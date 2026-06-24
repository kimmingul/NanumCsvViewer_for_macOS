import Foundation

public enum CsvError: Error, LocalizedError {
    case unsupportedEncoding(String)
    case fileOpenFailed(String)
    case shortRead
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .unsupportedEncoding(let name):
            return "'\(name)' encoding is not supported in high-speed mode. Use UTF-8 or CP949/EUC-KR."
        case .fileOpenFailed(let path):
            return "Could not open file: \(path)"
        case .shortRead:
            return "The file became shorter while reading. It may have been changed by another process."
        case .cancelled:
            return "The operation was cancelled."
        }
    }
}
