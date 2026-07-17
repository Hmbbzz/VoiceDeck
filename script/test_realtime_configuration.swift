import Darwin
import Foundation

@main
struct RealtimeConfigurationRegressionTests {
    static func main() {
        var failures: [String] = []

        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { failures.append(message) }
        }

        let endpoint = QwenRealtimeConfiguration.endpoint(workspaceID: "llm-example")
        expect(endpoint?.scheme == "wss", "WebSocket endpoint must use wss")
        expect(endpoint?.host == "llm-example.cn-beijing.maas.aliyuncs.com", "Endpoint must use the workspace domain")
        expect(URLComponents(url: endpoint!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "qwen3.5-omni-flash-realtime", "Endpoint must use the configured realtime model")
        expect(QwenRealtimeConfiguration.endpoint(workspaceID: "https://llm-example") == nil, "Endpoint must reject a URL instead of a workspace ID")
        expect(QwenRealtimeConfiguration.endpoint(workspaceID: "   ") == nil, "Endpoint must reject an empty workspace ID")

        let session = QwenRealtimeConfiguration.sessionUpdateEvent(voice: "Tina")["session"] as? [String: Any]
        expect(QwenRealtimeConfiguration.defaultVoice == "Tina", "Qwen3.5 Realtime must default to the supported Tina voice")
        expect(QwenRealtimeConfiguration.voices.map(\.id).contains("Ethan"), "Voice picker must expose the supported Ethan voice")
        expect(session?["voice"] as? String == "Tina", "Session must send the configured voice")
        expect(session?["input_audio_format"] as? String == "pcm", "Input audio must be PCM")
        expect(session?["output_audio_format"] as? String == "pcm", "Output audio must be PCM")
        expect(session?["turn_detection"] is NSNull, "Push-to-talk must disable server VAD")
        expect((session?["input_audio_transcription"] as? [String: Any])?["model"] as? String == "qwen3-asr-flash-realtime", "Session must request the supported ASR model")

        guard failures.isEmpty else {
            failures.forEach { fputs("FAIL: \($0)\n", stderr) }
            exit(EXIT_FAILURE)
        }
        print("Realtime configuration regression tests passed.")
    }
}
