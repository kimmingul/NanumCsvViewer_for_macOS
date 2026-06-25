import Foundation

public struct IndexProgress: Sendable {
    public let bytesProcessed: Int64
    public let fileLength: Int64
    public let rowsSoFar: Int64
    public let percentOverride: Int?

    public init(bytesProcessed: Int64, fileLength: Int64, rowsSoFar: Int64, percentOverride: Int? = nil) {
        self.bytesProcessed = bytesProcessed
        self.fileLength = fileLength
        self.rowsSoFar = rowsSoFar
        self.percentOverride = percentOverride
    }

    public var percent: Int {
        if let percentOverride {
            return max(0, min(100, percentOverride))
        }
        guard fileLength > 0 else { return 100 }
        return min(100, Int(bytesProcessed * 100 / fileLength))
    }
}

public struct SortKey: Sendable, Equatable, Codable {
    public let column: Int
    public let ascending: Bool

    public init(column: Int, ascending: Bool) {
        self.column = column
        self.ascending = ascending
    }
}
