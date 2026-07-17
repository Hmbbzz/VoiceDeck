# Voice Deck

> 中文 | English

Voice Deck 是一款 macOS 按住说话桌面助手：按住 `Option + Z` 说话，松开后发送，并可在设定时间内延续同一段语音对话。

Voice Deck is a macOS push-to-talk desktop assistant. Hold `Option + Z` to speak, release to send, and continue the same voice conversation within the configured time window.

## 功能 / Features

- 全局按住说话快捷键：`Option + Z`  
  Global push-to-talk shortcut: `Option + Z`
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

从工具栏齿轮进入设置，填写自己的 DashScope API Key 与业务空间 ID。API Key 仅保存在本机 macOS 钥匙串中，绝不会被写入此仓库。

Open Settings from the toolbar and enter your own DashScope API Key and workspace ID. The API Key is stored only in your local macOS Keychain and is never committed to this repository.

## 构建验证 / Build Verification

```bash
swift build
swiftc Sources/VoiceDeck/Services/QwenRealtimeConfiguration.swift \
  script/test_realtime_configuration.swift \
  -o /tmp/voicedeck-realtime-tests
/tmp/voicedeck-realtime-tests
```

生成并启动可运行的 App 包：

Create and launch a runnable app bundle:

```bash
./script/build_and_run.sh --verify
```

## 仓库说明 / Repository Notes

`.gitignore` 会排除构建产物、打包应用、ZIP 文件与本机 macOS 元数据。请不要提交 API Key、业务空间凭据或钥匙串数据。

`.gitignore` excludes build artifacts, packaged apps, ZIP files, and local macOS metadata. Do not commit API keys, workspace credentials, or Keychain data.
