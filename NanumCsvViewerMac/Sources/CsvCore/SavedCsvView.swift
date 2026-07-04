import Foundation

public struct SavedCsvView: Equatable, Codable, Sendable {
    public let name: String
    public let filterText: String?
    public let filterColumn: Int?
    public let sortKeys: [SortKey]
    public let hiddenColumnIndexes: [Int]
    public let searchQuery: CsvSearchQuery?
    public let currentColumn: Int
    public let columnFilters: ColumnFilterState

    public init(
        name: String,
        filterText: String?,
        filterColumn: Int?,
        sortKeys: [SortKey],
        hiddenColumnIndexes: [Int],
        searchQuery: CsvSearchQuery?,
        currentColumn: Int,
        columnFilters: ColumnFilterState = ColumnFilterState()
    ) {
        self.name = name
        self.filterText = filterText
        self.filterColumn = filterColumn
        self.sortKeys = sortKeys
        self.hiddenColumnIndexes = Array(Set(hiddenColumnIndexes)).sorted()
        self.searchQuery = searchQuery
        self.currentColumn = max(0, currentColumn)
        self.columnFilters = columnFilters
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case filterText
        case filterColumn
        case sortKeys
        case hiddenColumnIndexes
        case searchQuery
        case currentColumn
        case columnFilters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        filterText = try container.decodeIfPresent(String.self, forKey: .filterText)
        filterColumn = try container.decodeIfPresent(Int.self, forKey: .filterColumn)
        sortKeys = try container.decode([SortKey].self, forKey: .sortKeys)
        hiddenColumnIndexes = Array(Set(try container.decode([Int].self, forKey: .hiddenColumnIndexes))).sorted()
        searchQuery = try container.decodeIfPresent(CsvSearchQuery.self, forKey: .searchQuery)
        currentColumn = max(0, try container.decode(Int.self, forKey: .currentColumn))
        columnFilters = try container.decodeIfPresent(ColumnFilterState.self, forKey: .columnFilters) ?? ColumnFilterState()
    }
}
