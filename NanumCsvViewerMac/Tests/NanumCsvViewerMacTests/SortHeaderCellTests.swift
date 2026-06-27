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

    private func renderHeaderCell(title: String, type: String, width: Int, height: Int) -> NSBitmapImageRep {
        renderBitmap(width: width, height: height) {
            let frame = NSRect(x: 0, y: 0, width: width, height: height)
            let view = NSView(frame: frame)
            let cell = SortHeaderCell(textCell: title)
            cell.typeText = type
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
            column.headerCell = cell
            tableView.addTableColumn(column)

            headerView.draw(headerView.bounds)
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
