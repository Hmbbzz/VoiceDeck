# VoiceDeck UI Redesign v1

## 1. Product Intent

VoiceDeck is a calm macOS work companion for voice-first questions with optional frontmost-window context. The interface must make three things immediately clear:

1. What conversation is active.
2. Whether VoiceDeck is listening, processing, or idle.
3. Whether the screenshot attached to an Option + X request will be sent.

The visual personality is monochrome and efficient. The blue-purple Signal orb is the only expressive color and represents VoiceDeck's presence.

## 2. Confirmed Direction

| Area | Decision |
| --- | --- |
| Theme | White, black, and neutral grays. No persistent blue UI chrome. |
| Brand asset | A code-rendered blue orb with a small purple-blue core. |
| Main window density | Efficiency mode: compact, readable, and desktop-first. |
| Empty state headline | `随时开口，继续眼前的工作` |
| Floating window default | The compact voice card inspired by reference 5. |
| Screenshot mode | Start compact; expand only after the screenshot is successfully captured. |
| End of recording | Fade out immediately when the shortcut is released. |

## 3. Signal Orb

### Purpose

Signal is VoiceDeck's single animated brand element. It appears in the sidebar logo, new-conversation state, and voice floating window. Every placement uses the same component and state model so the product reads as one system.

### Construction

Signal is rendered in SwiftUI, not as an image asset:

- Inner core: compact purple-blue radial glow.
- Energy body: cyan-blue blurred circle.
- Halo: very low-opacity blue-white outer glow.

The initial implementation uses layered SwiftUI shapes, blur, and keyframe animation. It should only move while VoiceDeck is active. Metal shader refinement is deferred until visual QA proves it is necessary.

### State Model

| State | Behaviour | Locations |
| --- | --- | --- |
| Idle | Almost still; no attention-seeking pulse. | Sidebar logo |
| Ready | One slow, subtle 5-6 second breath. | Empty conversation |
| Listening | Scale and halo react to microphone level. | Floating window |
| Capturing context | Listening behavior plus a short successful-capture confirmation. | Expanded floating window |
| Thinking | Slow inward/outward breathing; no audio-reactive movement. | Floating window or conversation loading state |
| Reduced Motion | Static glow with only opacity changes. | All locations |

## 4. Main Window

### Layout

- Native macOS split view.
- Sidebar: Signal logo, new conversation, search, recent conversations, settings, and compose action.
- Toolbar: conversation title, provider/model menu, context duration, settings.
- Detail: efficient reading column with attachment-aware chat messages.
- Composer: anchored at the bottom with typed input, attach action, screenshot voice action, and hold-to-talk control.

### Empty Conversation

- Centered Signal orb, approximately 96pt.
- Headline: `随时开口，继续眼前的工作`.
- Supporting instruction: `按住 Option + Z 说话，或按住 Option + X 截图并提问`.
- Three concise suggestion rows: summarize current page, explain screen content, organize an idea.

### Message and Attachment Treatment

- User messages remain compact and visually secondary to the assistant answer.
- Screenshot attachments appear as real image thumbnails, not inline text markers.
- Each thumbnail includes the source app/window and capture time below it.
- Clicking an attachment opens a large preview with source information.
- The model is called only after a successful capture has been persisted to the user message.

## 5. Voice Floating Window

### Compact Default

The default card uses the reference-5 composition:

- Left: 56pt Signal orb.
- Center: a concise listening label and live transcription.
- Bottom: selected microphone name.
- No visible hard border; use a light material, 20pt corner radius, restrained shadow, and a subtle divider only above the metadata row.

### Live Transcription: Latest 20 Characters

The floating window shows a single visual line of the most recent 20 user-perceived characters (Swift `Character` grapheme clusters):

- New characters enter from the right with a short linear slide.
- Once text exceeds 20 characters, the oldest characters move left and disappear; they are not retained in the floating window.
- The complete recognized transcript remains in the conversation and is not truncated there.
- The card width is content-driven within stable limits: minimum 420pt, maximum 720pt. It grows in small animated steps as the visible text grows, then stops at the maximum and continues the leftward rolling line.
- The current design uses one line to preserve peripheral readability. A very short transcript keeps the card compact rather than leaving a large empty text region.

### Screenshot Expansion

For Option + X, the card does not expand until capture succeeds:

- Add a 96 x 72pt screenshot thumbnail on the left of Signal.
- Show a single green confirmation mark for 500ms, then return to the blue Signal palette.
- Bottom metadata shows `Safari - 当前窗口` or the corresponding source application/window.
- If capture fails, keep the compact card and show `未附加截图，仍将发送语音`.

### Shortcut Release

- Releasing Option + Z or Option + X sends the request.
- The floating window fades out immediately, using a short 160-200ms opacity transition.
- The main conversation shows the final transcription, screenshot state, and streaming response.

## 6. Error and Configuration Treatment

- A provider without an API Key is indicated in Settings and blocked before microphone access or screenshot capture starts.
- Microphone, screen-recording, capture, and provider failures use a concise retryable message in the composer area.
- Do not use modal alerts for recoverable errors.

## 7. Implementation Boundaries

### Code-rendered UI

- Signal orb, material cards, buttons, icons, waveform, chat layout, and all text.
- SF Symbols are the only icon family.

### No bitmap asset requirement

The reference imagery is a direction for layout and motion, not an in-app image dependency. Screenshot thumbnails are user-captured content.

## 8. Acceptance Criteria

1. The Signal orb looks consistent across sidebar, empty state, and floating window.
2. Blue-purple color is absent from passive UI chrome and only appears with Signal or active audio controls.
3. The voice card visibly shows only the latest 20 characters while recording, without resizing jitter.
4. Option + X only expands with a screenshot after capture success.
5. On shortcut release, the card immediately fades out and the full turn continues in the main chat.
6. Reduce Motion produces a calm static alternative.
