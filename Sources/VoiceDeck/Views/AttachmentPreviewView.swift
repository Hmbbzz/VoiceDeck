import AppKit
import SwiftUI

/// A compact, reusable preview for an image attachment stored by `AttachmentStore`.
struct AttachmentPreviewView: View {
    let attachment: ChatAttachment
    let attachmentStore: AttachmentStore

    @State private var image: NSImage?
    @State private var failedToLoad = false
    @State private var showsPreview = false

    init(attachment: ChatAttachment, attachmentStore: AttachmentStore = AttachmentStore()) {
        self.attachment = attachment
        self.attachmentStore = attachmentStore
    }

    var body: some View {
        Group {
            if let image {
                loadedAttachment(image)
            } else if failedToLoad {
                missingAttachment
            } else {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在载入附件")
            }
        }
        .onAppear(perform: loadImage)
        .sheet(isPresented: $showsPreview) {
            if let image {
                AttachmentImageViewer(image: image) {
                    openInPreview()
                }
            }
        }
    }

    private func loadedAttachment(_ image: NSImage) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Spacer(minLength: 0)

            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 112, height: 72)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            showsPreview = true
        }
    }

    private var missingAttachment: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.badge.exclamationmark")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.displayName)
                    .lineLimit(1)
                Text("附件文件不可用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("附件文件不可用：\(attachment.displayName)")
    }

    private func loadImage() {
        guard image == nil, !failedToLoad else { return }

        do {
            let data = try attachmentStore.loadImage(for: attachment)
            image = NSImage(data: data)
            failedToLoad = image == nil
        } catch {
            failedToLoad = true
        }
    }

    private func openInPreview() {
        guard let fileURL = try? attachmentStore.url(for: attachment) else { return }
        if let previewURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview") {
            NSWorkspace.shared.open(
                [fileURL],
                withApplicationAt: previewURL,
                configuration: NSWorkspace.OpenConfiguration()
            )
        } else {
            NSWorkspace.shared.open(fileURL)
        }
    }
}

private struct AttachmentImageViewer: View {
    let image: NSImage
    let openInPreview: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.opacity(0.94)
                .ignoresSafeArea()

            GeometryReader { proxy in
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: proxy.size.width - 80, maxHeight: proxy.size.height - 120)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }

            VStack {
                HStack {
                    Spacer()

                    Button(action: openInPreview) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(PreviewRippleIconButtonStyle(foreground: .white, background: .white.opacity(0.16)))
                    .help("在预览中打开")

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(PreviewRippleIconButtonStyle(foreground: .black, background: .white))
                    .help("关闭预览")
                }
                .padding(28)

                Spacer()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("图片预览")
        .frame(minWidth: 840, minHeight: 620)
    }
}

private struct PreviewRippleIconButtonStyle: ButtonStyle {
    let foreground: Color
    let background: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .background(background, in: Circle())
            .overlay {
                Circle()
                    .stroke(foreground.opacity(configuration.isPressed ? 0.32 : 0), lineWidth: 1)
                    .scaleEffect(configuration.isPressed ? 1.48 : 0.6)
                    .opacity(configuration.isPressed ? 1 : 0)
            }
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.22), value: configuration.isPressed)
    }
}
