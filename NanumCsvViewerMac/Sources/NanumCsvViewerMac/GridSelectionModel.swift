import Foundation

struct GridCellCoordinate: Hashable, Equatable {
    let row: Int
    let column: Int
}

struct ClosedRangeGrid: Equatable {
    let rows: ClosedRange<Int>
    let columns: ClosedRange<Int>
}

struct GridSelectionModel: Equatable {
    private(set) var selectedCells: Set<GridCellCoordinate> = []
    private(set) var anchor: GridCellCoordinate?

    init() {}

    init(selectedCells: Set<GridCellCoordinate>, anchor: GridCellCoordinate? = nil) {
        self.selectedCells = selectedCells.filter { $0.row >= 0 && $0.column >= 0 }
        self.anchor = anchor ?? self.selectedCells.sortedForGrid.first
    }

    var isEmpty: Bool {
        selectedCells.isEmpty
    }

    var selectedRows: IndexSet {
        IndexSet(selectedCells.map(\.row))
    }

    var selectedColumns: IndexSet {
        IndexSet(selectedCells.map(\.column))
    }

    mutating func replace(with cell: GridCellCoordinate) {
        guard isValid(cell) else { return }
        selectedCells = [cell]
        anchor = cell
    }

    mutating func replace(with range: ClosedRangeGrid) {
        selectedCells = Self.cells(in: range)
        anchor = GridCellCoordinate(row: range.rows.lowerBound, column: range.columns.lowerBound)
    }

    mutating func toggle(_ cell: GridCellCoordinate) {
        guard isValid(cell) else { return }
        if selectedCells.contains(cell) {
            selectedCells.remove(cell)
            if anchor == cell {
                anchor = selectedCells.sortedForGrid.first
            }
        } else {
            selectedCells.insert(cell)
            anchor = anchor ?? cell
        }
    }

    mutating func extend(to cell: GridCellCoordinate) {
        guard isValid(cell) else { return }
        let start = anchor ?? cell
        let range = ClosedRangeGrid(
            rows: min(start.row, cell.row)...max(start.row, cell.row),
            columns: min(start.column, cell.column)...max(start.column, cell.column)
        )
        selectedCells = Self.cells(in: range)
        anchor = start
    }

    mutating func clear() {
        selectedCells.removeAll()
        anchor = nil
    }

    func contains(row: Int, column: Int) -> Bool {
        selectedCells.contains(GridCellCoordinate(row: row, column: column))
    }

    func boundingRect() -> ClosedRangeGrid? {
        guard let first = selectedCells.first else { return nil }
        var minRow = first.row
        var maxRow = first.row
        var minColumn = first.column
        var maxColumn = first.column
        for cell in selectedCells {
            minRow = min(minRow, cell.row)
            maxRow = max(maxRow, cell.row)
            minColumn = min(minColumn, cell.column)
            maxColumn = max(maxColumn, cell.column)
        }
        return ClosedRangeGrid(rows: minRow...maxRow, columns: minColumn...maxColumn)
    }

    private func isValid(_ cell: GridCellCoordinate) -> Bool {
        cell.row >= 0 && cell.column >= 0
    }

    private static func cells(in range: ClosedRangeGrid) -> Set<GridCellCoordinate> {
        var cells: Set<GridCellCoordinate> = []
        for row in range.rows {
            for column in range.columns {
                cells.insert(GridCellCoordinate(row: row, column: column))
            }
        }
        return cells
    }
}

private extension Set where Element == GridCellCoordinate {
    var sortedForGrid: [GridCellCoordinate] {
        sorted {
            if $0.row != $1.row { return $0.row < $1.row }
            return $0.column < $1.column
        }
    }
}
