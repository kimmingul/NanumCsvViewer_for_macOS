import Foundation

public struct SavedCsvView: Equatable, Codable, Sendable {
    public let name: String
    public let filterText: String?
    public let filterColumn: Int?
    public let sortKeys: [SortKey]
    public let hiddenColumnIndexes: [Int]
    public let searchQuery: CsvSearchQuery?
    public let currentColumn: Int

    public init(
        name: String,
        filterText: String?,
        filterColumn: Int?,
        sortKeys: [SortKey],
        hiddenColumnIndexes: [Int],
        searchQuery: CsvSearchQuery?,
        currentColumn: Int
    ) {
        self.name = name
        self.filterText = filterText
        self.filterColumn = filterColumn
        self.sortKeys = sortKeys
        self.hiddenColumnIndexes = Array(Set(hiddenColumnIndexes)).sorted()
        self.searchQuery = searchQuery
        self.currentColumn = max(0, currentColumn)
    }
}
