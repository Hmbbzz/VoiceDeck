import Foundation
import OSLog

enum BailianTTSConfiguration {
    static let voicePreferenceKey = "voiceDeck.bailianTTSVoice"
    static let defaultVoice = "Cherry"

    static let voices = [
        BailianTTSVoice(id: "Cherry", name: "Cherry", description: "明快、自然女声"),
        BailianTTSVoice(id: "Serena", name: "Serena", description: "温柔、轻柔女声"),
        BailianTTSVoice(id: "Ethan", name: "Ethan", description: "温暖、清晰男声"),
        BailianTTSVoice(id: "Chelsie", name: "Chelsie", description: "活泼、二次元女声")
    ]

    static var selectedVoice: String {
        let savedVoice = UserDefaults.standard.string(forKey: voicePreferenceKey) ?? defaultVoice
        return voices.contains(where: { $0.id == savedVoice }) ? savedVoice : defaultVoice
    }
}

struct BailianTTSVoice: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
}

@MainActor
final class BailianTextToSpeech {
    private static let enabledPreferenceKey = "voiceDeck.playResponses"
    private static let endpoint = URL(string: "wss://dashscope.aliyuncs.com/api-ws/v1/realtime?model=qwen3-tts-flash-realtime")!

    private let player = PCMPlayer()
    private let logger = Logger(subsystem: "com.voicedeck.app", category: "tts")
    private var task: URLSessionWebSocketTask?
    private var outboundMessages: [String] = []
    private var isSending = false
    private var isConfigured = false
    private var pendingText = ""
    private var isFinishing = false
    private var isStreaming = false
    private(set) var isSpeaking = false {
        didSet { onPlaybackStateChange?(isSpeaking) }
    }

    var onPlaybackStateChange: ((Bool) -> Void)?

    init() {
        player.onPlaybackStateChange = { [weak self] _ in
            self?.updatePlaybackState()
        }
    }

    func speak(_ text: String, apiKey: String?) {
        let storedPreference = UserDefaults.standard.object(forKey: Self.enabledPreferenceKey) as? Bool
        guard storedPreference ?? true else { return }

        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        guard let apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            logger.notice("Skipped Bailian TTS because no DashScope API key is configured")
            return
        }

        stop()
        pendingText = content
        isStreaming = true
        updatePlaybackState()

        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let socket = URLSession.shared.webSocketTask(with: request)
        task = socket
        socket.resume()
        receiveNext(from: socket)
    }

    func stop() {
        player.stop()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        outboundMessages.removeAll()
        isSending = false
        isConfigured = false
        pendingText = ""
        isFinishing = false
        isStreaming = false
        updatePlaybackState()
    }

    private func receiveNext(from socket: URLSessionWebSocketTask) {
        socket.receive { [weak self] result in
            Task { @MainActor in
                self?.didReceive(result, from: socket)
            }
        }
    }

    private func didReceive(_ result: Result<URLSessionWebSocketTask.Message, Error>, from socket: URLSessionWebSocketTask) {
        guard socket === task else { return }

        switch result {
        case let .success(message):
            switch message {
            case let .string(text):
                handle(text, from: socket)
            case let .data(data):
                if let text = String(data: data, encoding: .utf8) {
                    handle(text, from: socket)
                }
            @unknown default:
                break
            }
            receiveNext(from: socket)
        case let .failure(error):
            guard !isFinishing else { return }
            logger.error("Bailian TTS socket failed: \(error.localizedDescription, privacy: .public)")
            resetConnection()
        }
    }

    private func handle(_ text: String, from socket: URLSessionWebSocketTask) {
        guard let data = text.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else { return }

        switch type {
        case "session.created":
            send(sessionUpdateEvent(), through: socket)
        case "session.updated":
            guard !isConfigured else { return }
            isConfigured = true
            let text = pendingText
            pendingText = ""
            send(["type": "input_text_buffer.append", "text": text], through: socket)
            send(["type": "input_text_buffer.commit"], through: socket)
        case "response.audio.delta":
            if let encoded = event["delta"] as? String, let audio = Data(base64Encoded: encoded) {
                player.play(audio)
            }
        case "response.audio.done":
            isFinishing = true
            isStreaming = false
            updatePlaybackState()
            send(["type": "session.finish"], through: socket)
        case "session.finished":
            resetConnection()
        case "error":
            let error = event["error"] as? [String: Any]
            let message = error?["message"] as? String ?? "未知错误"
            logger.error("Bailian TTS error: \(message, privacy: .public)")
            resetConnection()
        default:
            break
        }
    }

    private func sessionUpdateEvent() -> [String: Any] {
        [
            "event_id": eventID(),
            "type": "session.update",
            "session": [
                "voice": BailianTTSConfiguration.selectedVoice,
                "mode": "commit",
                "language_type": "Chinese",
                "response_format": "pcm",
                "sample_rate": 24_000
            ]
        ]
    }

    private func send(_ event: [String: Any], through socket: URLSessionWebSocketTask) {
        var payload = event
        if payload["event_id"] == nil {
            payload["event_id"] = eventID()
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        outboundMessages.append(text)
        sendNextMessage(through: socket)
    }

    private func sendNextMessage(through socket: URLSessionWebSocketTask) {
        guard !isSending, !outboundMessages.isEmpty else { return }
        isSending = true
        let message = outboundMessages[0]

        socket.send(.string(message)) { [weak self] error in
            Task { @MainActor in
                guard let self, socket === self.task else { return }
                self.isSending = false
                if let error {
                    self.logger.error("Unable to send Bailian TTS event: \(error.localizedDescription, privacy: .public)")
                    self.resetConnection()
                } else {
                    self.outboundMessages.removeFirst()
                    self.sendNextMessage(through: socket)
                }
            }
        }
    }

    private func resetConnection() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        outboundMessages.removeAll()
        isSending = false
        isConfigured = false
        pendingText = ""
        isFinishing = false
        isStreaming = false
        updatePlaybackState()
    }

    private func updatePlaybackState() {
        let nextState = isStreaming || player.isPlaying
        guard isSpeaking != nextState else { return }
        isSpeaking = nextState
    }

    private func eventID() -> String {
        "event_\(UUID().uuidString.lowercased())"
    }
}
