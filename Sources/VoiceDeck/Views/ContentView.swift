import SwiftUI

struct ContentView: View {
    @Bindable var store: ConversationStore
    @Bindable var voiceSession: VoiceSessionController
    @State private var isShowingSettings = false

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store) {
                isShowingSettings = true
            }
            .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 320)
        } detail: {
            ZStack {
                if isShowingSettings {
                    SettingsView {
                        isShowingSettings = false
                    }
                        .transition(.opacity.combined(with: .offset(x: 8, y: 0)))
                } else if let conversation = store.selectedConversation {
                    ConversationView(
                        conversation: conversation,
                        store: store,
                        voiceSession: voiceSession
                    )
                    .id(conversation.id)
                    .transition(.opacity.combined(with: .offset(x: 8, y: 0)))
                } else {
                    ContentUnavailableView("选择一个对话", systemImage: "bubble.left.and.bubble.right")
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.18), value: store.selectedConversationID)
            .animation(.easeOut(duration: 0.18), value: isShowingSettings)
        }
        .onChange(of: store.selectedConversationID) { _, _ in
            isShowingSettings = false
        }
    }
}
