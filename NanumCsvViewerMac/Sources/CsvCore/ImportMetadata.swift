import Foundation

public struct ImportMetadata: Codable, Equatable, Sendable {
    public struct Column: Codable, Equatable, Sendable {
        public let name: String
        public let label: String?
        public let declaredType: DeclaredType?
        public let valueLabels: [String: String]

        public init(name: String, label: String? = nil, declaredType: DeclaredType? = nil, valueLabels: [String: String] = [:]) {
            self.name = name
            self.label = label
            self.declaredType = declaredType
            self.valueLabels = valueLabels
        }
    }

    public struct Warning: Codable, Equatable, Sendable {
        public let code: String
        public let message: String

        public init(code: String, message: String) {
            self.code = code
            self.message = message
        }
    }

    public enum DeclaredType: String, Codable, Equatable, Sendable {
        case string
        case integer
        case float
        case date
        case boolean
        case categorical
        case ordinal
        case currency
        case percent
        case scientific

        public var columnValueType: ColumnValueType {
            switch self {
            case .string:
                return .string
            case .integer:
                return .integer
            case .float, .currency, .percent, .scientific:
                return .float
            case .date:
                return .date
            case .boolean:
                return .boolean
            case .categorical, .ordinal:
                return .categorical
            }
        }
    }

    public let columns: [Column]
    public let rowCount: Int64
    public let encoding: String?
    public let warnings: [Warning]

    public init(columns: [Column], rowCount: Int64, encoding: String? = nil, warnings: [Warning] = []) {
        self.columns = columns
        self.rowCount = rowCount
        self.encoding = encoding
        self.warnings = warnings
    }

    public func columnTypeOverrides() -> [Int: ColumnValueType] {
        var overrides: [Int: ColumnValueType] = [:]
        for (index, column) in columns.enumerated() {
            if let declaredType = column.declaredType {
                overrides[index] = declaredType.columnValueType
            }
        }
        return overrides
    }

    public func displayValue(rawValue: String, columnIndex: Int) -> String {
        guard columns.indices.contains(columnIndex) else { return rawValue }
        return columns[columnIndex].valueLabels[rawValue] ?? rawValue
    }
}
