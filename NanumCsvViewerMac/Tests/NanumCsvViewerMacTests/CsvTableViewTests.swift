import AppKit
import XCTest
@testable import NanumCsvViewerMac

final class CsvTableViewTests: XCTestCase {
    func testTrailingBodyFillerContinuesHorizontalGridLines() throws {
        let result = renderTableWithTrailingFiller()
        XCTAssertEqual(result.rowCount, 3)
        XCTAssertGreaterThan(result.boundsWidth, 300)
        XCTAssertEqual(result.columnWidth, 150, accuracy: 0.5)
        let trailingGridPixels = countBrightPixels(
            in: result.image,
            xRange: 180..<300,
            yRange: 0..<90
        )

        XCTAssertGreaterThan(trailingGridPixels, 120)
    }

    private func renderTableWithTrailingFiller() -> (image: NSBitmapImageRep, rowCount: Int, boundsWidth: CGFloat, columnWidth: CGFloat) {
        var rowCount = 0
        var boundsWidth = CGFloat(0)
        var columnWidth = CGFloat(0)
        let image = renderBitmap(width: 320, height: 90) {
            let tableView = CsvTableView(frame: NSRect(x: 0, y: 0, width: 320, height: 90))
            tableView.headerView = nil
            tableView.rowHeight = 28
            tableView.intercellSpacing = NSSize(width: 0, height: 0)
            tableView.usesAlternatingRowBackgroundColors = true
            tableView.gridStyleMask = [.solidHorizontalGridLineMask]
            tableView.gridColor = NSColor(calibratedWhite: 0.55, alpha: 1)
            tableView.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1)
            tableView.columnAutoresizingStyle = .noColumnAutoresizing

            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c0"))
            column.width = 150
            tableView.addTableColumn(column)
            tableView.setFrameSize(NSSize(width: 320, height: 90))
            tableView.setBoundsSize(NSSize(width: 320, height: 90))

            let dataSource = FixedRowsTableDataSource()
            tableView.dataSource = dataSource
            tableView.reloadData()
            tableView.noteNumberOfRowsChanged()
            tableView.layoutSubtreeIfNeeded()
            rowCount = tableView.numberOfRows
            boundsWidth = tableView.bounds.width
            columnWidth = column.width
            tableView.draw(tableView.bounds)
            _ = dataSource
        }
        return (image, rowCount, boundsWidth, columnWidth)
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

    private func countBrightPixels(in image: NSBitmapImageRep, xRange: Range<Int>, yRange: Range<Int>) -> Int {
        var count = 0
        for y in yRange {
            for x in xRange {
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.alphaComponent > 0.1 &&
                    (color.redComponent > 0.3 || color.greenComponent > 0.3 || color.blueComponent > 0.3) {
                    count += 1
                }
            }
        }
        return count
    }
}

private final class FixedRowsTableDataSource: NSObject, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        3
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        "row \(row)"
    }
}
