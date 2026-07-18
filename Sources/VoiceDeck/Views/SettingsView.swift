import SwiftUI

struct SettingsView: View {
    let onBack: () -> Void
    @AppStorage("voiceDeck.continuationWindow") private var continuationWindow = 120.0
    @AppStorage("voiceDeck.playResponses") private var playResponses = true
    @AppStorage("voiceDeck.dashScopeWorkspaceID") private var workspaceID = ""
    @AppStorage(QwenRealtimeConfiguration.voicePreferenceKey) private var voice = QwenRealtimeConfiguration.defaultVoice
    @AppStorage(AudioInputDevice.preferenceKey) private var inputDeviceUID = ""
    @State private var dashScopeAPIKey = ""
    @State private var saveMessage: String?
    @State private var screenCaptureMessage: String?
    @State private var inputDevices = AudioInputDevice.availableDevices()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
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
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("刷新输入设备")
                }
                Toggle("回答后自动朗读", isOn: $playResponses)
                Picker("回复音色", selection: $voice) {
                    ForEach(QwenRealtimeConfiguration.voices) { option in
                        Text("\(option.name) - \(option.description)")
                            .tag(option.id)
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
            }

            Section("屏幕录制权限") {
                Button("请求屏幕录制权限", systemImage: "rectangle.inset.filled.badge.record") {
                    screenCaptureMessage = WindowCaptureService.requestScreenCaptureAccess()
                }
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
                            saveMessage = "已保存"
                        } catch {
                            saveMessage = error.localizedDescription
                        }
                    }
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
        }
        .padding(32)
        .frame(maxWidth: 680, maxHeight: .infinity, alignment: .topLeading)
    }
}
