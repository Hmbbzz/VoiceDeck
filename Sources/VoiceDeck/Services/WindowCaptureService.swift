import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

struct CapturedWindowContext {
    let imageData: Data
    let ownerName: String
    let windowTitle: String?

    var displayName: String {
        if let windowTitle, !windowTitle.isEmpty {
            return "\(ownerName) - \(windowTitle)"
        }
        return ownerName
    }
}

enum WindowCaptureError: LocalizedError {
    case permissionDenied
    case permissionRequiresRestart
    case noWindow
    case windowNotShareable
    case captureFailed(String)
    case compressionFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Voice Deck 尚未获得屏幕录制权限。请在系统设置中允许后重新尝试。"
        case .permissionRequiresRestart:
            "已请求屏幕录制权限。请允许后完全退出并重新打开 Voice Deck，再截取窗口。"
        case .noWindow:
            "没有找到可截图的前台窗口。"
        case .windowNotShareable:
            "当前最上方窗口不允许被截图。请切换到需要作为上下文的窗口后重试。"
        case let .captureFailed(message):
            "无法截取当前窗口：\(message)"
        case .compressionFailed:
            "窗口截图压缩失败。"
        }
    }
}

enum WindowCaptureService {
    static func captureFrontmostWindow(maxBase64Bytes: Int = 250_000) async throws -> CapturedWindowContext {
        try ensureScreenCaptureAccess()

        guard let candidate = frontmostWindows().first else {
            throw WindowCaptureError.noWindow
        }

        let image = try await captureImage(for: candidate)

        guard let imageData = jpegData(for: image, maxBase64Bytes: maxBase64Bytes) else {
            throw WindowCaptureError.compressionFailed
        }

        return CapturedWindowContext(
            imageData: imageData,
            ownerName: candidate.ownerName,
            windowTitle: candidate.windowTitle
        )
    }

    static func requestScreenCaptureAccess() -> String {
        guard !CGPreflightScreenCaptureAccess() else {
            return "屏幕录制权限已启用。"
        }

        NSApp.activate(ignoringOtherApps: true)
        if CGRequestScreenCaptureAccess() {
            return "已请求屏幕录制权限。允许后请完全退出并重新打开 Voice Deck。"
        }
        return "系统尚未授予屏幕录制权限。请在系统弹窗中允许 Voice Deck 后重试。"
    }

    private static func ensureScreenCaptureAccess() throws {
        guard !CGPreflightScreenCaptureAccess() else { return }
        if CGRequestScreenCaptureAccess() {
            throw WindowCaptureError.permissionRequiresRestart
        }
        throw WindowCaptureError.permissionDenied
    }

    private static func captureImage(for candidate: WindowCandidate) async throws -> CGImage {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            if let window = content.windows.first(where: { $0.windowID == candidate.id }) {
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let configuration = SCStreamConfiguration()
                let pixelScale = CGFloat(filter.pointPixelScale)
                configuration.width = max(1, Int(window.frame.width * pixelScale))
                configuration.height = max(1, Int(window.frame.height * pixelScale))
                configuration.showsCursor = false
                if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) {
                    return image
                }
            }
        } catch {
            // Fall through to the window-frame capture below.
        }

        if #available(macOS 15.2, *) {
            do {
                return try await SCScreenshotManager.captureImage(in: candidate.bounds)
            } catch {
                throw WindowCaptureError.captureFailed(error.localizedDescription)
            }
        }

        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            candidate.id,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            throw WindowCaptureError.windowNotShareable
        }
        return image
    }

    private static func frontmostWindows() -> [WindowCandidate] {
        let currentProcessID = getpid()
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else {
            return []
        }

        return windows.compactMap { window in
            let layer = window[kCGWindowLayer as String] as? Int ?? Int.max
            let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t ?? 0
            let alpha = window[kCGWindowAlpha as String] as? Double ?? 1
            guard layer == 0, ownerPID != currentProcessID, alpha > 0 else { return nil }
            guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? Double,
                  let y = bounds["Y"] as? Double,
                  let width = bounds["Width"] as? Double,
                  let height = bounds["Height"] as? Double,
                  width >= 80,
                  height >= 80,
                  let id = window[kCGWindowNumber as String] as? CGWindowID,
                  let ownerName = window[kCGWindowOwnerName as String] as? String else {
                return nil
            }
            return WindowCandidate(
                id: id,
                bounds: CGRect(x: x, y: y, width: width, height: height),
                ownerName: ownerName,
                windowTitle: window[kCGWindowName as String] as? String
            )
        }
    }

    private static func jpegData(for image: CGImage, maxBase64Bytes: Int) -> Data? {
        let resized = resizedImageIfNeeded(image, maxDimension: 1_280)
        let bitmap = NSBitmapImageRep(cgImage: resized)
        var compression: CGFloat = 0.78

        while compression >= 0.22 {
            let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: compression])
            if let data, data.base64EncodedData().count <= maxBase64Bytes {
                return data
            }
            compression -= 0.14
        }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.18])
    }

    private static func resizedImageIfNeeded(_ image: CGImage, maxDimension: CGFloat) -> CGImage {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let scale = min(1, maxDimension / max(width, height))
        guard scale < 1 else { return image }

        let size = CGSize(width: floor(width * scale), height: floor(height * scale))
        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage() ?? image
    }
}

private struct WindowCandidate {
    let id: CGWindowID
    let bounds: CGRect
    let ownerName: String
    let windowTitle: String?
}
