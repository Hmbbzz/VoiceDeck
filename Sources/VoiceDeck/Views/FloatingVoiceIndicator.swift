import AppKit
import SwiftUI

@MainActor
final class FloatingVoiceIndicatorController {
    private var panel: NSPanel?
    private var pendingHide: DispatchWorkItem?

    func show() {
        pendingHide?.cancel()
        present(.recording)
    }

    func showCaptureFeedback(success: Bool) {
        pendingHide?.cancel()
        present(success ? .captureSuccess : .captureFailed)

        let hideWorkItem = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        pendingHide = hideWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: hideWorkItem)
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
        panel?.contentView = NSHostingView(rootView: FloatingVoiceIndicator(mode: mode))
        panel?.setContentSize(mode.size)
        positionPanel()
        panel?.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 132, height: 44),
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
        panel.contentView = NSHostingView(rootView: FloatingVoiceIndicator(mode: .recording))
        return panel
    }

    private func positionPanel() {
        guard let panel else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.minY + 24
        )
        panel.setFrameOrigin(origin)
    }
}

private enum FloatingIndicatorMode {
    case recording
    case captureSuccess
    case captureFailed

    var size: NSSize {
        switch self {
        case .recording: NSSize(width: 132, height: 44)
        case .captureSuccess, .captureFailed: NSSize(width: 84, height: 44)
        }
    }
}

private struct FloatingVoiceIndicator: View {
    let mode: FloatingIndicatorMode

    var body: some View {
        Group {
            switch mode {
            case .recording:
                HStack(spacing: 10) {
                    EqualizerBars(flipped: false)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18, weight: .semibold))
                    EqualizerBars(flipped: true)
                }
            case .captureSuccess, .captureFailed:
                HStack(spacing: 10) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 17, weight: .medium))
                    Rectangle()
                        .fill(.white.opacity(0.34))
                        .frame(width: 1, height: 16)
                    Image(systemName: mode == .captureSuccess ? "checkmark" : "exclamationmark")
                        .font(.system(size: 15, weight: .bold))
                }
            }
        }
        .foregroundStyle(.white)
        .frame(width: mode.size.width, height: mode.size.height)
        .background {
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.94))
        }
        .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
    }
}

private struct EqualizerBars: View {
    let flipped: Bool
    @State private var isAnimating = false

    private let heights: [CGFloat] = [10, 17, 13]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .frame(width: 3, height: height)
                    .scaleEffect(y: isAnimating ? (index == 1 ? 1.16 : 0.72) : 1, anchor: .center)
                    .animation(
                        .easeInOut(duration: 0.42).repeatForever(autoreverses: true).delay(Double(index) * 0.08),
                        value: isAnimating
                    )
            }
        }
        .scaleEffect(x: flipped ? -1 : 1, y: 1)
        .opacity(0.9)
        .onAppear { isAnimating = true }
    }
}
