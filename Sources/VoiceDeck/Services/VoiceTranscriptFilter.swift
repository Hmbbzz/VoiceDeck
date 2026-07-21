import Foundation

enum VoiceTranscriptFilter {
    private static let protocolLabels: Set<String> = [
        "system", "user", "assistant", "developer", "tool",
        "系统", "用户", "助手", "开发者", "工具"
    ]

    static func sanitized(_ value: String) -> String? {
        let transcript = value
            .replacingOccurrences(of: "\u{200B}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return nil }

        let canonical = transcript.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) || $0.properties.isIdeographic }
            .map(String.init)
            .joined()
        guard !protocolLabels.contains(canonical) else { return nil }
        guard !isProtocolEnvelope(transcript) else { return nil }
        return transcript
    }

    private static func isProtocolEnvelope(_ transcript: String) -> Bool {
        let normalized = transcript
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
        return ["<|system|>", "<|user|>", "<|assistant|>", "[system]", "[user]", "[assistant]"]
            .contains(normalized)
    }
}
