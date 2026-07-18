# Voicedeck

> 中文 | English

Voicedeck 是一款 macOS 按住说话桌面助手：按住 `Option + Z` 说话，松开后发送；按下 `Option + X` 可将当前最上方窗口截图加入下一轮对话上下文。

Voicedeck is a macOS push-to-talk desktop assistant. Hold `Option + Z` to speak, release to send, and press `Option + X` to add a screenshot of the frontmost window to the next voice request.

## 功能 / Features

- 全局按住说话快捷键：`Option + Z`
  Global push-to-talk shortcut: `Option + Z`
- 窗口截图上下文快捷键：`Option + X`，需要 macOS 屏幕录制权限
  Frontmost-window screenshot context: `Option + X`, requires macOS Screen Recording permission
- 可选择输入麦克风；录音和截图都有不抢焦点的小浮窗反馈
  Choose an input microphone, with unobtrusive floating feedback for recording and screenshots
- 通义 Qwen Omni Realtime 统一处理语音输入、回答生成与语音播放
  Qwen Omni Realtime handles voice input, response generation, and voice playback.
- 对话历史支持置顶、归档、删除与重命名
  Conversation history supports pinning, archiving, deletion, and renaming.
- 可选择回复音色和上下文延续时间
  Configure the reply voice and continuation window.
- 原生 macOS SwiftUI 界面
  Native macOS SwiftUI interface.

## 环境要求 / Requirements

- macOS 14 或更高版本 / macOS 14 or later
- 带 Swift 5.10 或更高版本的 Xcode Command Line Tools / Xcode Command Line Tools with Swift 5.10 or later
- 阿里云百炼（DashScope）API Key 与北京地域业务空间 ID / Alibaba Cloud Model Studio (DashScope) API Key and a Beijing workspace ID

## 本地运行 / Run Locally

```bash
./script/build_and_run.sh
```

从工具栏齿轮进入设置，填写自己的 DashScope API Key 与业务空间 ID。首次使用截图功能时，从设置中的“屏幕录制权限”部分请求并允许 Voicedeck 录制屏幕；授权后请完全退出并重新打开应用。API Key 仅保存在本机 macOS 钥匙串中，绝不会被写入此仓库。

Open Settings from the toolbar and enter your own DashScope API Key and workspace ID. For screenshots, request and grant Screen Recording access in Settings, then fully quit and reopen the app. The API Key is stored only in your local macOS Keychain and is never committed to this repository.

## 构建验证 / Build Verification

```bash
swift build
swiftc Sources/VoiceDeck/Services/QwenRealtimeConfiguration.swift \
  script/test_realtime_configuration.swift \
  -o /tmp/voicedeck-realtime-tests
/tmp/voicedeck-realtime-tests
```

生成并启动 `dist/Voicedeck.app`：

Create and launch a runnable app bundle:

```bash
./script/build_and_run.sh --verify
```

## 仓库说明 / Repository Notes

`.gitignore` 会排除构建产物、打包应用、ZIP 文件与本机 macOS 元数据。请不要提交 API Key、业务空间凭据或钥匙串数据。

`.gitignore` excludes build artifacts, packaged apps, ZIP files, and local macOS metadata. Do not commit API keys, workspace credentials, or Keychain data.
