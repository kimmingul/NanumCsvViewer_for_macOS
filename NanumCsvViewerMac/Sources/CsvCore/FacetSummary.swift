import Foundation

public struct FacetColumnRequest: Equatable, Sendable {
    public let column: Int
    public let wantsHistogram: Bool

    public init(column: Int, wantsHistogram: Bool) {
        self.column = column
        self.wantsHistogram = wantsHistogram
    }
}

public struct FacetValueBin: Equatable, Sendable {
    public let value: String
    public let count: Int

    public init(value: String, count: Int) {
        self.value = value
        self.count = count
    }
}

public struct FacetHistogramBin: Equatable, Sendable {
    public let lowerBound: Double
    public let upperBound: Double
    public let count: Int

    public init(lowerBound: Double, upperBound: Double, count: Int) {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.count = count
    }
}

public struct FacetSummary: Equatable, Sendable {
    public enum Content: Equatable, Sendable {
        case topValues(bins: [FacetValueBin], otherCount: Int, distinctTruncated: Bool)
        case histogram(bins: [FacetHistogramBin], numericCount: Int, nonNumericCount: Int)
    }

    public let column: Int
    public let content: Content

    public init(column: Int, content: Content) {
        self.column = column
        self.content = content
    }
}

public struct FacetReport: Equatable, Sendable {
    public let summaries: [FacetSummary]
    public let scannedRowCount: Int
    public let totalRowCount: Int

    public init(summaries: [FacetSummary], scannedRowCount: Int, totalRowCount: Int) {
        self.summaries = summaries
        self.scannedRowCount = scannedRowCount
        self.totalRowCount = totalRowCount
    }

    public var isRowCapped: Bool {
        scannedRowCount < totalRowCount
    }
}
