import Foundation

/// Removes temporary files the app leaves behind: the Excel/SQLite temp-CSV
/// bridge directories (one UUID subdirectory per open) and clipboard
/// quick-import CSVs. These live under the user temp directory, which macOS
/// only sweeps occasionally, so without this they accumulate across sessions.
enum TempFileCleanup {
    static let bridgeDirectoryNames = ["NanumCsvViewerXlsx", "NanumCsvViewerSqlite"]
    static let clipboardFilePrefix = "nanum-csv-clipboard-"

    /// Deletes leftover bridge directories and clipboard files older than
    /// `minimumAge`. The age gate matters because a document opened at launch
    /// (`application(_:openFile:)` runs before `applicationDidFinishLaunching`)
    /// creates a fresh bridge directory that this sweep must not race-delete;
    /// only entries from prior sessions are old enough to remove. Returns the
    /// number of top-level items deleted.
    @discardableResult
    static func removeStaleTempFiles(
        in temporaryDirectory: URL,
        minimumAge: TimeInterval = 0,
        now: Date,
        fileManager: FileManager = .default
    ) -> Int {
        func isOldEnough(_ url: URL) -> Bool {
            guard minimumAge > 0 else { return true }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            guard let modified else { return true }
            return now.timeIntervalSince(modified) >= minimumAge
        }

        var removed = 0
        for name in bridgeDirectoryNames {
            let directory = temporaryDirectory.appendingPathComponent(name, isDirectory: true)
            if fileManager.fileExists(atPath: directory.path), isOldEnough(directory),
               (try? fileManager.removeItem(at: directory)) != nil {
                removed += 1
            }
        }
        if let entries = try? fileManager.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) {
            for entry in entries where entry.lastPathComponent.hasPrefix(clipboardFilePrefix) && isOldEnough(entry) {
                if (try? fileManager.removeItem(at: entry)) != nil {
                    removed += 1
                }
            }
        }
        return removed
    }
}
