import Foundation

enum QwenRealtimeConfiguration {
    static let model = "qwen3.5-omni-flash-realtime"
    static let defaultVoice = "Tina"
    static let voicePreferenceKey = "voiceDeck.qwenVoice"

    static let voices = [
        QwenVoice(id: "Tina", name: "Tina", description: "温暖、清晰"),
        QwenVoice(id: "Cindy", name: "Cindy", description: "轻柔台湾腔"),
        QwenVoice(id: "Sunnybobi", name: "Sunnybobi", description: "自然、邻家感"),
        QwenVoice(id: "Raymond", name: "Raymond", description: "明亮男声"),
        QwenVoice(id: "Ethan", name: "Ethan", description: "温暖北方男声")
    ]

    static var selectedVoice: String {
        let savedVoice = UserDefaults.standard.string(forKey: voicePreferenceKey) ?? defaultVoice
        return voices.contains(where: { $0.id == savedVoice }) ? savedVoice : defaultVoice
    }

    static func endpoint(workspaceID: String) -> URL? {
        let workspace = workspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard workspace.range(of: "^[A-Za-z0-9-]+$", options: .regularExpression) != nil else {
            return nil
        }
        return URL(string: "wss://\(workspace).cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime?model=\(model)")
    }

    static func sessionUpdateEvent(voice: String = selectedVoice) -> [String: Any] {
        [
            "type": "session.update",
            "session": [
                "modalities": ["text", "audio"],
                "voice": voice,
                "instructions": "你是 Voice Deck 的桌面语音助手。用简洁、自然的中文回答。",
                "input_audio_format": "pcm",
                "output_audio_format": "pcm",
                "turn_detection": NSNull(),
                "input_audio_transcription": [
                    "model": "qwen3-asr-flash-realtime",
                    "language": "zh"
                ]
            ]
        ]
    }
}

struct QwenVoice: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
}
