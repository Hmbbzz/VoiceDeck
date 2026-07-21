import Darwin
import Foundation

@main
struct AttachmentStoreTests {
    static func main() {
        var failures: [String] = []

        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { failures.append(message) }
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceDeckAttachmentStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let store = AttachmentStore(baseDirectory: temporaryDirectory)
        let imageData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        do {
            let attachment = try store.saveImage(
                imageData,
                mimeType: "image/png",
                displayName: "Current window",
                screenshotSource: .init(applicationName: "Safari", windowTitle: "VoiceDeck")
            )
            expect(!attachment.fileName.hasPrefix("/"), "Attachment metadata must not contain an absolute path")
            expect(attachment.fileName.hasSuffix(".png"), "PNG attachments must use a PNG extension")
            expect(attachment.byteCount == imageData.count, "Attachment metadata must retain byte count")
            expect(attachment.screenshotSource?.applicationName == "Safari", "Screenshot source must persist")
            let loadedImage = try store.loadImage(for: attachment)
            expect(loadedImage == imageData, "Saved image must round-trip")

            try store.delete(attachment)
            do {
                _ = try store.loadImage(for: attachment)
                failures.append("Deleted attachment must not be readable")
            } catch AttachmentStoreError.attachmentNotFound {
                // Expected.
            }
        } catch {
            failures.append("Round-trip or deletion failed: \(error)")
        }

        let unsafeAttachment = ChatAttachment(
            fileName: "../outside.png",
            mimeType: "image/png",
            byteCount: imageData.count,
            displayName: "Unsafe"
        )
        do {
            _ = try store.loadImage(for: unsafeAttachment)
            failures.append("Path traversal file name must be rejected")
        } catch AttachmentStoreError.invalidFileName {
            // Expected.
        } catch {
            failures.append("Path traversal must return invalidFileName, got: \(error)")
        }

        let messageID = UUID()
        let createdAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let oldMessageJSON = """
        {
          "id": "\(messageID.uuidString)",
          "role": "user",
          "content": "legacy message",
          "createdAt": 1000
        }
        """.data(using: .utf8)!
        do {
            let legacyMessage = try JSONDecoder().decode(ChatMessage.self, from: oldMessageJSON)
            expect(legacyMessage.attachments.isEmpty, "Old ChatMessage JSON must decode with no attachments")
            expect(legacyMessage.createdAt == createdAt, "Legacy ChatMessage timestamp must decode")
        } catch {
            failures.append("Legacy ChatMessage JSON failed to decode: \(error)")
        }

        guard failures.isEmpty else {
            failures.forEach { fputs("FAIL: \($0)\n", stderr) }
            exit(EXIT_FAILURE)
        }
        print("Attachment store tests passed.")
    }
}
