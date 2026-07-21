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
                .onChange(of: voiceSession.liveTranscript) { _, transcript in
                    floatingIndicator.updateRecording(transcript: transcript, captureStatus: voiceSession.windowCaptureStatus)
                }
                .onChange(of: voiceSession.audioActivity) { _, activity in
                    floatingIndicator.updateAudioActivity(activity)
                }
                .onChange(of: voiceSession.windowCaptureStatus) { _, captureStatus in
                    floatingIndicator.updateRecording(transcript: voiceSession.liveTranscript, captureStatus: captureStatus)
                }
                .onAppear {
                    hotkey.start(
                        onPress: {
                            Task { @MainActor in
                                floatingIndicator.show(
                                    transcript: "",
                                    captureStatus: nil,
                                    audioActivity: voiceSession.audioActivity
                                )
                                voiceSession.beginRecording(in: store)
                            }
                        },
                        onRelease: {
                            Task { @MainActor in
                                floatingIndicator.hide()
                                voiceSession.endRecording(in: store)
                            }
                        },
                        onCapturePress: {
                            Task { @MainActor in
                                floatingIndicator.show(
                                    transcript: "",
                                    captureStatus: .capturing,
                                    audioActivity: voiceSession.audioActivity
                                )
                                voiceSession.beginRecordingWithWindowContext(in: store)
                            }
                        },
                        onCaptureRelease: {
                            Task { @MainActor in
                                floatingIndicator.hide()
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

                Button("截取当前窗口作为下一次语音上下文") {
                    voiceSession.captureFrontmostWindowContext(in: store) { success in
                        floatingIndicator.showCaptureFeedback(success: success)
                    }
                }
                .keyboardShortcut("x", modifiers: .option)
            }
        }
    }
}
