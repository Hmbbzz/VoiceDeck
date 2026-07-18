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

@MainActor
@Observable
final class VoiceSessionController {
    var state: VoiceSessionState = .idle
    var pendingWindowContextName: String?

    private let realtime = QwenRealtimeClient()
    private let player = PCMPlayer()
    private var captureEngine: AVAudioEngine?
    private var currentConversationID: UUID?
    private var lastVoiceInteractionAt: Date?
    private var userTranscript = ""
    private var assistantTranscript = ""
    private var hasSavedUserTranscript = false
    private var pendingWindowContext: CapturedWindowContext?
    private var didSendPendingWindowContext = false
    private var sentWindowContextName: String?
    private var startsCaptureWhenRealtimeIsReady = false
    private var hasCapturedAudibleAudio = false
    private var peakAudioLevel: Int16 = 0
    private let logger = Logger(subsystem: "com.voicedeck.app", category: "voice")

    init() {
        realtime.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
    }

    func beginRecording() {
        guard case .idle = state else { return }
        guard let store = activeStore else {
            state = .failed("无法确定当前对话，请从主窗口重新开始。")
            return
        }
        guard let apiKey = KeychainStore.value(for: .dashScopeAPIKey), !apiKey.isEmpty else {
            state = .failed("请先在设置中填写 DashScope API Key。")
            return
        }
        let workspaceID = UserDefaults.standard.string(forKey: "voiceDeck.dashScopeWorkspaceID")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !workspaceID.isEmpty else {
            state = .failed("请先在设置中填写百炼业务空间 ID。")
            return
        }

        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else {
                state = .failed("请在系统设置中允许 Voice Deck 使用麦克风。")
                return
            }

            let (conversationID, reusesSession) = conversation(for: store)
            currentConversationID = conversationID
            lastVoiceInteractionAt = .now
            userTranscript = ""
            assistantTranscript = ""
            hasSavedUserTranscript = false
            didSendPendingWindowContext = false
            sentWindowContextName = nil
            player.stop()

            if !reusesSession || !realtime.isConnected {
                realtime.disconnect()
                do {
                    try realtime.connect(apiKey: apiKey, workspaceID: workspaceID)
                    startsCaptureWhenRealtimeIsReady = true
                    state = .recording
                } catch {
                    state = .failed(error.localizedDescription)
                    return
                }
            } else {
                realtime.refreshConfigurationIfNeeded()
                try startAudioCapture()
                state = .recording
            }
        }
    }

    func beginRecording(in store: ConversationStore) {
        activeStore = store
        beginRecording()
    }

    func endRecording(in store: ConversationStore) {
        activeStore = store
        guard state == .recording else { return }
        startsCaptureWhenRealtimeIsReady = false
        stopAudioCapture()
        logger.info("Finished microphone capture with peak PCM level: \(self.peakAudioLevel, privacy: .public)")
        guard hasCapturedAudibleAudio else {
            state = .failed("没有检测到可用的麦克风声音。请检查系统输入设备和 Voice Deck 的麦克风权限后重试。")
            return
        }
        state = .thinking
        realtime.commitAudio()
    }

    func cancel() {
        startsCaptureWhenRealtimeIsReady = false
        stopAudioCapture()
        player.stop()
        if state == .thinking { realtime.cancelResponse() }
        state = .idle
    }

    func captureFrontmostWindowContext(in store: ConversationStore, onResult: @escaping (Bool) -> Void = { _ in }) {
        activeStore = store
        Task {
            do {
                let context = try await WindowCaptureService.captureFrontmostWindow()
                pendingWindowContext = context
                pendingWindowContextName = context.displayName
                didSendPendingWindowContext = false
                onResult(true)
            } catch {
                state = .failed(error.localizedDescription)
                onResult(false)
            }
        }
    }

    private weak var activeStore: ConversationStore?

    private func conversation(for store: ConversationStore) -> (UUID, Bool) {
        let continuationWindow = UserDefaults.standard.object(forKey: "voiceDeck.continuationWindow") as? Double ?? 120
        let canReuse = lastVoiceInteractionAt.map { Date.now.timeIntervalSince($0) <= continuationWindow } ?? false

        if canReuse, let currentConversationID, store.containsConversation(currentConversationID) {
            store.selectedConversationID = currentConversationID
            return (currentConversationID, true)
        }

        store.createConversation()
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
        case let .userTranscript(transcript):
            userTranscript = transcript
            guard !hasSavedUserTranscript, !transcript.isEmpty else { return }
            store.append(ChatMessage(role: .user, content: transcriptWithWindowContext(transcript)), to: conversationID)
            hasSavedUserTranscript = true
        case let .assistantTranscript(delta):
            assistantTranscript += delta
        case let .audio(data):
            player.play(data)
        case .responseFinished:
            if !hasSavedUserTranscript {
                let fallback = userTranscript.isEmpty ? "语音提问" : userTranscript
                store.append(ChatMessage(role: .user, content: transcriptWithWindowContext(fallback)), to: conversationID)
            }
            if !assistantTranscript.isEmpty {
                store.append(ChatMessage(role: .assistant, content: assistantTranscript), to: conversationID)
            }
            state = .idle
        case let .failed(message):
            stopAudioCapture()
            player.stop()
            state = .failed(message)
        }
    }

    private func startAudioCapture() throws {
        stopAudioCapture()
        hasCapturedAudibleAudio = false
        peakAudioLevel = 0
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

        input.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { [weak self, converter] buffer, _ in
            guard let audio = Self.convert(buffer, using: converter, outputFormat: outputFormat) else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.recordAudioLevel(in: audio)
                self.realtime.appendAudio(audio)
                self.sendPendingWindowContextIfNeeded()
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
    }

    private func recordAudioLevel(in audio: Data) {
        let peak = audio.withUnsafeBytes { samples -> Int16 in
            guard let base = samples.bindMemory(to: Int16.self).baseAddress else { return 0 }
            return (0 ..< audio.count / MemoryLayout<Int16>.size).reduce(0) { currentPeak, index in
                max(currentPeak, Int16(clamping: abs(Int(base[index]))) )
            }
        }
        peakAudioLevel = max(peakAudioLevel, peak)
        if peak >= 320 { hasCapturedAudibleAudio = true }
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

    private func sendPendingWindowContextIfNeeded() {
        guard !didSendPendingWindowContext, let pendingWindowContext else { return }
        realtime.appendImage(pendingWindowContext.imageData)
        didSendPendingWindowContext = true
        sentWindowContextName = pendingWindowContext.displayName
        self.pendingWindowContext = nil
        pendingWindowContextName = nil
    }

    private func transcriptWithWindowContext(_ transcript: String) -> String {
        guard let sentWindowContextName else { return transcript }
        return "\(transcript)\n\n[包含窗口截图：\(sentWindowContextName)]"
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
