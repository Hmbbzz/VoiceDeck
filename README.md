# VoiceDeck

VoiceDeck is a native macOS desktop assistant for asking about the work already in front of you. Hold a global shortcut to speak, or capture the frontmost window and ask about it in the same turn.

中文桌面语音助手：按住快捷键说话，松开后发送；也可以同时附带当前前台窗口截图，让多模态模型理解屏幕上下文。

## Highlights

- Global push-to-talk: hold `Option + Z`, then release to send.
- Visual voice question: hold `Option + X` to capture the frontmost window and record in parallel. A successful capture is attached to the same user message before it is sent to the model.
- Compact non-activating floating indicator with live transcript feedback.
- Adaptive voice gate prevents silence and incidental noise from reaching transcription.
- Qwen Realtime transcription through Alibaba Cloud Model Studio (DashScope).
- Multimodal conversation providers: Qwen, OpenAI, Kimi, and GLM. The model picker only exposes image-capable models.
- Streaming text responses, persistent conversation history, automatic titles from the first exchange, screenshot attachments, and full-size image preview.
- Bailian TTS for all responses, selectable voice, and a stop-speaking control while audio is playing.
- Configurable input microphone, conversation continuation window, screen-capture permission flow, and local macOS Keychain storage for API keys.

## Requirements

- macOS 14 or later
- Swift 5.10 or later / Xcode Command Line Tools
- A DashScope API Key and Beijing-region Model Studio workspace ID for transcription and Bailian TTS
- API keys for any optional conversation provider you enable

## Configure

Open Settings in the app and configure:

1. DashScope workspace ID and API Key. This is required for voice transcription and speech playback.
2. An input microphone and optional TTS voice.
3. A conversation provider and its API Key. Qwen reuses the DashScope key; OpenAI, Kimi, and GLM store their own key in macOS Keychain.
4. Screen Recording permission before using `Option + X`. macOS may require a full application relaunch after granting this permission.

Keys are never written to this repository. They are saved locally in macOS Keychain only.

## Run Locally

```bash
./script/build_and_run.sh
```

Create a separately named local test application when permission records must be isolated:

```bash
./script/build_and_run.sh --test
./script/build_and_run.sh --test2
./script/build_and_run.sh --test3
./script/build_and_run.sh --test4
```

Each test variant has its own Bundle ID and is written to `dist/`. For reliable reuse of macOS privacy permissions across rebuilt binaries, install an Apple Development certificate in Xcode. The script discovers and uses it automatically; otherwise it falls back to ad-hoc signing.

## Verify

```bash
swift build

swiftc Sources/VoiceDeck/Services/VoiceTranscriptFilter.swift \
  script/test_voice_transcript_filter.swift \
  -o /tmp/voicedeck-transcript-filter-tests
/tmp/voicedeck-transcript-filter-tests

swiftc Sources/VoiceDeck/Services/QwenRealtimeConfiguration.swift \
  Sources/VoiceDeck/Services/QwenRealtimeClient.swift \
  script/test_realtime_configuration.swift \
  -o /tmp/voicedeck-realtime-tests
/tmp/voicedeck-realtime-tests

swiftc -parse-as-library \
  Sources/VoiceDeck/Models/Conversation.swift \
  Sources/VoiceDeck/Services/ConversationProvider.swift \
  Sources/VoiceDeck/Services/OpenAICompatibleConversationProvider.swift \
  script/test_conversation_provider.swift \
  -o /tmp/voicedeck-conversation-provider-tests
/tmp/voicedeck-conversation-provider-tests
```

## Project Notes

- Product and UI decisions are documented in [`docs/PRODUCT.md`](docs/PRODUCT.md) and [`docs/UI_REDESIGN_V1.md`](docs/UI_REDESIGN_V1.md).
- `design-demo/` contains local HTML explorations of the redesigned desktop and floating UI.
- Build output, app bundles, local metadata, API keys, workspace credentials, and Keychain data must not be committed.
