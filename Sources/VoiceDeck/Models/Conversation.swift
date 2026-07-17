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

    init(id: UUID = UUID(), role: Role, content: String, createdAt: Date = .now) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}
