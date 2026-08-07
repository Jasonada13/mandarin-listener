import Foundation
import MandarinListenerCore

enum TranscriptExporter {
    private static let filenamePrefix = "Mandarin-Listener-"

    static func createExport(
        entries: [TranscriptEntry],
        sessionStartedAt: Date
    ) throws -> URL {
        let markdown = TranscriptFormatter.markdown(
            entries: entries,
            sessionStartedAt: sessionStartedAt
        )
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(filenamePrefix)\(UUID().uuidString).md")
        try Data(markdown.utf8).write(
            to: url,
            options: [.atomic, .completeFileProtection]
        )
        return url
    }

    static func removeExport(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func removeStaleExports() {
        let directory = FileManager.default.temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        for file in files where file.lastPathComponent.hasPrefix(filenamePrefix) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
