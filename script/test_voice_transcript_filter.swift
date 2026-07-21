import Darwin
import Foundation

@main
struct VoiceTranscriptFilterTests {
    static func main() {
        let rejected = ["", "  ", "system", "SYSTEM", "assistant", "developer", "tool", "系统", "助手", "<|system|>", "[assistant]"]
        let accepted = ["system design", "帮我总结这段内容", "hello world"]

        for value in rejected where VoiceTranscriptFilter.sanitized(value) != nil {
            fputs("FAIL: expected to reject \(value)\n", stderr)
            exit(EXIT_FAILURE)
        }
        for value in accepted where VoiceTranscriptFilter.sanitized(value) != value {
            fputs("FAIL: expected to preserve \(value)\n", stderr)
            exit(EXIT_FAILURE)
        }
        print("Voice transcript filter tests passed.")
    }
}
