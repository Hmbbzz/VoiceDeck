@preconcurrency import AVFoundation
import Foundation
import Observation
import OSLog

enum VoiceSessionState: Equatable {
    case idle
    case recording
    case thinking
    case failed(String)
}

enum WindowCaptureStatus: Equatable {
    case capturing
    case attached(String)
    case failed
}

@MainActor
@Observable
final class VoiceSessionController {
    var state: VoiceSessionState = .idle
    var pendingWindowContextName: String?
    var liveTranscript = ""
    var audioActivity: Double = 0
    var windowCaptureStatus: WindowCaptureStatus?
    var isSpeaking = false

    private let realtime = QwenRealtimeClient()
    private let speech = BailianTextToSpeech()
    private var captureEngine: AVAudioEngine?
    private var currentConversationID: UUID?
    private var userTranscript = ""
    private var assistantTranscript = ""
    private var hasSavedUserTranscript = false
    private var pendingWindowAttachment: ChatAttachment?
    private var windowCaptureTask: Task<Void, Never>?
    private var currentUserMessageID: ChatMessage.ID?
    private var providerResponseTask: Task<Void, Never>?
    private var titleGenerationTask: Task<Void, Never>?
    private var startsCaptureWhenRealtimeIsReady = false
    private var isPreparingRecording = false
    private var recordingPreparationID: UUID?
    private var hasReleasedRecording = false
    private var hasCapturedAudibleAudio = false
    private var consecutiveSpeechBufferCount = 0
    private var hasStartedSpeech = false
    private var speechPreRoll: [Data] = []
    private var noiseFloorDecibels = -60.0
    private var createdConversationForCurrentRecording = false
    private var peakAudioLevel: Int16 = 0
    private let logger = Logger(subsystem: "com.voicedeck.app", category: "voice")

    init() {
        speech.onPlaybackStateChange = { [weak self] isSpeaking in
            self?.isSpeaking = isSpeaking
        }
        realtime.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
    }

    func beginRecording() {
        if case .thinking = state {
            interruptCurrentTurn()
        } else if case .failed = state {
            state = .idle
        }
        guard case .idle = state, !isPreparingRecording else { return }
        guard let store = activeStore else {
            state = .failed("无法确定当前对话，请从主窗口重新开始。")
            return
        }
        guard validateRecordingConfiguration() else { return }
        startRecording(in: store)
    }

    func conversationModelDidChange() {
        if case .failed = state {
            state = .idle
        }
        if let configuration = try? ConversationProviderSettings.configuration(),
           let endpoint = configuration.endpoint {
            ConversationConnectionWarmup.warm(endpoint: endpoint)
        }
    }

    func dismissFailure() {
        if case .failed = state {
            state = .idle
        }
    }

    func stopSpeaking() {
        speech.stop()
    }

    private func validateRecordingConfiguration() -> Bool {
        guard let apiKey = KeychainStore.value(for: .dashScopeAPIKey), !apiKey.isEmpty else {
            state = .failed("请先在设置中填写 DashScope API Key。")
            return false
        }
        ConversationProviderSettings.markCredentialSaved(for: .qwen)
        let workspaceID = UserDefaults.standard.string(forKey: "voiceDeck.dashScopeWorkspaceID")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !workspaceID.isEmpty else {
            state = .failed("请先在设置中填写百炼业务空间 ID。")
            return false
        }
        let providerID = ConversationProviderSettings.selectedProviderID
        if providerID != .qwen {
            guard validateConversationProviderConfiguration() else { return false }
        }
        return true
    }

    private func validateConversationProviderConfiguration() -> Bool {
        let providerID = ConversationProviderSettings.selectedProviderID
        let keyReference = ConversationProviderSettings.keychainReference(for: providerID)
        guard let providerAPIKey = KeychainStore.value(forReference: keyReference), !providerAPIKey.isEmpty else {
            state = .failed("请先在设置中配置 \(providerID.displayName) API Key。")
            return false
        }
        ConversationProviderSettings.markCredentialSaved(for: providerID)
        return true
    }

    private func startRecording(in store: ConversationStore) {
        guard let apiKey = KeychainStore.value(for: .dashScopeAPIKey), !apiKey.isEmpty else { return }
        let workspaceID = UserDefaults.standard.string(forKey: "voiceDeck.dashScopeWorkspaceID")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !workspaceID.isEmpty else { return }
        isPreparingRecording = true
        let preparationID = UUID()
        recordingPreparationID = preparationID
        hasReleasedRecording = false
        liveTranscript = ""
        audioActivity = 0
        resetVoiceActivityGate()
        state = .recording

        Task {
            defer {
                if recordingPreparationID == preparationID {
                    isPreparingRecording = false
                    recordingPreparationID = nil
                }
            }
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else {
                state = .failed("请在系统设置中允许 Voice Deck 使用麦克风。")
                return
            }
            guard recordingPreparationID == preparationID, state == .recording else { return }

            let (conversationID, _) = conversation(for: store)
            currentConversationID = conversationID
            userTranscript = ""
            assistantTranscript = ""
            hasSavedUserTranscript = false
            currentUserMessageID = nil
            speech.stop()

            if !realtime.isConnected {
                realtime.disconnect()
                do {
                    try realtime.connect(apiKey: apiKey, workspaceID: workspaceID)
                    startsCaptureWhenRealtimeIsReady = true
                } catch {
                    state = .failed(error.localizedDescription)
                    return
                }
            } else {
                realtime.refreshConfigurationIfNeeded()
                realtime.clearAudio()
                try startAudioCapture()
            }
        }
    }

    func beginRecording(in store: ConversationStore) {
        activeStore = store
        windowCaptureStatus = nil
        beginRecording()
    }

    func sendText(_ text: String, in store: ConversationStore) {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        if case .failed = state { state = .idle }
        guard case .idle = state else { return }
        guard validateConversationProviderConfiguration() else { return }

        activeStore = store
        if store.selectedConversationID == nil {
            store.createConversation()
        }
        guard let conversationID = store.selectedConversationID else {
            state = .failed("无法确定当前对话。")
            return
        }

        currentConversationID = conversationID
        currentUserMessageID = nil
        hasSavedUserTranscript = false
        saveUserTranscript(content, in: store, conversationID: conversationID)
        state = .thinking
        startExternalConversation(in: store, conversationID: conversationID)
    }

    func attachImage(data: Data, fileName: String, mimeType: String) throws {
        let displayName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingWindowAttachment = try AttachmentStore().saveImage(
            data,
            mimeType: mimeType,
            displayName: displayName.isEmpty ? "图片附件" : displayName
        )
        pendingWindowContextName = displayName.isEmpty ? "图片附件" : displayName
    }

    func beginRecordingWithWindowContext(
        in store: ConversationStore,
        onCaptureResult: @escaping (Bool) -> Void = { _ in }
    ) {
        guard case .idle = state else { return }
        activeStore = store
        pendingWindowAttachment = nil
        pendingWindowContextName = "正在截取窗口"
        windowCaptureStatus = .capturing
        guard validateRecordingConfiguration() else {
            pendingWindowContextName = nil
            windowCaptureStatus = nil
            return
        }
        captureWindowContext(in: store, shouldFailSession: false, onResult: onCaptureResult)
        startRecording(in: store)
    }

    func endRecording(in store: ConversationStore) {
        activeStore = store
        guard state == .recording else { return }
        startsCaptureWhenRealtimeIsReady = false
        isPreparingRecording = false
        recordingPreparationID = nil
        hasReleasedRecording = true
        stopAudioCapture()
        logger.info("Finished microphone capture with peak PCM level: \(self.peakAudioLevel, privacy: .public)")
        guard hasCapturedAudibleAudio else {
            realtime.clearAudio()
            discardSilentRecording(in: store)
            state = .idle
            return
        }
        state = .thinking
        realtime.commitAudio(createResponse: false)
        submitTranscriptIfReady(in: store)
    }

    func cancel() {
        startsCaptureWhenRealtimeIsReady = false
        isPreparingRecording = false
        recordingPreparationID = nil
        hasReleasedRecording = false
        stopAudioCapture()
        realtime.clearAudio()
        if let activeStore {
            discardSilentRecording(in: activeStore)
        }
        speech.stop()
        providerResponseTask?.cancel()
        providerResponseTask = nil
        if state == .thinking { realtime.cancelResponse() }
        state = .idle
    }

    func captureFrontmostWindowContext(in store: ConversationStore, onResult: @escaping (Bool) -> Void = { _ in }) {
        activeStore = store
        captureWindowContext(in: store, shouldFailSession: true, onResult: onResult)
    }

    private func captureWindowContext(
        in store: ConversationStore,
        shouldFailSession: Bool,
        onResult: @escaping (Bool) -> Void
    ) {
        windowCaptureTask?.cancel()
        windowCaptureTask = Task {
            do {
                let context = try await WindowCaptureService.captureFrontmostWindow()
                guard !Task.isCancelled else { return }
                pendingWindowContextName = context.displayName
                windowCaptureStatus = .attached(context.displayName)
                let attachment = try AttachmentStore().saveImage(
                    context.imageData,
                    mimeType: "image/jpeg",
                    displayName: context.displayName,
                    screenshotSource: .init(applicationName: context.ownerName, windowTitle: context.windowTitle)
                )
                guard !Task.isCancelled else {
                    try? AttachmentStore().delete(attachment)
                    return
                }
                pendingWindowAttachment = attachment
                if let conversationID = currentConversationID, let messageID = currentUserMessageID {
                    store.addAttachment(attachment, to: messageID, in: conversationID)
                    pendingWindowAttachment = nil
                }
                onResult(true)
            } catch {
                pendingWindowContextName = nil
                windowCaptureStatus = .failed
                if shouldFailSession {
                    state = .failed(error.localizedDescription)
                }
                onResult(false)
            }
        }
    }

    private weak var activeStore: ConversationStore?

    private func conversation(for store: ConversationStore) -> (UUID, Bool) {
        if let selectedConversation = store.selectedConversation, !selectedConversation.isArchived {
            createdConversationForCurrentRecording = false
            currentConversationID = selectedConversation.id
            return (selectedConversation.id, true)
        }

        if let currentConversationID, store.containsConversation(currentConversationID) {
            createdConversationForCurrentRecording = false
            store.selectedConversationID = currentConversationID
            return (currentConversationID, true)
        }

        store.createConversation()
        createdConversationForCurrentRecording = true
        return (store.selectedConversationID ?? UUID(), false)
    }

    private func handle(_ event: QwenRealtimeEvent) {
        guard let store = activeStore, let conversationID = currentConversationID else { return }

        switch event {
        case .ready:
            guard startsCaptureWhenRealtimeIsReady, state == .recording else { return }
            startsCaptureWhenRealtimeIsReady = false
            do {
                try startAudioCapture()
            } catch {
                state = .failed("无法开始录音：\(error.localizedDescription)")
            }
        case let .userTranscriptPreview(transcript):
            guard state == .recording,
                  hasCapturedAudibleAudio,
                  let transcript = VoiceTranscriptFilter.sanitized(transcript) else { return }
            liveTranscript = transcript
        case let .userTranscript(transcript):
            guard (state == .recording || state == .thinking || hasReleasedRecording),
                  hasCapturedAudibleAudio,
                  let transcript = VoiceTranscriptFilter.sanitized(transcript) else { return }
            userTranscript = transcript
            liveTranscript = transcript
            submitTranscriptIfReady(in: store)
        case let .assistantTranscript(delta):
            assistantTranscript += delta
        case let .audio(data):
            _ = data
        case .responseFinished:
            guard hasSavedUserTranscript else {
                liveTranscript = ""
                state = .idle
                return
            }
            if !assistantTranscript.isEmpty {
                store.append(ChatMessage(role: .assistant, content: assistantTranscript), to: conversationID)
            }
            state = .idle
        case let .failed(message):
            stopAudioCapture()
            isPreparingRecording = false
            recordingPreparationID = nil
            hasReleasedRecording = false
            speech.stop()
            state = .failed(message)
        }
    }

    private func startAudioCapture() throws {
        stopAudioCapture()
        peakAudioLevel = 0
        resetVoiceActivityGate()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let selectedDeviceName = try configureInputDevice(for: input)
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw VoiceCaptureError.inputUnavailable
        }
        if let selectedDeviceName {
            logger.info("Using selected microphone: \(selectedDeviceName, privacy: .public)")
        }
        logger.info("Starting microphone capture at \(inputFormat.sampleRate, privacy: .public) Hz with \(inputFormat.channelCount, privacy: .public) channel(s)")
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ), let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw VoiceCaptureError.unsupportedFormat
        }

        input.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { [weak self, converter] buffer, _ in
            guard let audio = Self.convert(buffer, using: converter, outputFormat: outputFormat) else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.forwardAudioForTranscription(audio)
            }
        }
        engine.prepare()
        try engine.start()
        captureEngine = engine
    }

    private func stopAudioCapture() {
        captureEngine?.inputNode.removeTap(onBus: 0)
        captureEngine?.stop()
        captureEngine = nil
        audioActivity = 0
    }

    private func forwardAudioForTranscription(_ audio: Data) {
        recordAudioLevel(in: audio)
        guard hasStartedSpeech else {
            speechPreRoll.append(audio)
            if speechPreRoll.count > 6 {
                speechPreRoll.removeFirst()
            }
            guard hasCapturedAudibleAudio else { return }
            hasStartedSpeech = true
            speechPreRoll.forEach(realtime.appendAudio)
            speechPreRoll.removeAll()
            return
        }
        realtime.appendAudio(audio)
    }

    private func recordAudioLevel(in audio: Data) {
        let metrics = audio.withUnsafeBytes { samples -> (peak: Int16, decibels: Double) in
            guard let base = samples.bindMemory(to: Int16.self).baseAddress else { return (0, -90) }
            let count = audio.count / MemoryLayout<Int16>.size
            guard count > 0 else { return (0, -90) }

            var peak: Int16 = 0
            var sumOfSquares = 0.0
            for index in 0 ..< count {
                let sample = Int(base[index])
                peak = max(peak, Int16(clamping: abs(sample)))
                let normalized = Double(sample) / Double(Int16.max)
                sumOfSquares += normalized * normalized
            }
            let rms = sqrt(sumOfSquares / Double(count))
            return (peak, 20 * log10(max(rms, 0.000_01)))
        }
        let peak = metrics.peak
        peakAudioLevel = max(peakAudioLevel, peak)
        let decibels = metrics.decibels
        let normalized = min(max((decibels + 50) / 32, 0), 1)
        let response = normalized > audioActivity ? 0.62 : 0.18
        audioActivity += (normalized - audioActivity) * response

        // A short peak is typically keyboard or ambient noise. Require about
        // 320 ms of energy above the adaptive noise floor before audio reaches ASR.
        let speechThreshold = max(noiseFloorDecibels + 14, -36)
        let isSpeechCandidate = decibels >= speechThreshold
        if !hasStartedSpeech && !isSpeechCandidate {
            noiseFloorDecibels = noiseFloorDecibels * 0.92 + decibels * 0.08
        }
        if isSpeechCandidate {
            consecutiveSpeechBufferCount += 1
        } else {
            consecutiveSpeechBufferCount = max(0, consecutiveSpeechBufferCount - 2)
        }
        if consecutiveSpeechBufferCount >= 5 { hasCapturedAudibleAudio = true }
    }

    private func resetVoiceActivityGate() {
        hasCapturedAudibleAudio = false
        consecutiveSpeechBufferCount = 0
        hasStartedSpeech = false
        speechPreRoll.removeAll()
        noiseFloorDecibels = -60
    }

    private func discardSilentRecording(in store: ConversationStore) {
        liveTranscript = ""
        userTranscript = ""
        assistantTranscript = ""
        hasSavedUserTranscript = false
        hasReleasedRecording = false
        resetVoiceActivityGate()

        windowCaptureTask?.cancel()
        windowCaptureTask = nil
        if let pendingWindowAttachment {
            try? AttachmentStore().delete(pendingWindowAttachment)
        }
        pendingWindowAttachment = nil
        pendingWindowContextName = nil
        windowCaptureStatus = nil

        if createdConversationForCurrentRecording,
           let currentConversationID,
           store.messages(for: currentConversationID).isEmpty {
            store.delete(currentConversationID)
            self.currentConversationID = nil
        }
        createdConversationForCurrentRecording = false
    }

    private static func convert(
        _ input: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        outputFormat: AVAudioFormat
    ) -> Data? {
        let ratio = outputFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio + 1)
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return input
        }
        guard status != .error, error == nil, let samples = output.int16ChannelData?[0] else { return nil }
        return Data(bytes: samples, count: Int(output.frameLength) * MemoryLayout<Int16>.size)
    }

    private func saveUserTranscript(_ transcript: String, in store: ConversationStore, conversationID: UUID) {
        let attachments = pendingWindowAttachment.map { [$0] } ?? []
        let message = ChatMessage(role: .user, content: transcript, attachments: attachments)
        store.append(message, to: conversationID)
        currentUserMessageID = message.id
        pendingWindowAttachment = nil
        pendingWindowContextName = nil
        hasSavedUserTranscript = true
        createdConversationForCurrentRecording = false
    }

    private func submitTranscriptIfReady(in store: ConversationStore) {
        guard hasReleasedRecording,
              !hasSavedUserTranscript,
              let conversationID = currentConversationID,
              let transcript = VoiceTranscriptFilter.sanitized(userTranscript) else { return }
        saveUserTranscript(transcript, in: store, conversationID: conversationID)
        startExternalConversation(in: store, conversationID: conversationID)
    }

    private func interruptCurrentTurn() {
        startsCaptureWhenRealtimeIsReady = false
        isPreparingRecording = false
        recordingPreparationID = nil
        hasReleasedRecording = false
        stopAudioCapture()
        realtime.clearAudio()
        speech.stop()
        providerResponseTask?.cancel()
        providerResponseTask = nil
        windowCaptureTask?.cancel()
        windowCaptureTask = nil
        if let pendingWindowAttachment {
            try? AttachmentStore().delete(pendingWindowAttachment)
        }
        pendingWindowAttachment = nil
        pendingWindowContextName = nil
        windowCaptureStatus = nil
        liveTranscript = ""
        state = .idle
    }

    private func startExternalConversation(in store: ConversationStore, conversationID: UUID) {
        providerResponseTask?.cancel()
        providerResponseTask = Task { [weak self] in
            guard let self else { return }
            do {
                // Option + X must finish attaching a successful capture before the model sees this turn.
                if let windowCaptureTask {
                    await windowCaptureTask.value
                }
                guard !Task.isCancelled else { return }
                let configuration = try ConversationProviderSettings.configuration()
                let provider = OpenAICompatibleConversationProvider(
                    configuration: configuration,
                    capabilities: ConversationProviderSettings.capabilities(for: configuration.providerID),
                    secretProvider: { reference in KeychainStore.value(forReference: reference) },
                    attachmentDataProvider: { attachment in try AttachmentStore().loadImage(for: attachment) }
                )
                let messages = recentMessages(in: store, conversationID: conversationID)
                let request = ConversationRequest(
                    systemPrompt: "你是 VoiceDeck 的桌面助手。用简洁、自然的中文回答。",
                    messages: messages
                )
                var response = ""
                var assistantMessageID: ChatMessage.ID?
                for try await event in provider.stream(request) {
                    if Task.isCancelled { return }
                    if case let .textDelta(delta) = event {
                        response += delta
                        if let assistantMessageID {
                            store.replaceContent(of: assistantMessageID, in: conversationID, with: response)
                        } else {
                            let message = ChatMessage(role: .assistant, content: response)
                            store.append(message, to: conversationID)
                            assistantMessageID = message.id
                        }
                    }
                }
                guard !Task.isCancelled else { return }
                generateConversationTitleIfNeeded(in: store, conversationID: conversationID)
                speech.speak(response, apiKey: KeychainStore.value(for: .dashScopeAPIKey))
                state = .idle
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed("无法连接 \(ConversationProviderSettings.selectedProviderID.displayName)：\(error.localizedDescription)")
            }
        }
    }

    private func recentMessages(in store: ConversationStore, conversationID: UUID) -> [ConversationMessage] {
        let continuationWindow = UserDefaults.standard.object(forKey: "voiceDeck.continuationWindow") as? Double ?? 120
        let cutoff = Date.now.addingTimeInterval(-continuationWindow)
        let messages = store.messages(for: conversationID)
        let recent = messages.filter { $0.createdAt >= cutoff }
        return (recent.isEmpty ? messages.suffix(1) : recent).map(ConversationMessage.init(chatMessage:))
    }

    private func generateConversationTitleIfNeeded(in store: ConversationStore, conversationID: UUID) {
        let messages = store.messages(for: conversationID)
        guard messages.count >= 2,
              let firstQuestion = messages.first(where: { $0.role == .user }),
              let firstAnswer = messages.first(where: { $0.role == .assistant }) else { return }

        titleGenerationTask?.cancel()
        titleGenerationTask = Task { [weak store] in
            guard let store else { return }
            let fallbackTitle = Self.fallbackTitle(from: firstQuestion.content)
            do {
                let configuration = try ConversationProviderSettings.configuration()
                let provider = OpenAICompatibleConversationProvider(
                    configuration: configuration,
                    capabilities: ConversationProviderSettings.capabilities(for: configuration.providerID),
                    secretProvider: { reference in KeychainStore.value(forReference: reference) },
                    attachmentDataProvider: { attachment in try AttachmentStore().loadImage(for: attachment) }
                )
                let request = ConversationRequest(
                    systemPrompt: "根据用户的首个问题和助手的首个回答，为这段对话生成一个 8 到 18 个汉字的简洁标题。只输出标题，不要引号、标点、前缀或解释。",
                    messages: [
                        ConversationMessage(role: .user, content: "用户首问：\(firstQuestion.content)\n\n助手首答：\(firstAnswer.content)")
                    ]
                )
                var generatedTitle = ""
                for try await event in provider.stream(request) {
                    guard !Task.isCancelled else { return }
                    if case let .textDelta(delta) = event {
                        generatedTitle += delta
                    }
                }
                guard !Task.isCancelled else { return }
                store.renameIfUntitled(conversationID, to: Self.normalizedTitle(generatedTitle) ?? fallbackTitle)
            } catch {
                guard !Task.isCancelled else { return }
                store.renameIfUntitled(conversationID, to: fallbackTitle)
            }
        }
    }

    private static func normalizedTitle(_ value: String) -> String? {
        let withoutPrefix = value
            .replacingOccurrences(of: "标题：", with: "")
            .replacingOccurrences(of: "标题:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let singleLine = withoutPrefix
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !singleLine.isEmpty else { return nil }
        return String(singleLine.prefix(24))
    }

    private static func fallbackTitle(from question: String) -> String {
        let title = question.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "新对话" : String(title.prefix(18))
    }
}

private enum VoiceCaptureError: LocalizedError {
    case unsupportedFormat
    case inputUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            "当前麦克风不支持所需的音频格式。"
        case .inputUnavailable:
            "当前选择的输入设备没有可用的麦克风通道。"
        }
    }
}
