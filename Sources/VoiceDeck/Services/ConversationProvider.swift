import Foundation

/// Identifies a conversational model family without binding the app to its transport.
enum ConversationProviderID: String, CaseIterable, Codable, Hashable, Sendable {
    case qwen
    case openAI
    case kimi
    case glm
    case miniMax
}

extension ConversationProviderID {
    var displayName: String {
        switch self {
        case .qwen: "通义千问"
        case .openAI: "OpenAI"
        case .kimi: "Kimi"
        case .glm: "GLM"
        case .miniMax: "MiniMax"
        }
    }
}

struct ConversationProviderCapabilities: OptionSet, Codable, Hashable, Sendable {
    let rawValue: Int

    static let text = ConversationProviderCapabilities(rawValue: 1 << 0)
    static let images = ConversationProviderCapabilities(rawValue: 1 << 1)
    static let streaming = ConversationProviderCapabilities(rawValue: 1 << 2)

    init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

enum ConversationAuthentication: Codable, Hashable, Sendable {
    /// The actual secret remains in Keychain. This value is only its lookup reference.
    case apiKey(reference: String)
    case bearerToken(reference: String)
    case none

    var secretReference: String? {
        switch self {
        case let .apiKey(reference), let .bearerToken(reference):
            return reference
        case .none:
            return nil
        }
    }
}

struct ConversationModelConfiguration: Codable, Hashable, Sendable {
    let providerID: ConversationProviderID
    let model: String
    let endpoint: URL?
    let authentication: ConversationAuthentication

    init(
        providerID: ConversationProviderID,
        model: String,
        endpoint: URL? = nil,
        authentication: ConversationAuthentication = .none
    ) throws {
        self.providerID = providerID
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.endpoint = endpoint
        self.authentication = authentication
        try validate()
    }

    func validate() throws {
        guard !model.isEmpty else {
            throw ConversationProviderError.invalidModel
        }

        if let endpoint, endpoint.scheme != "https" {
            throw ConversationProviderError.invalidEndpoint
        }

        if let reference = authentication.secretReference,
           reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ConversationProviderError.invalidCredentialReference
        }
    }

    static func `default`(for providerID: ConversationProviderID) -> ConversationModelConfiguration {
        let descriptor: (model: String, capabilities: ConversationProviderCapabilities) = switch providerID {
        case .qwen:
            ("qwen-plus", [.text, .images, .streaming])
        case .openAI:
            ("gpt-4.1-mini", [.text, .images, .streaming])
        case .kimi:
            ("moonshot-v1-8k", [.text, .streaming])
        case .glm:
            ("glm-4-flash", [.text, .images, .streaming])
        case .miniMax:
            ("MiniMax-Text-01", [.text, .streaming])
        }

        // Defaults are local placeholders. A settings screen supplies the endpoint and Keychain reference.
        return try! ConversationModelConfiguration(
            providerID: providerID,
            model: descriptor.model,
            authentication: .apiKey(reference: "conversation.\(providerID.rawValue).api-key")
        )
    }
}

struct ConversationMessage: Codable, Hashable, Identifiable, Sendable {
    enum Role: String, Codable, Hashable, Sendable {
        case system
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    let content: String
    let attachments: [ChatAttachment]

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        attachments: [ChatAttachment] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.attachments = attachments
    }
}

extension ConversationMessage {
    init(chatMessage: ChatMessage) {
        self.init(
            id: chatMessage.id,
            role: chatMessage.role == .user ? .user : .assistant,
            content: chatMessage.content,
            attachments: chatMessage.attachments
        )
    }
}

struct ConversationRequest: Codable, Hashable, Sendable {
    let systemPrompt: String?
    let messages: [ConversationMessage]
    /// Attachments supplied for the current request but not yet persisted into history.
    let attachments: [ChatAttachment]

    init(
        systemPrompt: String? = nil,
        messages: [ConversationMessage],
        attachments: [ChatAttachment] = []
    ) {
        self.systemPrompt = systemPrompt
        self.messages = messages
        self.attachments = attachments
    }

    var allAttachments: [ChatAttachment] {
        messages.flatMap(\.attachments) + attachments
    }
}

enum ConversationStreamEvent: Hashable, Sendable {
    case textDelta(String)
    case completed
    case usage(inputTokens: Int, outputTokens: Int)
}

enum ConversationProviderError: Error, Equatable, LocalizedError {
    case invalidModel
    case invalidEndpoint
    case invalidCredentialReference
    case unsupportedAttachment(ChatAttachment.Kind)
    case unsupportedStreaming
    case providerNotRegistered(ConversationProviderID)

    var errorDescription: String? {
        switch self {
        case .invalidModel:
            "A conversation model must be selected."
        case .invalidEndpoint:
            "Conversation provider endpoints must use HTTPS."
        case .invalidCredentialReference:
            "Credential references cannot be empty."
        case let .unsupportedAttachment(kind):
            "This provider does not support \(kind.rawValue) attachments."
        case .unsupportedStreaming:
            "This provider does not support streamed responses."
        case let .providerNotRegistered(providerID):
            "No conversation provider is registered for \(providerID.rawValue)."
        }
    }
}

protocol ConversationProvider {
    var configuration: ConversationModelConfiguration { get }
    var capabilities: ConversationProviderCapabilities { get }

    func validate(_ request: ConversationRequest) throws
    func stream(_ request: ConversationRequest) -> AsyncThrowingStream<ConversationStreamEvent, Error>
}

extension ConversationProvider {
    func validate(_ request: ConversationRequest) throws {
        try configuration.validate()
        if !request.allAttachments.isEmpty, !capabilities.contains(.images) {
            let kind = request.allAttachments.first?.kind ?? .image
            throw ConversationProviderError.unsupportedAttachment(kind)
        }
        guard capabilities.contains(.streaming) else {
            throw ConversationProviderError.unsupportedStreaming
        }
    }
}

/// A factory registry makes it possible to choose a provider at runtime without coupling UI to its client.
struct ConversationProviderRegistry {
    typealias Factory = (ConversationModelConfiguration) throws -> any ConversationProvider

    private var factories: [ConversationProviderID: Factory] = [:]

    mutating func register(_ providerID: ConversationProviderID, factory: @escaping Factory) {
        factories[providerID] = factory
    }

    func provider(for configuration: ConversationModelConfiguration) throws -> any ConversationProvider {
        guard let factory = factories[configuration.providerID] else {
            throw ConversationProviderError.providerNotRegistered(configuration.providerID)
        }
        return try factory(configuration)
    }
}

/// A deterministic provider used by tests, previews, and future UI integration tests.
struct MockConversationProvider: ConversationProvider {
    let configuration: ConversationModelConfiguration
    let capabilities: ConversationProviderCapabilities
    let events: [ConversationStreamEvent]

    init(
        configuration: ConversationModelConfiguration,
        capabilities: ConversationProviderCapabilities = [.text, .images, .streaming],
        events: [ConversationStreamEvent] = [.completed]
    ) {
        self.configuration = configuration
        self.capabilities = capabilities
        self.events = events
    }

    func stream(_ request: ConversationRequest) -> AsyncThrowingStream<ConversationStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            do {
                try validate(request)
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}
