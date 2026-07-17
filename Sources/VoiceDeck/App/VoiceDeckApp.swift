import SwiftUI

@main
struct VoiceDeckApp: App {
    @State private var store = ConversationStore()
    @State private var voiceSession = VoiceSessionController()
    @State private var hotkey = GlobalHotkeyManager()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(store: store, voiceSession: voiceSession)
                .frame(minWidth: 880, minHeight: 620)
                .onAppear {
                    hotkey.start(
                        onPress: {
                            Task { @MainActor in
                                voiceSession.beginRecording(in: store)
                            }
                        },
                        onRelease: {
                            Task { @MainActor in
                                voiceSession.endRecording(in: store)
                            }
                        }
                    )
                }
        }
        .defaultSize(width: 1_080, height: 720)
        .commands {
            CommandMenu("对话") {
                Button("新建对话") {
                    store.createConversation()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("开始语音输入") {
                    voiceSession.beginRecording(in: store)
                }
            }
        }
    }
}
