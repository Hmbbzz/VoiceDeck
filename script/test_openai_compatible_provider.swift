import Foundation

@main
struct OpenAICompatibleConversationProviderTests {
    static func main() {
        do {
            try testRequestEncoding()
            try testStreamParsing()
            try testErrors()
            print("OpenAI-compatible provider tests passed.")
        } catch {
            fputs("OpenAI-compatible provider tests failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func testRequestEncoding() throws {
        let configuration = try ConversationModelConfiguration(
            providerID: .openAI,
            model: "gpt-test",
            endpoint: URL(string: "https://example.com/v1/chat/completions")!,
            authentication: .apiKey(reference: "openai.test")
        )
        let image = ChatAttachment(
            fileName: "window.png",
            mimeType: "image/png",
            byteCount: 3,
            displayName: "Window"
        )
        let provider = OpenAICompatibleConversationProvider(
            configuration: configuration,
            secretProvider: { reference in reference == "openai.test" ? "secret-value" : nil },
            attachmentDataProvider: { attachment in
                precondition(attachment == image)
                return Data([0x01, 0x02, 0x03])
            }
        )
        let request = try provider.makeURLRequest(for: ConversationRequest(
            systemPrompt: "Be concise.",
            messages: [ConversationMessage(role: .user, content: "What is this?", attachments: [image])]
        ))

        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-value")
        precondition(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        let body = try JSONSerialization.jsonObject(with: try require(request.httpBody)) as! [String: Any]
        precondition(body["model"] as? String == "gpt-test")
        precondition(body["stream"] as? Bool == true)
        let messages = try require(body["messages"] as? [[String: Any]])
        let userContent = try require(messages.last?["content"] as? [[String: Any]])
        precondition(userContent[0]["type"] as? String == "text")
        let imageURL = try require((userContent[1]["image_url"] as? [String: Any])?["url"] as? String)
        precondition(imageURL == "data:image/png;base64,AQID")
    }

    private static func testStreamParsing() throws {
        let delta = try OpenAICompatibleConversationProvider.parseSSELine(
            "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}"
        )
        precondition(delta == .textDelta("Hello"))
        let ignoredEvent = try OpenAICompatibleConversationProvider.parseSSELine("event: message")
        let completedEvent = try OpenAICompatibleConversationProvider.parseSSELine("data: [DONE]")
        precondition(ignoredEvent == nil)
        precondition(completedEvent == .completed)
    }

    private static func testErrors() throws {
        let configuration = try ConversationModelConfiguration(
            providerID: .kimi,
            model: "kimi-test",
            endpoint: URL(string: "https://example.com/chat")!,
            authentication: .apiKey(reference: "missing")
        )
        let provider = OpenAICompatibleConversationProvider(
            configuration: configuration,
            secretProvider: { _ in nil },
            attachmentDataProvider: { _ in Data() }
        )
        do {
            _ = try provider.makeURLRequest(for: ConversationRequest(messages: []))
            preconditionFailure("A missing credential must be rejected")
        } catch OpenAICompatibleConversationProviderError.missingSecret("missing") {
            // Expected.
        }

        do {
            _ = try OpenAICompatibleConversationProvider.parseSSELine("data: not-json")
            preconditionFailure("Malformed JSON must be rejected")
        } catch OpenAICompatibleConversationProviderError.malformedEvent("not-json") {
            // Expected.
        }

        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 401,
            httpVersion: nil,
            headerFields: nil
        )!
        do {
            try OpenAICompatibleConversationProvider.validateHTTPResponse(response)
            preconditionFailure("Non-success HTTP status must be rejected")
        } catch OpenAICompatibleConversationProviderError.httpStatus(code: 401, message: nil) {
            // Expected.
        }
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw TestError.missingValue }
        return value
    }

    private enum TestError: Error { case missingValue }
}
