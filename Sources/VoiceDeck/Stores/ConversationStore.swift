import Foundation
import Observation

@MainActor
@Observable
final class ConversationStore {
    private let storageKey = "voiceDeck.conversations"

    var conversations: [Conversation]
    var selectedConversationID: Conversation.ID?

    init() {
        let restored = Self.restore(storageKey: storageKey)
        conversations = restored.isEmpty ? Self.previewConversations : restored
        selectedConversationID = conversations.first?.id
    }

    var selectedConversation: Conversation? {
        guard let selectedConversationID else { return nil }
        return conversations.first { $0.id == selectedConversationID }
    }

    func createConversation() {
        let conversation = Conversation(title: "新对话")
        conversations.insert(conversation, at: 0)
        selectedConversationID = conversation.id
        persist()
    }

    func append(_ message: ChatMessage, to conversationID: Conversation.ID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }

        conversations[index].messages.append(message)
        conversations[index].updatedAt = message.createdAt
        sortConversations()
        persist()
    }

    func addAttachment(_ attachment: ChatAttachment, to messageID: ChatMessage.ID, in conversationID: Conversation.ID) {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              let messageIndex = conversations[conversationIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }

        let message = conversations[conversationIndex].messages[messageIndex]
        guard !message.attachments.contains(where: { $0.id == attachment.id }) else { return }
        conversations[conversationIndex].messages[messageIndex] = ChatMessage(
            id: message.id,
            role: message.role,
            content: message.content,
            createdAt: message.createdAt,
            attachments: message.attachments + [attachment]
        )
        conversations[conversationIndex].updatedAt = .now
        sortConversations()
        persist()
    }

    func replaceContent(of messageID: ChatMessage.ID, in conversationID: Conversation.ID, with content: String) {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              let messageIndex = conversations[conversationIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }
        let message = conversations[conversationIndex].messages[messageIndex]
        conversations[conversationIndex].messages[messageIndex] = ChatMessage(
            id: message.id,
            role: message.role,
            content: content,
            createdAt: message.createdAt,
            attachments: message.attachments
        )
        conversations[conversationIndex].updatedAt = .now
        persist()
    }

    func rename(_ conversationID: Conversation.ID, to title: String) {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty,
              let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[index].title = String(normalizedTitle.prefix(80))
        persist()
    }

    /// Claims an untouched conversation title once its first exchange has completed.
    func renameIfUntitled(_ conversationID: Conversation.ID, to title: String) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }),
              conversations[index].title == "新对话" else { return }
        rename(conversationID, to: title)
    }

    func togglePin(_ conversationID: Conversation.ID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[index].isPinned.toggle()
        sortConversations()
        persist()
    }

    func archive(_ conversationID: Conversation.ID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[index].isArchived = true
        conversations[index].isPinned = false
        selectNextConversation(afterRemoving: conversationID)
        persist()
    }

    func unarchive(_ conversationID: Conversation.ID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[index].isArchived = false
        sortConversations()
        selectedConversationID = conversationID
        persist()
    }

    func delete(_ conversationID: Conversation.ID) {
        conversations.removeAll { $0.id == conversationID }
        selectNextConversation(afterRemoving: conversationID)
        persist()
    }

    func messages(for conversationID: Conversation.ID) -> [ChatMessage] {
        conversations.first { $0.id == conversationID }?.messages ?? []
    }

    func containsConversation(_ id: Conversation.ID) -> Bool {
        conversations.contains { $0.id == id }
    }

    private func selectNextConversation(afterRemoving id: Conversation.ID) {
        guard selectedConversationID == id else { return }
        selectedConversationID = conversations.first { !$0.isArchived && $0.id != id }?.id
    }

    private func sortConversations() {
        conversations.sort {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.updatedAt > $1.updatedAt
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func restore(storageKey: String) -> [Conversation] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([Conversation].self, from: data)) ?? []
    }

    private static let previewConversations: [Conversation] = [
        Conversation(
            title: "为周末上海行程做规划",
            updatedAt: .now,
            messages: [
                ChatMessage(role: .user, content: "周末去上海两天，想吃得好也想逛一逛。"),
                ChatMessage(role: .assistant, content: "可以把行程放在梧桐区和西岸两条线：第一天从武康路一路散步到安福路，傍晚去徐汇滨江；第二天逛外滩、北外滩，再留一顿本帮菜。要不要按你的出发位置和预算细化？")
            ]
        ),
        Conversation(
            title: "整理项目想法",
            updatedAt: .now.addingTimeInterval(-86_400),
            messages: [
                ChatMessage(role: .user, content: "帮我把这个产品想法整理成 MVP。"),
                ChatMessage(role: .assistant, content: "先验证最高频的一件事：用户能否在不中断当前工作的情况下发起一次可靠的语音问答。")
            ]
        )
    ]
}
