import Foundation

enum ClipboardImportResolver {
    enum ImportResult: Equatable {
        case existingFile(URL)
        case createdFile(URL)

        var url: URL {
            switch self {
            case .existingFile(let url), .createdFile(let url):
                return url
            }
        }
    }

    enum ImportError: Error, Equatable {
        case emptyClipboardText
    }

    static func resolve(
        text: String,
        fileManager: FileManager = .default,
        temporaryDirectory: URL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    ) throws -> ImportResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ImportError.emptyClipboardText
        }

        if let existing = existingFileURL(from: trimmed, fileManager: fileManager) {
            return .existingFile(existing)
        }

        let url = temporaryDirectory.appendingPathComponent("nanum-csv-clipboard-\(UUID().uuidString).csv")
        try text.data(using: .utf8)?.write(to: url, options: .atomic)
        return .createdFile(url)
    }

    private static func existingFileURL(from text: String, fileManager: FileManager) -> URL? {
        if let url = URL(string: text), url.isFileURL, fileManager.fileExists(atPath: url.path) {
            return URL(fileURLWithPath: url.path)
        }

        if text.contains("\n") || text.contains("\r") {
            return nil
        }

        let expanded = (text as NSString).expandingTildeInPath
        guard fileManager.fileExists(atPath: expanded) else { return nil }
        return URL(fileURLWithPath: expanded)
    }
}
