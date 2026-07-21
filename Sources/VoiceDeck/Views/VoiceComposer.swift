import SwiftUI
import UniformTypeIdentifiers

struct VoiceComposer: View {
    @Binding var draft: String
    @Bindable var voiceSession: VoiceSessionController
    @Bindable var store: ConversationStore

    @State private var isSelectingAttachment = false
    @State private var attachmentError: String?

    var body: some View {
        HStack(spacing: 10) {
            Button {
                isSelectingAttachment = true
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(voiceSession.pendingWindowContextName == nil ? Color.secondary : Color.accentColor)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(attachmentHelp)

            TextField("输入消息", text: $draft)
                .textFieldStyle(.plain)
                .font(.body)
                .onSubmit(sendDraft)

            if voiceSession.isSpeaking {
                Button {
                    voiceSession.stopSpeaking()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(ComposerIconButtonStyle())
                .help("停止朗读")
                .accessibilityLabel("停止朗读")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: 820, minHeight: 52, maxHeight: 52)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.72), lineWidth: 0.7)
        )
        .frame(maxWidth: .infinity)
        .fileImporter(isPresented: $isSelectingAttachment, allowedContentTypes: [.image]) { result in
            addAttachment(from: result)
        }
        .alert("无法开始问答", isPresented: showsVoiceError) {
            Button("好", role: .cancel) {
                voiceSession.dismissFailure()
            }
        } message: {
            Text(voiceErrorMessage ?? "请检查模型与 API Key 配置。")
        }
        .alert("无法添加附件", isPresented: showsAttachmentError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(attachmentError ?? "未知错误")
        }
    }

    private var attachmentHelp: String {
        if let name = voiceSession.pendingWindowContextName {
            return "已附带：\(name)"
        }
        return "添加图片附件"
    }

    private var showsAttachmentError: Binding<Bool> {
        Binding(
            get: { attachmentError != nil },
            set: { if !$0 { attachmentError = nil } }
        )
    }

    private var voiceErrorMessage: String? {
        guard case let .failed(message) = voiceSession.state else { return nil }
        return message
    }

    private var showsVoiceError: Binding<Bool> {
        Binding(
            get: { voiceErrorMessage != nil },
            set: { if !$0 { voiceSession.dismissFailure() } }
        )
    }

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        voiceSession.sendText(text, in: store)
    }

    private func addAttachment(from result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess { url.stopAccessingSecurityScopedResource() }
            }

            let data = try Data(contentsOf: url)
            let contentType = UTType(filenameExtension: url.pathExtension)
            try voiceSession.attachImage(
                data: data,
                fileName: url.lastPathComponent,
                mimeType: contentType?.preferredMIMEType ?? "image/jpeg"
            )
        } catch {
            attachmentError = error.localizedDescription
        }
    }
}

private struct ComposerIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.primary)
            .background {
                Circle()
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.13 : 0.07))
                    .scaleEffect(configuration.isPressed ? 1 : 0.72)
            }
            .overlay {
                Circle()
                    .stroke(Color.primary.opacity(configuration.isPressed ? 0.22 : 0), lineWidth: 1)
                    .scaleEffect(configuration.isPressed ? 1.35 : 0.62)
                    .opacity(configuration.isPressed ? 1 : 0)
            }
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}
