import AppKit
import NaturalLanguage
import Observation
import SwiftUI

@MainActor
@Observable
private final class FloatingIndicatorState {
    var mode: FloatingIndicatorMode = .recording(transcript: "")
    var audioActivity: Double = 0
}

@MainActor
final class FloatingVoiceIndicatorController {
    private var panel: NSPanel?
    private var pendingHide: DispatchWorkItem?
    private let indicatorState = FloatingIndicatorState()

    func show(
        transcript: String = "",
        captureStatus: WindowCaptureStatus? = nil,
        audioActivity: Double = 0
    ) {
        pendingHide?.cancel()
        indicatorState.audioActivity = audioActivity
        present(.recording(transcript: transcript))
    }

    func updateRecording(transcript: String, captureStatus: WindowCaptureStatus?) {
        guard panel?.isVisible == true else { return }
        pendingHide?.cancel()
        present(.recording(transcript: VoiceTranscriptFilter.sanitized(transcript) ?? ""))
    }

    func updateAudioActivity(_ activity: Double) {
        guard panel?.isVisible == true else { return }
        indicatorState.audioActivity = min(max(activity, 0), 1)
    }

    func showCaptureFeedback(success: Bool) {
        pendingHide?.cancel()
        indicatorState.audioActivity = 0
        present(success ? .captureSuccess : .captureFailed)

        let hideWorkItem = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        pendingHide = hideWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: hideWorkItem)
    }

    func hide() {
        pendingHide?.cancel()
        pendingHide = nil
        panel?.orderOut(nil)
    }

    private func present(_ mode: FloatingIndicatorMode) {
        if panel == nil {
            panel = makePanel()
        }
        indicatorState.mode = mode
        panel?.setContentSize(mode.size)
        positionPanel()
        panel?.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: indicatorState.mode.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let hostingView = NSHostingView(rootView: FloatingVoiceIndicator(state: indicatorState))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.masksToBounds = false
        hostingView.layer?.shadowOpacity = 0
        panel.contentView = hostingView
        return panel
    }

    private func positionPanel() {
        guard let panel else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.minY + 28
        ))
    }
}

private enum FloatingIndicatorMode {
    case recording(transcript: String)
    case captureSuccess
    case captureFailed

    var displayText: String {
        switch self {
        case let .recording(transcript):
            TranscriptWindow.latestWords(from: VoiceTranscriptFilter.sanitized(transcript) ?? "", limit: 20)
        case .captureSuccess:
            "截图已附带"
        case .captureFailed:
            "截图未完成"
        }
    }

    var size: NSSize {
        let textWidth = CGFloat(max(displayText.count, 4)) * 13
        return NSSize(width: min(max(28 + textWidth, 132), 360), height: 48)
    }
}

private struct FloatingVoiceIndicator: View {
    @Bindable var state: FloatingIndicatorState

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 9) {
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 6, height: 6)
                    .scaleEffect(state.audioActivity > 0.08 ? 1.12 : 1)

                Text(state.mode.displayText.isEmpty ? " " : state.mode.displayText)
                    .id(state.mode.displayText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.96))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(x: 9)),
                        removal: .opacity.combined(with: .offset(x: -9))
                    ))
            }
        }
        .padding(.horizontal, 14)
        .frame(width: state.mode.size.width, height: state.mode.size.height)
        .background(Color(red: 0.14, green: 0.16, blue: 0.22))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.easeOut(duration: 0.22), value: state.mode.displayText)
        .animation(.snappy(duration: 0.25), value: state.mode.size.width)
        .animation(.easeOut(duration: 0.16), value: state.audioActivity > 0.08)
    }

    private var indicatorColor: Color {
        switch state.mode {
        case .captureSuccess:
            Color(red: 0.40, green: 0.88, blue: 0.65)
        case .captureFailed:
            Color(red: 1.0, green: 0.67, blue: 0.40)
        case .recording:
            state.audioActivity > 0.08
                ? Color(red: 0.40, green: 0.67, blue: 1.0)
                : Color(red: 0.57, green: 0.63, blue: 0.74)
        }
    }
}

private enum TranscriptWindow {
    static func latestWords(from text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }

        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = trimmed
        let fullRange = trimmed.startIndex ..< trimmed.endIndex
        let tokens = tokenizer.tokens(for: fullRange)
        var start = trimmed.endIndex

        for token in tokens.reversed() {
            let candidate = trimmed[token.lowerBound ..< trimmed.endIndex]
            if candidate.count > limit {
                break
            }
            start = token.lowerBound
        }

        if start == trimmed.endIndex {
            return String(trimmed.suffix(limit))
        }
        return String(trimmed[start ..< trimmed.endIndex])
    }
}
