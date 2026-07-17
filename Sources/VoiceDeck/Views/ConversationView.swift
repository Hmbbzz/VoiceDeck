import SwiftUI

struct ConversationView: View {
    let conversation: Conversation
    @Bindable var store: ConversationStore
    @Bindable var voiceSession: VoiceSessionController

    var body: some View {
        VStack(spacing: 0) {
            conversationHeader

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 26) {
                        ForEach(conversation.messages) { message in
                            MessageRow(message: message)
                                .id(message.id)
                        }
                    }
                    .frame(maxWidth: 700, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 42)
                    .padding(.vertical, 30)
                }
                .onChange(of: conversation.messages.count) { _, _ in
                    guard let id = conversation.messages.last?.id else { return }
                    withAnimation(.easeOut(duration: 0.22)) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }

            Divider()
            VoiceComposer(voiceSession: voiceSession, store: store)
            .padding(.horizontal, 32)
            .padding(.vertical, 18)
        }
        .background(.background)
    }

    private var conversationHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.title)
                    .font(.title2.weight(.semibold))
                Text("语音对话会在 2 分钟内自动延续上下文")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "waveform")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 22)
    }
}

private struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        Group {
            if message.role == .user {
                HStack {
                    Spacer(minLength: 80)
                    Text(message.content)
                        .textSelection(.enabled)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 11)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Voice Deck", systemImage: "waveform")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(message.content)
                        .textSelection(.enabled)
                        .font(.body)
                        .lineSpacing(4)
                }
            }
        }
    }
}
