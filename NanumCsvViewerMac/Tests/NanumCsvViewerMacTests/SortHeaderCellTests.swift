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

    private func renderHeaderCell(title: String, type: String, width: Int, height: Int) -> NSBitmapImageRep {
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

            let view = NSView(frame: frame)
            let cell = SortHeaderCell(textCell: title)
            cell.typeText = type
            cell.draw(withFrame: frame, in: view)
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
