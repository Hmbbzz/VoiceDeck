import SwiftUI

struct VoiceComposer: View {
    @Bindable var voiceSession: VoiceSessionController
    @Bindable var store: ConversationStore

    var body: some View {
        VStack(spacing: 10) {
            Button {
                switch voiceSession.state {
                case .idle:
                    voiceSession.beginRecording(in: store)
                case .recording:
                    voiceSession.endRecording(in: store)
                case .thinking:
                    voiceSession.cancel()
                case .failed:
                    voiceSession.cancel()
                    voiceSession.beginRecording(in: store)
                }
            } label: {
                HStack(spacing: 10) {
                    if voiceSession.state == .thinking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: symbol)
                            .font(.body.weight(.semibold))
                            .transition(.opacity.combined(with: .scale))
                    }
                    Text(title)
                        .font(.body.weight(.medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
            }
            .buttonStyle(
                VoiceButtonStyle(
                    isRecording: voiceSession.state == .recording,
                    isThinking: voiceSession.state == .thinking
                )
            )
            .animation(.snappy(duration: 0.22), value: voiceSession.state)

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(title)
    }

    private var title: String {
        switch voiceSession.state {
        case .idle: "按住说话"
        case .recording: "松开即可发送"
        case .thinking: "正在整理回答"
        case let .failed(message): message
        }
    }

    private var caption: String {
        switch voiceSession.state {
        case .idle: "全局快捷键 Option + Z"
        case .recording: "正在聆听"
        case .thinking: "再次点击可以取消"
        case .failed: "点击后可以重新尝试"
        }
    }

    private var symbol: String {
        switch voiceSession.state {
        case .idle: "mic.fill"
        case .recording: "stop.fill"
        case .thinking: "ellipsis"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
}

private struct VoiceButtonStyle: ButtonStyle {
    let isRecording: Bool
    let isThinking: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isRecording ? Color.white : Color.primary)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isRecording ? Color.red : Color.primary.opacity(configuration.isPressed ? 0.14 : 0.09))
            }
            .shadow(
                color: isRecording ? .red.opacity(0.28) : .black.opacity(configuration.isPressed ? 0.04 : 0.1),
                radius: isRecording ? 12 : 5,
                y: isRecording ? 5 : 2
            )
            .scaleEffect(configuration.isPressed ? 0.985 : (isRecording ? 1.008 : 1))
            .opacity(isThinking ? 0.78 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
            .animation(.snappy(duration: 0.22), value: isRecording)
            .animation(.easeInOut(duration: 0.2), value: isThinking)
    }
}
