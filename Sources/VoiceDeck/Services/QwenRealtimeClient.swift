import Foundation

enum QwenRealtimeEvent {
    case ready
    case userTranscript(String)
    case assistantTranscript(String)
    case audio(Data)
    case responseFinished
    case failed(String)
}

@MainActor
final class QwenRealtimeClient {
    var onEvent: ((QwenRealtimeEvent) -> Void)?

    // A socket is reusable only after the server accepts the session configuration.
    var isConnected: Bool { task != nil && isReady }

    private var task: URLSessionWebSocketTask?
    private var queuedEvents: [[String: Any]] = []
    private var outboundMessages: [String] = []
    private var isReady = false
    private var isSending = false
    private var shouldCreateResponse = false
    private var configuredVoice: String?

    func connect(apiKey: String, workspaceID: String) throws {
        disconnect()
        guard let url = QwenRealtimeConfiguration.endpoint(workspaceID: workspaceID) else {
            throw QwenRealtimeError.invalidWorkspace
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let socket = URLSession.shared.webSocketTask(with: request)
        task = socket
        socket.resume()
        receiveNext(from: socket)
    }

    func appendAudio(_ audio: Data) {
        send([
            "type": "input_audio_buffer.append",
            "audio": audio.base64EncodedString()
        ])
    }

    func appendImage(_ image: Data) {
        send([
            "type": "input_image_buffer.append",
            "image": image.base64EncodedString()
        ])
    }

    func commitAudio() {
        shouldCreateResponse = true
        send(["type": "input_audio_buffer.commit"])
    }

    func cancelResponse() {
        send(["type": "response.cancel"])
    }

    func refreshConfigurationIfNeeded() {
        guard isReady, configuredVoice != QwenRealtimeConfiguration.selectedVoice else { return }
        configuredVoice = QwenRealtimeConfiguration.selectedVoice
        sendImmediately(QwenRealtimeConfiguration.sessionUpdateEvent(voice: configuredVoice!))
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        resetConnectionState()
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
            if case let .string(text) = message {
                handle(text)
            } else if case let .data(data) = message, let text = String(data: data, encoding: .utf8) {
                handle(text)
            }
            receiveNext(from: socket)
        case let .failure(error):
            failConnection(message: error.localizedDescription)
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else { return }

        switch type {
        case "session.created":
            configuredVoice = QwenRealtimeConfiguration.selectedVoice
            sendImmediately(QwenRealtimeConfiguration.sessionUpdateEvent(voice: configuredVoice!))
        case "session.updated":
            isReady = true
            let pending = queuedEvents
            queuedEvents.removeAll()
            pending.forEach(sendImmediately)
            emit(.ready)
        case "input_audio_buffer.committed":
            if shouldCreateResponse {
                shouldCreateResponse = false
                send(["type": "response.create"])
            }
        case "conversation.item.input_audio_transcription.completed":
            if let transcript = event["transcript"] as? String {
                emit(.userTranscript(transcript))
            }
        case "response.audio_transcript.delta", "response.text.delta":
            if let transcript = (event["delta"] ?? event["transcript"]) as? String {
                emit(.assistantTranscript(transcript))
            }
        case "response.audio.delta":
            if let encoded = event["delta"] as? String, let audio = Data(base64Encoded: encoded) {
                emit(.audio(audio))
            }
        case "response.done":
            emit(.responseFinished)
        case "error":
            let details = event["error"] as? [String: Any]
            failConnection(message: details?["message"] as? String)
        default:
            break
        }
    }

    private func send(_ event: [String: Any]) {
        guard isReady else {
            queuedEvents.append(event)
            return
        }
        sendImmediately(event)
    }

    private func sendImmediately(_ event: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: event),
              let text = String(data: data, encoding: .utf8) else { return }
        outboundMessages.append(text)
        sendNextMessage()
    }

    private func sendNextMessage() {
        guard !isSending, let socket = task, !outboundMessages.isEmpty else { return }
        isSending = true
        let message = outboundMessages[0]

        socket.send(.string(message)) { [weak self] error in
            Task { @MainActor in
                guard let self, socket === self.task else { return }
                self.isSending = false
                if error == nil {
                    self.outboundMessages.removeFirst()
                    self.sendNextMessage()
                } else {
                    self.failConnection(message: error?.localizedDescription)
                }
            }
        }
    }

    private func failConnection(message: String? = nil) {
        task?.cancel(with: .goingAway, reason: nil)
        resetConnectionState()
        let explanation = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        if explanation?.localizedCaseInsensitiveContains("voice") == true,
           explanation?.localizedCaseInsensitiveContains("not supported") == true {
            emit(.failed("百炼不支持当前音色配置。请更新到最新版后重新尝试。"))
        } else {
            let details = explanation?.isEmpty == false ? "（\(explanation!)）" : ""
            emit(.failed("无法连接百炼实时服务\(details)。请检查业务空间 ID、API Key 是否属于北京地域，然后重试。"))
        }
    }

    private func resetConnectionState() {
        task = nil
        queuedEvents.removeAll()
        outboundMessages.removeAll()
        isReady = false
        isSending = false
        shouldCreateResponse = false
        configuredVoice = nil
    }

    private func emit(_ event: QwenRealtimeEvent) {
        onEvent?(event)
    }
}

private enum QwenRealtimeError: LocalizedError {
    case invalidWorkspace

    var errorDescription: String? {
        "业务空间 ID 格式无效，请只填写类似 llm-xxxx 的 ID。"
    }
}
