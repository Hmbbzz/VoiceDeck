import SwiftUI

struct SettingsView: View {
    let onBack: () -> Void
    @AppStorage("voiceDeck.continuationWindow") private var continuationWindow = 120.0
    @AppStorage("voiceDeck.playResponses") private var playResponses = true
    @AppStorage(BailianTTSConfiguration.voicePreferenceKey) private var ttsVoice = BailianTTSConfiguration.defaultVoice
    @AppStorage("voiceDeck.dashScopeWorkspaceID") private var workspaceID = ""
    @AppStorage(AudioInputDevice.preferenceKey) private var inputDeviceUID = ""
    @AppStorage(ConversationProviderSettings.providerPreferenceKey) private var providerRawValue = ConversationProviderID.qwen.rawValue
    @State private var dashScopeAPIKey = ""
    @State private var providerModel = ""
    @State private var providerAPIKey = ""
    @State private var saveMessage: String?
    @State private var providerSaveMessage: String?
    @State private var screenCaptureMessage: String?
    @State private var inputDevices = AudioInputDevice.availableDevices()
    @State private var inputRefreshRotation = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(RippleIconButtonStyle())
                .help("返回对话")

                Text("设置")
                    .font(.title2.weight(.semibold))
                Spacer()
            }
            .padding(.bottom, 20)

            Form {
            Section("语音与上下文") {
                Picker("输入设备", selection: $inputDeviceUID) {
                    Text("系统默认（\(AudioInputDevice.defaultDeviceName() ?? "未检测到"))")
                        .tag("")
                    ForEach(inputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                .pickerStyle(.menu)
                HStack(spacing: 8) {
                    Text("选择后将在下一次录音时生效。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        inputDevices = AudioInputDevice.availableDevices()
                        withAnimation(.snappy(duration: 0.32, extraBounce: 0.08)) {
                            inputRefreshRotation += 360
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(inputRefreshRotation))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(RippleIconButtonStyle())
                    .help("刷新输入设备")
                }
                Toggle("回答后自动朗读", isOn: $playResponses)
                Text("所有模型回复都使用阿里百炼语音合成，并复用下方的 DashScope API Key。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("朗读音色", selection: $ttsVoice) {
                    ForEach(BailianTTSConfiguration.voices) { voice in
                        Text("\(voice.name) - \(voice.description)")
                            .tag(voice.id)
                    }
                }
                .pickerStyle(.menu)
                Picker("延续上下文", selection: $continuationWindow) {
                    Text("1 分钟").tag(60.0)
                    Text("2 分钟").tag(120.0)
                    Text("3 分钟").tag(180.0)
                    Text("5 分钟").tag(300.0)
                }
                .pickerStyle(.menu)
            }

            Section("快捷操作") {
                LabeledContent("开始语音输入") {
                    Text("Option + Z")
                        .monospaced()
                        .foregroundStyle(.secondary)
                }
                Text("按住快捷键说话，松开后发送。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("截取窗口上下文") {
                    Text("Option + X")
                        .monospaced()
                        .foregroundStyle(.secondary)
                }
                Text("按住 Option + X 会并行截取前台窗口并录音；松开后作为同一条消息发送。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("对话模型") {
                Picker("模型提供商", selection: $providerRawValue) {
                    ForEach(ConversationProviderSettings.availableProviderIDs, id: \.rawValue) { providerID in
                        Text(providerID.displayName).tag(providerID.rawValue)
                    }
                }
                .pickerStyle(.menu)

                Picker("模型", selection: $providerModel) {
                    ForEach(ConversationProviderSettings.modelOptions(for: selectedProviderID)) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: providerModel) { _, model in
                    ConversationProviderSettings.save(model: model, for: selectedProviderID)
                }
                if selectedProviderID == .qwen {
                    Label("使用下方阿里百炼 DashScope API Key 与业务空间", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label(
                        ConversationProviderSettings.hasSavedCredential(for: selectedProviderID)
                            ? "已配置 \(selectedProviderID.displayName) API Key"
                            : "尚未配置 \(selectedProviderID.displayName) API Key",
                        systemImage: ConversationProviderSettings.hasSavedCredential(for: selectedProviderID)
                            ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ConversationProviderSettings.hasSavedCredential(for: selectedProviderID) ? .green : .orange
                    )
                    SecureField("\(selectedProviderID.displayName) API Key", text: $providerAPIKey)
                        .textFieldStyle(.roundedBorder)
                    Text("该模型支持窗口截图。API 端点由应用按提供商固定；API Key 仅在点击保存时写入钥匙串。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("保存模型配置", systemImage: "key.fill") {
                            saveProviderConfiguration()
                        }
                        .buttonStyle(SettingsActionButtonStyle())
                        .disabled(providerModel.isEmpty || providerAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if let providerSaveMessage {
                            Text(providerSaveMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("屏幕录制权限") {
                Button("请求屏幕录制权限", systemImage: "rectangle.inset.filled.badge.record") {
                    screenCaptureMessage = WindowCaptureService.requestScreenCaptureAccess()
                }
                .buttonStyle(SettingsActionButtonStyle())
                if let screenCaptureMessage {
                    Text(screenCaptureMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("阿里百炼") {
                TextField("业务空间 ID", text: $workspaceID, prompt: Text("Workspace ID"))
                    .textFieldStyle(.roundedBorder)
                SecureField("DashScope API Key", text: $dashScopeAPIKey, prompt: Text("sk-..."))
                    .textFieldStyle(.roundedBorder)
                Text("已保存的密钥不会显示在这里。只有保存新密钥或首次开始语音时，系统才会请求钥匙串授权。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("保存到钥匙串", systemImage: "key.fill") {
                        do {
                            try KeychainStore.save(dashScopeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines), for: .dashScopeAPIKey)
                            ConversationProviderSettings.markCredentialSaved(for: .qwen)
                            saveMessage = "已保存"
                        } catch {
                            saveMessage = error.localizedDescription
                        }
                    }
                    .buttonStyle(SettingsActionButtonStyle())
                    .controlSize(.regular)
                    .disabled(dashScopeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let saveMessage {
                        Text(saveMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            }
            .formStyle(.grouped)
            .animation(.snappy(duration: 0.24), value: providerRawValue)
        }
        .padding(32)
        .frame(maxWidth: 680, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if !ConversationProviderSettings.availableProviderIDs.contains(ConversationProviderID(rawValue: providerRawValue) ?? .qwen) {
                providerRawValue = ConversationProviderID.qwen.rawValue
            }
            loadProviderConfiguration()
        }
        .onChange(of: providerRawValue) { _, _ in
            providerAPIKey = ""
            providerSaveMessage = nil
            loadProviderConfiguration()
        }
    }

    private var selectedProviderID: ConversationProviderID {
        let providerID = ConversationProviderID(rawValue: providerRawValue) ?? .qwen
        return ConversationProviderSettings.availableProviderIDs.contains(providerID) ? providerID : .qwen
    }

    private func loadProviderConfiguration() {
        providerModel = ConversationProviderSettings.savedModel(for: selectedProviderID)
    }

    private func saveProviderConfiguration() {
        let model = providerModel.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            ConversationProviderSettings.save(model: model, for: selectedProviderID)
            try KeychainStore.save(
                providerAPIKey.trimmingCharacters(in: .whitespacesAndNewlines),
                forReference: ConversationProviderSettings.keychainReference(for: selectedProviderID)
            )
            ConversationProviderSettings.markCredentialSaved(for: selectedProviderID)
            providerAPIKey = ""
            providerSaveMessage = "已保存"
        } catch {
            providerSaveMessage = error.localizedDescription
        }
    }

}

private struct RippleIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Circle()
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.16 : 0))
                    .scaleEffect(configuration.isPressed ? 1 : 0.65)
            }
            .clipShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

private struct SettingsActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.065))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.accentColor.opacity(configuration.isPressed ? 0.12 : 0))
                            .scaleEffect(configuration.isPressed ? 1 : 0.72)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
