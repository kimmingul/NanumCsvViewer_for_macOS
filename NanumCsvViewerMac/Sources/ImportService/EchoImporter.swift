import Foundation
import ImportServiceProtocol

public enum EchoImporter {
    public enum Error: Swift.Error, Equatable {
        case maxBytesExceeded
        case timeoutExceeded
        case unsupportedKind
    }

    public static func copy(source: FileHandle, output: FileHandle, outputURL: URL, limits: ImportLimits) throws -> ImportResult {
        let deadline = Date().addingTimeInterval(limits.timeoutSeconds)

        do {
            try source.seek(toOffset: 0)
            try output.truncate(atOffset: 0)
            var copied: Int64 = 0
            while true {
                if Date() > deadline {
                    throw Error.timeoutExceeded
                }
                let chunk = try source.read(upToCount: 64 * 1024) ?? Data()
                if chunk.isEmpty {
                    break
                }
                copied += Int64(chunk.count)
                if copied > limits.maxBytes {
                    throw Error.maxBytesExceeded
                }
                try output.write(contentsOf: chunk)
            }
            return ImportResult(csvURL: outputURL, metadataURL: nil, warnings: [], rowCount: 0, columnCount: 0)
        } catch {
            try? output.truncate(atOffset: 0)
            throw error
        }
    }
}
