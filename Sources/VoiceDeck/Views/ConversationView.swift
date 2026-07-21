import SwiftUI

struct ConversationView: View {
    let conversation: Conversation
    @Bindable var store: ConversationStore
    @Bindable var voiceSession: VoiceSessionController

    @AppStorage(ConversationProviderSettings.providerPreferenceKey)
    private var providerRawValue = ConversationProviderID.qwen.rawValue
    @State private var draft = ""
    @State private var modelRevision = 0
    @State private var isModelPickerPresented = false

    var body: some View {
        VStack(spacing: 0) {
            if conversation.messages.isEmpty {
                EmptyConversationState()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                messages
            }

            VoiceComposer(draft: $draft, voiceSession: voiceSession, store: store)
                .padding(.horizontal, 42)
                .padding(.top, 12)
                .padding(.bottom, 20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(conversation.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                modelMenu
            }
        }
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 30) {
                    ForEach(conversation.messages) { message in
                        MessageRow(message: message)
                            .id(message.id)
                    }
                }
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 42)
                .padding(.vertical, 34)
            }
            .onChange(of: conversation.messages.count) { _, _ in
                guard let id = conversation.messages.last?.id else { return }
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }

    private var modelMenu: some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) {
                isModelPickerPresented.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Text(selectedModel.title)
                    .lineLimit(1)
                    .font(.subheadline.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(isModelPickerPresented ? 180 : 0))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(minWidth: 160, minHeight: 34, alignment: .center)
        }
        .buttonStyle(ModelPickerButtonStyle(isPresented: isModelPickerPresented))
        .popover(isPresented: $isModelPickerPresented, arrowEdge: .top) {
            modelPickerPanel
        }
        .id(modelRevision)
        .help("选择对话模型")
    }

    private var modelPickerPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ConversationProviderSettings.availableProviderIDs, id: \.self) { providerID in
                VStack(alignment: .leading, spacing: 4) {
                    Text(providerID.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                    ForEach(ConversationProviderSettings.modelOptions(for: providerID)) { option in
                        Button {
                            selectModel(option, from: providerID)
                        } label: {
                            HStack(spacing: 9) {
                                Text(option.title)
                                Spacer(minLength: 20)
                                if providerID == selectedProviderID && option.id == selectedModel.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                        }
                        .buttonStyle(ModelOptionButtonStyle(isSelected: providerID == selectedProviderID && option.id == selectedModel.id))
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 246)
    }

    private func selectModel(_ option: ConversationProviderSettings.ModelOption, from providerID: ConversationProviderID) {
        ConversationProviderSettings.select(model: option.id, for: providerID)
        providerRawValue = providerID.rawValue
        voiceSession.conversationModelDidChange()
        modelRevision += 1
        withAnimation(.snappy(duration: 0.2)) {
            isModelPickerPresented = false
        }
    }

    private var selectedProviderID: ConversationProviderID {
        ConversationProviderID(rawValue: providerRawValue) ?? .qwen
    }

    private var selectedModel: ConversationProviderSettings.ModelOption {
        ConversationProviderSettings.selectedModelOption(for: selectedProviderID)
    }
}

private struct ModelPickerButtonStyle: ButtonStyle {
    let isPresented: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.12 : 0))
                    .scaleEffect(configuration.isPressed ? 1 : 0.7)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.18), value: isPresented)
    }
}

private struct ModelOptionButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(configuration.isPressed ? 0.08 : 0))
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct EmptyConversationState: View {
    var body: some View {
        VStack(spacing: 0) {
            SignalOrbView(size: 112, isActive: true, isSoft: true)
                .padding(.bottom, 34)

            Text("随时开口，继续眼前的工作")
                .font(.system(size: 28, weight: .semibold))
                .padding(.bottom, 9)

            Text("按住 ⌥Z 说话，或按住 ⌥X 截图并提问")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 42)
    }
}

private struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        if message.role == .user {
            if message.attachments.isEmpty {
                HStack {
                    Spacer(minLength: 100)
                    Text(message.content)
                        .textSelection(.enabled)
                        .lineSpacing(3)
                        .multilineTextAlignment(.trailing)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 11)
                        .background(
                            Color.primary.opacity(0.075),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                }
            } else {
                HStack {
                    Spacer(minLength: 40)
                    AttachmentMessageCard(message: message)
                        .frame(maxWidth: 720)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                SignalOrbView(size: 32, isActive: true, isSoft: true)
                    .frame(width: 38, height: 38)
                    .padding(.top, 3)
                Text(message.content)
                    .textSelection(.enabled)
                    .font(.body)
                    .lineSpacing(5)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .background(
                        Color(red: 0.949, green: 0.965, blue: 0.988),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct AttachmentMessageCard: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(message.attachments) { attachment in
                AttachmentPreviewView(attachment: attachment)
            }

            if !message.content.isEmpty {
                Text(message.content)
                    .textSelection(.enabled)
                    .font(.body.weight(.medium))
                    .lineSpacing(3)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(20)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.88),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }
}
