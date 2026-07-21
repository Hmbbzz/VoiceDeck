import Foundation

enum AttachmentStoreError: LocalizedError {
    case emptyData
    case unsupportedMimeType(String)
    case invalidFileName(String)
    case attachmentNotFound(String)

    var errorDescription: String? {
        switch self {
        case .emptyData:
            "附件数据不能为空。"
        case let .unsupportedMimeType(mimeType):
            "不支持的图片 MIME 类型：\(mimeType)。"
        case let .invalidFileName(fileName):
            "附件文件名不安全：\(fileName)。"
        case let .attachmentNotFound(fileName):
            "找不到附件：\(fileName)。"
        }
    }
}

struct AttachmentStore {
    let baseDirectory: URL
    private let fileManager: FileManager

    init(baseDirectory: URL = AttachmentStore.defaultBaseDirectory, fileManager: FileManager = .default) {
        self.baseDirectory = baseDirectory.standardizedFileURL
        self.fileManager = fileManager
    }

    static var defaultBaseDirectory: URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport
            .appendingPathComponent("Voicedeck", isDirectory: true)
            .appendingPathComponent("Attachments", isDirectory: true)
    }

    @discardableResult
    func saveImage(
        _ data: Data,
        mimeType: String,
        displayName: String,
        screenshotSource: ChatAttachment.ScreenshotSource? = nil
    ) throws -> ChatAttachment {
        guard !data.isEmpty else { throw AttachmentStoreError.emptyData }

        let fileExtension = try fileExtension(for: mimeType)
        let fileName = "\(UUID().uuidString.lowercased()).\(fileExtension)"
        let destination = try fileURL(for: fileName)

        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)

        return ChatAttachment(
            fileName: fileName,
            mimeType: mimeType,
            byteCount: data.count,
            displayName: displayName,
            screenshotSource: screenshotSource
        )
    }

    func loadImage(for attachment: ChatAttachment) throws -> Data {
        let fileURL = try fileURL(for: attachment.fileName)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw AttachmentStoreError.attachmentNotFound(attachment.fileName)
        }
        return try Data(contentsOf: fileURL)
    }

    func url(for attachment: ChatAttachment) throws -> URL {
        try fileURL(for: attachment.fileName)
    }

    func delete(_ attachment: ChatAttachment) throws {
        let fileURL = try fileURL(for: attachment.fileName)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw AttachmentStoreError.attachmentNotFound(attachment.fileName)
        }
        try fileManager.removeItem(at: fileURL)
    }

    private func fileURL(for fileName: String) throws -> URL {
        let validatedName = try validatedFileName(fileName)
        return baseDirectory.appendingPathComponent(validatedName, isDirectory: false)
    }

    private func validatedFileName(_ fileName: String) throws -> String {
        guard !fileName.isEmpty,
              fileName == URL(fileURLWithPath: fileName).lastPathComponent,
              !fileName.contains("/"),
              !fileName.contains("\\"),
              fileName != ".",
              fileName != "..",
              fileName.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "-" || $0 == "_"
              }) else {
            throw AttachmentStoreError.invalidFileName(fileName)
        }
        return fileName
    }

    private func fileExtension(for mimeType: String) throws -> String {
        switch mimeType.lowercased() {
        case "image/jpeg", "image/jpg": "jpg"
        case "image/png": "png"
        case "image/heic": "heic"
        case "image/webp": "webp"
        default: throw AttachmentStoreError.unsupportedMimeType(mimeType)
        }
    }
}
