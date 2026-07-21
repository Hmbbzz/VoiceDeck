import Foundation

enum OpenAICompatibleConversationProviderError: Error, Equatable, LocalizedError {
    case missingEndpoint
    case missingSecret(reference: String)
    case invalidAttachmentData(ChatAttachment)
    case invalidServerResponse
    case httpStatus(code: Int, message: String?)
    case remoteError(String)
    case malformedEvent(String)

    var errorDescription: String? {
        switch self {
        case .missingEndpoint:
            "A conversation provider endpoint is required."
        case let .missingSecret(reference):
            "No credential is available for \(reference)."
        case let .invalidAttachmentData(attachment):
            "Attachment \(attachment.displayName) contains no data."
        case .invalidServerResponse:
            "The conversation provider returned an invalid response."
        case let .httpStatus(code, message):
            message ?? "The conversation provider returned HTTP \(code)."
        case let .remoteError(message):
            message
        case let .malformedEvent(event):
            "The conversation provider returned an invalid stream event: \(event)"
        }
    }
}

/// A Chat Completions-compatible streaming client for providers configured at runtime.
/// Secrets and attachment bytes are deliberately supplied by the app at request time.
struct OpenAICompatibleConversationProvider: ConversationProvider {
    typealias SecretProvider = @Sendable (String) -> String?
    typealias AttachmentDataProvider = @Sendable (ChatAttachment) throws -> Data

    let configuration: ConversationModelConfiguration
    let capabilities: ConversationProviderCapabilities
    private let secretProvider: SecretProvider
    private let attachmentDataProvider: AttachmentDataProvider
    private let session: URLSession

    init(
        configuration: ConversationModelConfiguration,
        capabilities: ConversationProviderCapabilities = [.text, .images, .streaming],
        secretProvider: @escaping SecretProvider,
        attachmentDataProvider: @escaping AttachmentDataProvider,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.capabilities = capabilities
        self.secretProvider = secretProvider
        self.attachmentDataProvider = attachmentDataProvider
        self.session = session
    }

    func stream(_ request: ConversationRequest) -> AsyncThrowingStream<ConversationStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try validate(request)
                    let urlRequest = try makeURLRequest(for: request)
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    try Self.validateHTTPResponse(response)

                    for try await line in bytes.lines {
                        guard let event = try Self.parseSSELine(line) else { continue }
                        continuation.yield(event)
                        if event == .completed { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func makeURLRequest(for request: ConversationRequest) throws -> URLRequest {
        guard let endpoint = configuration.endpoint else {
            throw OpenAICompatibleConversationProviderError.missingEndpoint
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        if let reference = configuration.authentication.secretReference {
            guard let secret = secretProvider(reference)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !secret.isEmpty else {
                throw OpenAICompatibleConversationProviderError.missingSecret(reference: reference)
            }
            urlRequest.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }

        urlRequest.httpBody = try JSONEncoder().encode(
            OpenAICompatibleRequestBody(
                model: configuration.model,
                messages: try makeRequestMessages(from: request),
                stream: true
            )
        )
        return urlRequest
    }

    static func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAICompatibleConversationProviderError.invalidServerResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OpenAICompatibleConversationProviderError.httpStatus(code: httpResponse.statusCode, message: nil)
        }
    }

    /// Parses one `data:` line. Event framing is handled by URLSession.AsyncBytes.lines.
    static func parseSSELine(_ line: String) throws -> ConversationStreamEvent? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty else { return nil }
        if payload == "[DONE]" { return .completed }

        guard let data = payload.data(using: .utf8) else {
            throw OpenAICompatibleConversationProviderError.malformedEvent(payload)
        }
        let event: OpenAICompatibleStreamPayload
        do {
            event = try JSONDecoder().decode(OpenAICompatibleStreamPayload.self, from: data)
        } catch {
            throw OpenAICompatibleConversationProviderError.malformedEvent(payload)
        }

        if let message = event.error?.message, !message.isEmpty {
            throw OpenAICompatibleConversationProviderError.remoteError(message)
        }
        guard let content = event.choices?.first?.delta.content, !content.isEmpty else {
            return nil
        }
        return .textDelta(content)
    }

    private func makeRequestMessages(from request: ConversationRequest) throws -> [OpenAICompatibleRequestMessage] {
        var messages = request.messages
        if !request.attachments.isEmpty {
            if let index = messages.lastIndex(where: { $0.role == .user }) {
                let message = messages[index]
                messages[index] = ConversationMessage(
                    id: message.id,
                    role: message.role,
                    content: message.content,
                    attachments: message.attachments + request.attachments
                )
            } else {
                messages.append(ConversationMessage(role: .user, content: "", attachments: request.attachments))
            }
        }

        var encodedMessages: [OpenAICompatibleRequestMessage] = []
        if let systemPrompt = request.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !systemPrompt.isEmpty {
            encodedMessages.append(.text(role: .system, content: systemPrompt))
        }
        for message in messages {
            encodedMessages.append(try makeRequestMessage(from: message))
        }
        return encodedMessages
    }

    private func makeRequestMessage(from message: ConversationMessage) throws -> OpenAICompatibleRequestMessage {
        guard !message.attachments.isEmpty else {
            return .text(role: message.role, content: message.content)
        }

        var content: [OpenAICompatibleContentPart] = [.text(message.content)]
        for attachment in message.attachments {
            guard attachment.kind == .image else { throw ConversationProviderError.unsupportedAttachment(attachment.kind) }
            let data = try attachmentDataProvider(attachment)
            guard !data.isEmpty else { throw OpenAICompatibleConversationProviderError.invalidAttachmentData(attachment) }
            let url = "data:\(attachment.mimeType);base64,\(data.base64EncodedString())"
            content.append(.image(url: url))
        }
        return .parts(role: message.role, content: content)
    }
}

/// Establishes DNS/TLS state after a provider changes without sending a model request.
enum ConversationConnectionWarmup {
    static func warm(endpoint: URL) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 4
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request).resume()
    }
}

private struct OpenAICompatibleRequestBody: Encodable {
    let model: String
    let messages: [OpenAICompatibleRequestMessage]
    let stream: Bool
}

private struct OpenAICompatibleRequestMessage: Encodable {
    let role: ConversationMessage.Role
    let content: Content

    enum Content: Encodable {
        case text(String)
        case parts([OpenAICompatibleContentPart])

        func encode(to encoder: Encoder) throws {
            switch self {
            case let .text(text): try text.encode(to: encoder)
            case let .parts(parts): try parts.encode(to: encoder)
            }
        }
    }

    static func text(role: ConversationMessage.Role, content: String) -> Self {
        Self(role: role, content: .text(content))
    }

    static func parts(role: ConversationMessage.Role, content: [OpenAICompatibleContentPart]) -> Self {
        Self(role: role, content: .parts(content))
    }
}

private struct OpenAICompatibleContentPart: Encodable {
    let type: String
    let text: String?
    let imageURL: ImageURL?

    struct ImageURL: Encodable {
        let url: String

        enum CodingKeys: String, CodingKey { case url }
    }

    enum CodingKeys: String, CodingKey {
        case type, text
        case imageURL = "image_url"
    }

    static func text(_ text: String) -> Self {
        Self(type: "text", text: text, imageURL: nil)
    }

    static func image(url: String) -> Self {
        Self(type: "image_url", text: nil, imageURL: ImageURL(url: url))
    }
}

private struct OpenAICompatibleStreamPayload: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable { let content: String? }
        let delta: Delta
    }
    struct ProviderError: Decodable { let message: String? }

    let choices: [Choice]?
    let error: ProviderError?
}
