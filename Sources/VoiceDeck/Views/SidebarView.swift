import SwiftUI

struct SidebarView: View {
    @Bindable var store: ConversationStore
    let onShowSettings: () -> Void

    @State private var conversationToRename: Conversation?
    @State private var searchText = ""

    private var visibleConversations: [Conversation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.conversations }
        return store.conversations.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.preview.localizedCaseInsensitiveContains(query)
        }
    }

    private var recent: [Conversation] {
        visibleConversations.filter { !$0.isArchived && !$0.isPinned && Calendar.current.isDateInToday($0.updatedAt) }
    }

    private var earlier: [Conversation] {
        visibleConversations.filter { !$0.isArchived && !$0.isPinned && !Calendar.current.isDateInToday($0.updatedAt) }
    }

    private var pinned: [Conversation] {
        visibleConversations.filter { !$0.isArchived && $0.isPinned }
    }

    private var archived: [Conversation] {
        visibleConversations.filter(\.isArchived)
    }

    var body: some View {
        VStack(spacing: 0) {
            brand
            newConversationButton
            searchField
            conversationList
            footer
        }
        .sheet(item: $conversationToRename) { conversation in
            RenameConversationSheet(conversation: conversation) { title in
                store.rename(conversation.id, to: title)
            }
        }
    }

    private var brand: some View {
        HStack(spacing: 12) {
            SignalOrbView(size: 32, isSoft: true)
            Text("VoiceDeck")
                .font(.system(size: 17, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 24)
    }

    private var newConversationButton: some View {
        Button {
            store.createConversation()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 20)
                Text("新对话")
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.75), lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索对话", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 13)
        .frame(height: 42)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.top, 12)
    }

    private var conversationList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                conversationSection("已置顶", conversations: pinned)
                conversationSection("最近", conversations: recent)
                conversationSection("较早", conversations: earlier)
                conversationSection("已归档", conversations: archived)
            }
            .padding(.horizontal, 12)
            .padding(.top, 30)
            .padding(.bottom, 18)
        }
    }

    @ViewBuilder
    private func conversationSection(_ title: String, conversations: [Conversation]) -> some View {
        if !conversations.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)

                VStack(spacing: 3) {
                    ForEach(conversations) { conversation in
                        ConversationRow(
                            conversation: conversation,
                            isSelected: store.selectedConversationID == conversation.id,
                            store: store,
                            onSelect: { store.selectedConversationID = conversation.id },
                            onRename: { conversationToRename = conversation }
                        )
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: onShowSettings) {
                Image(systemName: "gearshape")
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("设置")

            Button {
                store.createConversation()
            } label: {
                Image(systemName: "square.and.pencil")
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("新对话")

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }
}

private struct ConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool
    @Bindable var store: ConversationStore
    let onSelect: () -> Void
    let onRename: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Text(conversation.title)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if conversation.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 36)
            .contentShape(Rectangle())
            .background(
                isSelected ? Color.primary.opacity(0.075) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
        }
        .buttonStyle(.plain)
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
                Button("取消", role: .cancel) { dismiss() }
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
