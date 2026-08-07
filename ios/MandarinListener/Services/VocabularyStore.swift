import Combine
import Foundation
import MandarinListenerCore

@MainActor
final class VocabularyStore: ObservableObject {
    @Published private(set) var entries: [VocabularyEntry] = []

    var onEntriesChange: (([VocabularyEntry]) -> Void)?

    private let learner = VocabularyLearner()
    private let fileManager: FileManager
    private let fileURL: URL
    private var undoEntries: [VocabularyEntry]?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let directory = applicationSupport.appending(
            path: "MandarinListener",
            directoryHint: .isDirectory
        )
        fileURL = directory.appending(path: "vocabulary.json")
        load()
    }

    @discardableResult
    func learnFromCorrection(
        originalText: String,
        correctedText: String
    ) -> [String] {
        let result = learner.applyingCorrection(
            originalText: originalText,
            correctedText: correctedText,
            to: entries
        )
        guard !result.learnedTerms.isEmpty else { return [] }

        let currentEntries = entries
        entries = result.entries
        guard persist() else {
            entries = currentEntries
            return []
        }
        undoEntries = result.previousEntries
        onEntriesChange?(entries)
        return result.learnedTerms
    }

    func undoLastLearning() {
        guard let undoEntries else { return }
        let currentEntries = entries
        entries = undoEntries
        guard persist() else {
            entries = currentEntries
            return
        }
        self.undoEntries = nil
        onEntriesChange?(entries)
    }

    func remove(_ entry: VocabularyEntry) {
        let currentEntries = entries
        entries.removeAll { $0.term == entry.term }
        guard persist() else {
            entries = currentEntries
            return
        }
        undoEntries = nil
        onEntriesChange?(entries)
    }

    func appleTerms() -> [String] {
        learner.appleBiasTerms(from: entries)
    }

    func onDeviceTerms() -> [String] {
        learner.onDeviceHotwords(from: entries)
    }

    func elevenLabsTerms() -> [String] {
        learner.elevenLabsKeyterms(from: entries)
    }

    private func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode([VocabularyEntry].self, from: data)
            entries = learner.ranked(decoded, limit: VocabularyLearner.appleTermLimit)
        } catch {
            entries = []
        }
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var directoryURL = directory
            try directoryURL.setResourceValues(resourceValues)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])

            var fileValues = URLResourceValues()
            fileValues.isExcludedFromBackup = true
            var protectedFileURL = fileURL
            try protectedFileURL.setResourceValues(fileValues)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: fileURL.path
            )
            return true
        } catch {
            return false
        }
    }
}
