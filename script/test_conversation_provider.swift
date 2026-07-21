import Foundation

@main
struct ConversationProviderTests {
    static func main() async {
        do {
            try testDefaultsAndValidation()
            try testRegistryAndCapabilities()
            try await testMockStream()
            print("Conversation provider tests passed.")
        } catch {
            fputs("Conversation provider tests failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func testDefaultsAndValidation() throws {
        for providerID in ConversationProviderID.allCases {
            let configuration = ConversationModelConfiguration.default(for: providerID)
            try configuration.validate()
            precondition(configuration.providerID == providerID)
            precondition(!configuration.model.isEmpty)
        }

        do {
            _ = try ConversationModelConfiguration(providerID: .openAI, model: "   ")
            preconditionFailure("An empty model should be rejected")
        } catch ConversationProviderError.invalidModel {
            // Expected.
        }

        do {
            _ = try ConversationModelConfiguration(
                providerID: .openAI,
                model: "test",
                endpoint: URL(string: "http://localhost:8080")
            )
            preconditionFailure("Non-HTTPS endpoints should be rejected")
        } catch ConversationProviderError.invalidEndpoint {
            // Expected.
        }
    }

    private static func testRegistryAndCapabilities() throws {
        let configuration = ConversationModelConfiguration.default(for: .openAI)
        var registry = ConversationProviderRegistry()
        registry.register(.openAI) { configuration in
            MockConversationProvider(configuration: configuration)
        }
        let provider = try registry.provider(for: configuration)
        precondition(provider.capabilities.contains(.text))
        precondition(provider.capabilities.contains(.images))

        let image = ChatAttachment(
            fileName: "window.jpg",
            mimeType: "image/jpeg",
            byteCount: 1_024,
            displayName: "Current window"
        )
        let textOnlyProvider = MockConversationProvider(
            configuration: configuration,
            capabilities: [.text, .streaming]
        )
        do {
            try textOnlyProvider.validate(ConversationRequest(messages: [], attachments: [image]))
            preconditionFailure("Image validation should respect provider capabilities")
        } catch ConversationProviderError.unsupportedAttachment(.image) {
            // Expected.
        }

        do {
            _ = try registry.provider(for: ConversationModelConfiguration.default(for: .glm))
            preconditionFailure("Unregistered providers should fail clearly")
        } catch ConversationProviderError.providerNotRegistered(.glm) {
            // Expected.
        }
    }

    private static func testMockStream() async throws {
        let configuration = ConversationModelConfiguration.default(for: .qwen)
        let provider = MockConversationProvider(
            configuration: configuration,
            events: [.textDelta("Hello"), .textDelta(" world"), .usage(inputTokens: 3, outputTokens: 2), .completed]
        )
        var received: [ConversationStreamEvent] = []
        for try await event in provider.stream(ConversationRequest(messages: [])) {
            received.append(event)
        }
        precondition(received == provider.events)
    }
}
