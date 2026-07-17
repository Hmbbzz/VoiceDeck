import SwiftUI

struct SidebarView: View {
    @Bindable var store: ConversationStore
    @State private var conversationToRename: Conversation?

    private var today: [Conversation] {
        store.conversations.filter { !$0.isArchived && !$0.isPinned && Calendar.current.isDateInToday($0.updatedAt) }
    }

    private var earlier: [Conversation] {
        store.conversations.filter { !$0.isArchived && !$0.isPinned && !Calendar.current.isDateInToday($0.updatedAt) }
    }

    private var pinned: [Conversation] {
        store.conversations.filter { !$0.isArchived && $0.isPinned }
    }

    private var archived: [Conversation] {
        store.conversations.filter(\.isArchived)
    }

    var body: some View {
        List(selection: $store.selectedConversationID) {
            if !pinned.isEmpty {
                Section("已置顶") {
                    conversationRows(pinned)
                }
            }

            if !today.isEmpty {
                Section("今天") {
                    conversationRows(today)
                }
            }

            if !earlier.isEmpty {
                Section("较早") {
                    conversationRows(earlier)
                }
            }

            if !archived.isEmpty {
                Section("已归档") {
                    conversationRows(archived)
                }
            }

        }
        .listStyle(.sidebar)
        .navigationTitle("Voice Deck")
        .sheet(item: $conversationToRename) { conversation in
            RenameConversationSheet(conversation: conversation) { title in
                store.rename(conversation.id, to: title)
            }
        }
    }

    @ViewBuilder
    private func conversationRows(_ conversations: [Conversation]) -> some View {
        ForEach(conversations) { conversation in
            ConversationRow(conversation: conversation, store: store) {
                conversationToRename = conversation
            }
            .tag(conversation.id)
        }
    }
}

private struct ConversationRow: View {
    let conversation: Conversation
    @Bindable var store: ConversationStore
    let onRename: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.title)
                    .lineLimit(1)
                Text(conversation.preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if conversation.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                store.delete(conversation.id)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(action: onRename) {
                Label("重命名", systemImage: "pencil")
            }
            if conversation.isArchived {
                Button {
                    store.unarchive(conversation.id)
                } label: {
                    Label("取消归档", systemImage: "tray.and.arrow.up")
                }
            } else {
                Button {
                    store.togglePin(conversation.id)
                } label: {
                    Label(conversation.isPinned ? "取消置顶" : "置顶", systemImage: conversation.isPinned ? "pin.slash" : "pin")
                }
                Button {
                    store.archive(conversation.id)
                } label: {
                    Label("归档", systemImage: "archivebox")
                }
            }
            Divider()
            Button(role: .destructive) {
                store.delete(conversation.id)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}

private struct RenameConversationSheet: View {
    let conversation: Conversation
    let onRename: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @FocusState private var isFocused: Bool

    init(conversation: Conversation, onRename: @escaping (String) -> Void) {
        self.conversation = conversation
        self.onRename = onRename
        _title = State(initialValue: conversation.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("重命名对话")
                .font(.headline)

            TextField("对话名称", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit(save)

            HStack {
                Spacer()
                Button("取消", role: .cancel) {
                    dismiss()
                }
                Button("完成", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
        .onAppear { isFocused = true }
    }

    private func save() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onRename(title)
        dismiss()
    }
}
