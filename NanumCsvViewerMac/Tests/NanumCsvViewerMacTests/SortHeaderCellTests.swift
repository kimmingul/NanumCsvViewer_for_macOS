import AppKit
import XCTest
@testable import NanumCsvViewerMac

final class SortHeaderCellTests: XCTestCase {
    func testTypeBadgeRendersNextToHeaderTitle() throws {
        let image = renderHeaderCell(title: "visit_date", type: "Date", width: 150, height: 28)
        let adjacentTypeAreaPixels = countVisiblePixels(
            in: image,
            xRange: 76..<112,
            yRange: 4..<24
        )

        XCTAssertGreaterThan(adjacentTypeAreaPixels, 40)
    }

    func testTypeBadgeDoesNotRenderInTrailingHeaderFillerArea() throws {
        let image = renderHeaderFillerArea()
        let fillerPixels = countVisiblePixels(
            in: image,
            xRange: 150..<300,
            yRange: 4..<24
        )

        XCTAssertLessThan(fillerPixels, 20)
    }

    func testHeaderViewDoesNotRepeatLastColumnHeaderInTrailingFillerArea() throws {
        let image = renderHeaderViewWithTrailingFiller()
        let fillerPixels = countVisiblePixels(
            in: image,
            xRange: 150..<300,
            yRange: 4..<24
        )

        XCTAssertLessThan(fillerPixels, 20)
    }

    func testHeaderCellStillDrawsTitleBeforeHeaderViewIsSized() throws {
        let image = renderUnsizedHeaderCell()
        let titlePixels = countVisiblePixels(
            in: image,
            xRange: 6..<72,
            yRange: 4..<24
        )

        XCTAssertGreaterThan(titlePixels, 20)
    }

    func testFilterIndicatorRendersNearHeaderContent() throws {
        let image = renderHeaderCell(title: "site", type: "Categorical", width: 160, height: 28, filterAvailable: true, filterActive: true)
        let filterPixels = countVisiblePixels(
            in: image,
            xRange: 96..<128,
            yRange: 5..<23
        )

        XCTAssertGreaterThan(filterPixels, 20)
    }

    func testFilterButtonFrameHitsIndicatorAreaOnly() throws {
        let cell = SortHeaderCell(textCell: "site")
        cell.filterAvailable = true
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 160, height: 28))
        let frame = try XCTUnwrap(cell.filterButtonFrame(withFrame: view.bounds, in: view))

        XCTAssertTrue(frame.contains(NSPoint(x: 40, y: 14)))
        XCTAssertFalse(frame.contains(NSPoint(x: 145, y: 14)))
        XCTAssertFalse(frame.contains(NSPoint(x: 20, y: 14)))
    }

    func testFilterButtonFrameStaysNearHeaderContentWhenColumnIsWide() throws {
        let cell = SortHeaderCell(textCell: "주소")
        cell.titleText = "주소"
        cell.typeText = "Categorical"
        cell.filterAvailable = true
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 28))

        let frame = try XCTUnwrap(cell.filterButtonFrame(withFrame: view.bounds, in: view))

        XCTAssertLessThan(frame.minX, 140)
        XCTAssertFalse(frame.contains(NSPoint(x: 400, y: 14)))
    }

    func testHeaderViewMapsFilterIndicatorHitToDataColumn() throws {
        let tableView = NSTableView(frame: NSRect(x: 0, y: 0, width: 240, height: 28))
        let headerView = CsvTableHeaderView(frame: tableView.bounds)
        tableView.headerView = headerView

        let rowNumber = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("rowNumber"))
        rowNumber.width = 60
        tableView.addTableColumn(rowNumber)

        let dataColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c0"))
        dataColumn.width = 160
        let cell = SortHeaderCell(textCell: "site")
        cell.filterAvailable = true
        dataColumn.headerCell = cell
        tableView.addTableColumn(dataColumn)

        let filterFrame = try XCTUnwrap(cell.filterButtonFrame(
            withFrame: headerView.headerRect(ofColumn: 1),
            in: headerView
        ))
        let hit = try XCTUnwrap(headerView.filterHit(at: NSPoint(x: filterFrame.midX, y: filterFrame.midY)))

        XCTAssertEqual(hit.dataColumn, 0)
        XCTAssertFalse(headerView.filterHit(at: NSPoint(x: 90, y: 14)) != nil)
    }

    func testHeaderCellCopyPreservesSwiftDrawingState() throws {
        let copy: SortHeaderCell = try autoreleasepool {
            let cell = SortHeaderCell(textCell: "visit_date")
            cell.titleText = "검사일자"
            cell.typeText = "Date"
            cell.columnIdentifierRawValue = "c0"
            cell.sortPriority = 2
            cell.ascending = false
            cell.filterAvailable = true
            cell.filterActive = true

            return try XCTUnwrap(cell.copy() as? SortHeaderCell)
        }

        XCTAssertEqual(copy.stringValue, "visit_date")
        XCTAssertEqual(copy.titleText, "검사일자")
        XCTAssertEqual(copy.typeText, "Date")
        XCTAssertEqual(copy.columnIdentifierRawValue, "c0")
        XCTAssertEqual(copy.sortPriority, 2)
        XCTAssertEqual(copy.ascending, false)
        XCTAssertEqual(copy.filterAvailable, true)
        XCTAssertEqual(copy.filterActive, true)

        let image = renderHeaderCell(copy, width: 180, height: 28)
        XCTAssertGreaterThan(countVisiblePixels(in: image, xRange: 6..<170, yRange: 4..<24), 20)
    }

    func testCopiedHeaderCellDoesNotDrawInTrailingOverflowArea() throws {
        let image = renderCopiedHeaderCellInTrailingFiller()
        let fillerPixels = countVisiblePixels(
            in: image,
            xRange: 150..<300,
            yRange: 4..<24
        )

        XCTAssertLessThan(fillerPixels, 20)
    }

    private func renderHeaderCell(
        title: String,
        type: String,
        width: Int,
        height: Int,
        filterAvailable: Bool = false,
        filterActive: Bool = false
    ) -> NSBitmapImageRep {
        renderBitmap(width: width, height: height) {
            let frame = NSRect(x: 0, y: 0, width: width, height: height)
            let view = NSView(frame: frame)
            let cell = SortHeaderCell(textCell: title)
            cell.typeText = type
            cell.filterAvailable = filterAvailable
            cell.filterActive = filterActive
            cell.draw(withFrame: frame, in: view)
        }
    }

    private func renderHeaderCell(_ cell: SortHeaderCell, width: Int, height: Int) -> NSBitmapImageRep {
        renderBitmap(width: width, height: height) {
            let frame = NSRect(x: 0, y: 0, width: width, height: height)
            let view = NSView(frame: frame)
            cell.draw(withFrame: frame, in: view)
        }
    }

    private func renderHeaderFillerArea() -> NSBitmapImageRep {
        renderBitmap(width: 300, height: 28) {
            let tableView = NSTableView(frame: NSRect(x: 0, y: 0, width: 300, height: 28))
            let headerView = NSTableHeaderView(frame: tableView.bounds)
            tableView.headerView = headerView

            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c0"))
            column.width = 150
            let cell = SortHeaderCell(textCell: "주소 [Categorical]")
            cell.titleText = "주소"
            cell.typeText = "Categorical"
            cell.columnIdentifierRawValue = column.identifier.rawValue
            column.headerCell = cell
            tableView.addTableColumn(column)

            cell.drawInterior(withFrame: NSRect(x: 150, y: 0, width: 150, height: 28), in: headerView)
        }
    }

    private func renderHeaderViewWithTrailingFiller() -> NSBitmapImageRep {
        renderBitmap(width: 300, height: 28) {
            let tableView = NSTableView(frame: NSRect(x: 0, y: 0, width: 300, height: 28))
            let headerView = CsvTableHeaderView(frame: tableView.bounds)
            tableView.headerView = headerView

            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c0"))
            column.width = 150
            let cell = SortHeaderCell(textCell: "주소 [Categorical]")
            cell.titleText = "주소"
            cell.typeText = "Categorical"
            cell.columnIdentifierRawValue = column.identifier.rawValue
            column.headerCell = cell
            tableView.addTableColumn(column)

            headerView.draw(headerView.bounds)
        }
    }

    private func renderUnsizedHeaderCell() -> NSBitmapImageRep {
        renderBitmap(width: 150, height: 28) {
            let tableView = NSTableView(frame: .zero)
            let headerView = CsvTableHeaderView(frame: .zero)
            tableView.headerView = headerView

            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c0"))
            column.width = 150
            let cell = SortHeaderCell(textCell: "주소")
            cell.titleText = "주소"
            cell.columnIdentifierRawValue = column.identifier.rawValue
            column.headerCell = cell
            tableView.addTableColumn(column)

            cell.drawInterior(withFrame: NSRect(x: 0, y: 0, width: 150, height: 28), in: headerView)
        }
    }

    private func renderCopiedHeaderCellInTrailingFiller() -> NSBitmapImageRep {
        renderBitmap(width: 300, height: 28) {
            let tableView = NSTableView(frame: NSRect(x: 0, y: 0, width: 300, height: 28))
            let headerView = CsvTableHeaderView(frame: tableView.bounds)
            tableView.headerView = headerView

            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c0"))
            column.width = 150
            let cell = SortHeaderCell(textCell: "주소 [Categorical]")
            cell.titleText = "주소"
            cell.typeText = "Categorical"
            cell.columnIdentifierRawValue = column.identifier.rawValue
            column.headerCell = cell
            tableView.addTableColumn(column)

            let copiedCell = cell.copy() as! SortHeaderCell
            copiedCell.drawInterior(withFrame: NSRect(x: 150, y: 0, width: 150, height: 28), in: headerView)
        }
    }

    private func renderBitmap(width: Int, height: Int, drawContent: @escaping () -> Void) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        let previousContext = NSGraphicsContext.current
        NSGraphicsContext.current = context
        defer {
            NSGraphicsContext.current = previousContext
        }

        let draw = {
            let frame = NSRect(x: 0, y: 0, width: width, height: height)
            NSColor.black.setFill()
            frame.fill()
            drawContent()
        }
        if let appearance = NSAppearance(named: .darkAqua) {
            appearance.performAsCurrentDrawingAppearance(draw)
        } else {
            draw()
        }
        return rep
    }

    private func countVisiblePixels(in image: NSBitmapImageRep, xRange: Range<Int>, yRange: Range<Int>) -> Int {
        var count = 0
        for y in yRange {
            for x in xRange {
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.alphaComponent > 0.1 &&
                    (color.redComponent > 0.18 || color.greenComponent > 0.18 || color.blueComponent > 0.18) {
                    count += 1
                }
            }
        }
        return count
    }
}
