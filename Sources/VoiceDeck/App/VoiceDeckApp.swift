import AppKit
import SwiftUI

@main
struct VoiceDeckApp: App {
    @State private var store = ConversationStore()
    @State private var voiceSession = VoiceSessionController()
    @State private var hotkey = GlobalHotkeyManager()
    @State private var floatingIndicator = FloatingVoiceIndicatorController()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(store: store, voiceSession: voiceSession)
                .frame(minWidth: 880, minHeight: 620)
                .onAppear {
                    hotkey.start(
                        onPress: {
                            Task { @MainActor in
                                if !NSApp.isActive {
                                    floatingIndicator.show()
                                }
                                voiceSession.beginRecording(in: store)
                            }
                        },
                        onRelease: {
                            Task { @MainActor in
                                floatingIndicator.hide()
                                voiceSession.endRecording(in: store)
                            }
                        },
                        onCaptureWindowContext: {
                            Task { @MainActor in
                                voiceSession.captureFrontmostWindowContext(in: store) { success in
                                    floatingIndicator.showCaptureFeedback(success: success)
                                }
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

                Button("截取当前窗口作为上下文") {
                    voiceSession.captureFrontmostWindowContext(in: store) { success in
                        floatingIndicator.showCaptureFeedback(success: success)
                    }
                }
                .keyboardShortcut("x", modifiers: .option)
            }
        }
    }
}
