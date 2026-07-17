@preconcurrency import AVFoundation
import Foundation
import Observation

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

    private let realtime = QwenRealtimeClient()
    private let player = PCMPlayer()
    private var captureEngine: AVAudioEngine?
    private var currentConversationID: UUID?
    private var lastVoiceInteractionAt: Date?
    private var userTranscript = ""
    private var assistantTranscript = ""
    private var hasSavedUserTranscript = false

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
            player.stop()

            if !reusesSession || !realtime.isConnected {
                realtime.disconnect()
                do {
                    try realtime.connect(apiKey: apiKey, workspaceID: workspaceID)
                } catch {
                    state = .failed(error.localizedDescription)
                    return
                }
            } else {
                realtime.refreshConfigurationIfNeeded()
            }

            do {
                try startAudioCapture()
                state = .recording
            } catch {
                state = .failed("无法开始录音：\(error.localizedDescription)")
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
        stopAudioCapture()
        state = .thinking
        realtime.commitAudio()
    }

    func cancel() {
        stopAudioCapture()
        player.stop()
        if state == .thinking { realtime.cancelResponse() }
        state = .idle
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
            break
        case let .userTranscript(transcript):
            userTranscript = transcript
            guard !hasSavedUserTranscript, !transcript.isEmpty else { return }
            store.append(ChatMessage(role: .user, content: transcript), to: conversationID)
            hasSavedUserTranscript = true
        case let .assistantTranscript(delta):
            assistantTranscript += delta
        case let .audio(data):
            player.play(data)
        case .responseFinished:
            if !hasSavedUserTranscript {
                store.append(ChatMessage(role: .user, content: userTranscript.isEmpty ? "语音提问" : userTranscript), to: conversationID)
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
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
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
                self?.realtime.appendAudio(audio)
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
}

private enum VoiceCaptureError: LocalizedError {
    case unsupportedFormat

    var errorDescription: String? {
        "当前麦克风不支持所需的音频格式。"
    }
}
