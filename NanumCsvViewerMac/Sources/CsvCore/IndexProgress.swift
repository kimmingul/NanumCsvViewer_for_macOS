import Foundation

public struct IndexProgress: Sendable {
    public let bytesProcessed: Int64
    public let fileLength: Int64
    public let rowsSoFar: Int64

    public init(bytesProcessed: Int64, fileLength: Int64, rowsSoFar: Int64) {
        self.bytesProcessed = bytesProcessed
        self.fileLength = fileLength
        self.rowsSoFar = rowsSoFar
    }

    public var percent: Int {
        guard fileLength > 0 else { return 100 }
        return min(100, Int(bytesProcessed * 100 / fileLength))
    }
}

public struct SortKey: Sendable, Equatable {
    public let column: Int
    public let ascending: Bool

    public init(column: Int, ascending: Bool) {
        self.column = column
        self.ascending = ascending
    }
}
