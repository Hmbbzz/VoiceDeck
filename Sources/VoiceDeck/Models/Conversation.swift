import Foundation

struct Conversation: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var updatedAt: Date
    var messages: [ChatMessage]
    var isPinned: Bool
    var isArchived: Bool

    init(
        id: UUID = UUID(),
        title: String,
        updatedAt: Date = .now,
        messages: [ChatMessage] = [],
        isPinned: Bool = false,
        isArchived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
        self.messages = messages
        self.isPinned = isPinned
        self.isArchived = isArchived
    }

    var preview: String {
        messages.last?.content ?? "还没有消息"
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, updatedAt, messages, isPinned, isArchived
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        messages = try container.decode([ChatMessage].self, forKey: .messages)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }
}

struct ChatMessage: Identifiable, Codable, Hashable {
    enum Role: String, Codable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    let content: String
    let createdAt: Date
    let attachments: [ChatAttachment]

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        createdAt: Date = .now,
        attachments: [ChatAttachment] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.attachments = attachments
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, content, createdAt, attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(Role.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        attachments = try container.decodeIfPresent([ChatAttachment].self, forKey: .attachments) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(attachments, forKey: .attachments)
    }
}

struct ChatAttachment: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, Hashable {
        case image
    }

    struct ScreenshotSource: Codable, Hashable {
        let applicationName: String?
        let windowTitle: String?

        init(applicationName: String? = nil, windowTitle: String? = nil) {
            self.applicationName = applicationName
            self.windowTitle = windowTitle
        }
    }

    let id: UUID
    let kind: Kind
    let fileName: String
    let mimeType: String
    let byteCount: Int
    let displayName: String
    let screenshotSource: ScreenshotSource?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        kind: Kind = .image,
        fileName: String,
        mimeType: String,
        byteCount: Int,
        displayName: String,
        screenshotSource: ScreenshotSource? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.fileName = fileName
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.displayName = displayName
        self.screenshotSource = screenshotSource
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, fileName, mimeType, byteCount, displayName, screenshotSource, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(Kind.self, forKey: .kind)
        fileName = try container.decode(String.self, forKey: .fileName)
        mimeType = try container.decode(String.self, forKey: .mimeType)
        byteCount = try container.decode(Int.self, forKey: .byteCount)
        displayName = try container.decode(String.self, forKey: .displayName)
        screenshotSource = try container.decodeIfPresent(ScreenshotSource.self, forKey: .screenshotSource)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
    }
}
