import Foundation

public enum TranscriptFormatter {
    public static func markdown(
        entries: [TranscriptEntry],
        sessionStartedAt: Date,
        generatedAt: Date = Date()
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        var lines = [
            "# Mandarin Listener Transcript",
            "",
            "Session: \(dateFormatter.string(from: sessionStartedAt))",
            "Exported: \(dateFormatter.string(from: generatedAt))",
            ""
        ]

        for entry in entries {
            lines.append("## \(dateFormatter.string(from: entry.finalizedAt))")
            lines.append("")
            lines.append("**中文**")
            lines.append("")
            lines.append(entry.sourceText)
            lines.append("")
            lines.append("**English**")
            lines.append("")
            lines.append(entry.displayTranslation ?? "_Translation unavailable_")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
