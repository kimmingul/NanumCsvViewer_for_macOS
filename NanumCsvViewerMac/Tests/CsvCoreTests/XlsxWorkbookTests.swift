import Compression
import Foundation
import XCTest
@testable import CsvCore

final class XlsxWorkbookTests: XCTestCase {
    func testSheetNamesReadsWorkbookOrder() throws {
        let path = try writeFixtureXlsx(sheets: [
            ("Sales", sheetXml(rows: [["A", "B"], ["1", "2"]])),
            ("두번째", sheetXml(rows: [["X"]]))
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }

        XCTAssertTrue(XlsxWorkbook.isXlsxFile(path: path))
        XCTAssertTrue(XlsxWorkbook.hasXlsxExtension(path))
        XCTAssertEqual(try XlsxWorkbook.sheetNames(path: path), ["Sales", "두번째"])
    }

    func testExportSheetWritesCsvWithSharedStringsAndNumbers() throws {
        let shared = ["name", "amount", "Alice, \"the\" first", "Bob"]
        let sheet = """
        <?xml version="1.0" encoding="UTF-8"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <sheetData>
        <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>
        <row r="2"><c r="A2" t="s"><v>2</v></c><c r="B2"><v>12.5</v></c></row>
        <row r="3"><c r="A3" t="s"><v>3</v></c><c r="B3"><v>7</v></c></row>
        </sheetData>
        </worksheet>
        """
        let path = try writeFixtureXlsx(sheets: [("Data", sheet)], sharedStrings: shared)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let destination = temporaryUrl(ext: "csv")
        defer { try? FileManager.default.removeItem(at: destination) }
        let rows = try XlsxWorkbook.exportSheetToCsv(path: path, sheet: "Data", destination: destination)

        XCTAssertEqual(rows, 3)
        let csv = try String(contentsOf: destination, encoding: .utf8)
        XCTAssertEqual(csv, """
        name,amount
        "Alice, ""the"" first",12.5
        Bob,7

        """)
    }

    func testExportHandlesGapsInlineStringsAndBooleans() throws {
        let sheet = """
        <?xml version="1.0" encoding="UTF-8"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <sheetData>
        <row r="1"><c r="A1" t="inlineStr"><is><t>a</t></is></c><c r="C1" t="inlineStr"><is><t>c</t></is></c></row>
        <row r="3"><c r="B3" t="b"><v>1</v></c></row>
        </sheetData>
        </worksheet>
        """
        let path = try writeFixtureXlsx(sheets: [("S", sheet)])
        defer { try? FileManager.default.removeItem(atPath: path) }

        let destination = temporaryUrl(ext: "csv")
        defer { try? FileManager.default.removeItem(at: destination) }
        _ = try XlsxWorkbook.exportSheetToCsv(path: path, sheet: "S", destination: destination)

        let csv = try String(contentsOf: destination, encoding: .utf8)
        XCTAssertEqual(csv, """
        a,,c
        ,,
        ,TRUE,

        """, "column gaps and skipped rows keep their positions")
    }

    func testExportConvertsDateStyledSerials() throws {
        let styles = """
        <?xml version="1.0" encoding="UTF-8"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <cellXfs count="2">
        <xf numFmtId="0"/>
        <xf numFmtId="14"/>
        </cellXfs>
        </styleSheet>
        """
        let sheet = """
        <?xml version="1.0" encoding="UTF-8"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <sheetData>
        <row r="1"><c r="A1" t="inlineStr"><is><t>date</t></is></c></row>
        <row r="2"><c r="A2" s="1"><v>45292</v></c></row>
        <row r="3"><c r="A3"><v>45292</v></c></row>
        </sheetData>
        </worksheet>
        """
        let path = try writeFixtureXlsx(sheets: [("D", sheet)], stylesXml: styles)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let destination = temporaryUrl(ext: "csv")
        defer { try? FileManager.default.removeItem(at: destination) }
        _ = try XlsxWorkbook.exportSheetToCsv(path: path, sheet: "D", destination: destination)

        let csv = try String(contentsOf: destination, encoding: .utf8)
        let lines = csv.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines[1], "2024-01-01", "serial 45292 with date style renders as ISO date")
        XCTAssertEqual(lines[2], "45292", "the same serial without a date style stays numeric")
    }

    func testUnknownSheetThrows() throws {
        let path = try writeFixtureXlsx(sheets: [("Only", sheetXml(rows: [["x"]]))])
        defer { try? FileManager.default.removeItem(atPath: path) }

        XCTAssertThrowsError(
            try XlsxWorkbook.exportSheetToCsv(path: path, sheet: "Nope", destination: temporaryUrl(ext: "csv"))
        )
    }

    func testDeflatedEntriesAreSupported() throws {
        let path = try writeFixtureXlsx(sheets: [("Z", sheetXml(rows: [["hello", "world"], ["1", "2"]]))], compress: true)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let destination = temporaryUrl(ext: "csv")
        defer { try? FileManager.default.removeItem(at: destination) }
        _ = try XlsxWorkbook.exportSheetToCsv(path: path, sheet: "Z", destination: destination)

        let csv = try String(contentsOf: destination, encoding: .utf8)
        XCTAssertTrue(csv.hasPrefix("hello,world\n"))
    }

    func testExcelDateEpochEdges() {
        // 1900 system: epoch 1899-12-30 absorbs the phantom Feb 29, 1900.
        XCTAssertEqual(XlsxWorkbook.dateString(fromSerial: 1, date1904: false), "1899-12-31")
        XCTAssertEqual(XlsxWorkbook.dateString(fromSerial: 60, date1904: false), "1900-02-28")
        XCTAssertEqual(XlsxWorkbook.dateString(fromSerial: 61, date1904: false), "1900-03-01")
        XCTAssertEqual(XlsxWorkbook.dateString(fromSerial: 45292, date1904: false), "2024-01-01")
        XCTAssertEqual(
            XlsxWorkbook.dateString(fromSerial: 45292.5, date1904: false),
            "2024-01-01 12:00:00",
            "fractional serials carry the time of day"
        )
        // 1904 system starts at 1904-01-01.
        XCTAssertEqual(XlsxWorkbook.dateString(fromSerial: 0, date1904: true), "1904-01-01")
        XCTAssertEqual(XlsxWorkbook.dateString(fromSerial: 1, date1904: true), "1904-01-02")
    }

    func testZipRejectsAbsurdEntryClaims() throws {
        // Corrupt a valid archive's central directory to claim a multi-GB
        // uncompressed size for the workbook entry.
        let path = try writeFixtureXlsx(sheets: [("S", sheetXml(rows: [["x"]]))])
        defer { try? FileManager.default.removeItem(atPath: path) }
        var bytes = try Data(contentsOf: URL(fileURLWithPath: path))

        let signature: [UInt8] = [0x50, 0x4B, 0x01, 0x02]
        guard let headerIndex = bytes.firstRange(of: Data(signature))?.lowerBound else {
            return XCTFail("central directory not found")
        }
        let sizeOffset = headerIndex + 24
        let huge = UInt32(2_000_000_000)
        withUnsafeBytes(of: huge.littleEndian) { buffer in
            bytes.replaceSubrange(sizeOffset..<(sizeOffset + 4), with: buffer)
        }
        let corruptedPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("corrupt-\(UUID().uuidString).xlsx")
        try bytes.write(to: URL(fileURLWithPath: corruptedPath))
        defer { try? FileManager.default.removeItem(atPath: corruptedPath) }

        XCTAssertThrowsError(try XlsxWorkbook.sheetNames(path: corruptedPath))
    }

    // MARK: - Fixture construction

    private func sheetXml(rows: [[String]]) -> String {
        var body = ""
        for (rowIndex, row) in rows.enumerated() {
            body += "<row r=\"\(rowIndex + 1)\">"
            for (columnIndex, value) in row.enumerated() {
                let reference = "\(columnLetters(columnIndex))\(rowIndex + 1)"
                let escaped = value
                    .replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                if Double(value) != nil {
                    body += "<c r=\"\(reference)\"><v>\(escaped)</v></c>"
                } else {
                    body += "<c r=\"\(reference)\" t=\"inlineStr\"><is><t>\(escaped)</t></is></c>"
                }
            }
            body += "</row>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <sheetData>\(body)</sheetData>
        </worksheet>
        """
    }

    private func columnLetters(_ index: Int) -> String {
        var result = ""
        var value = index
        repeat {
            result = String(UnicodeScalar(UInt8(65 + value % 26))) + result
            value = value / 26 - 1
        } while value >= 0
        return result
    }

    private func writeFixtureXlsx(
        sheets: [(name: String, xml: String)],
        sharedStrings: [String]? = nil,
        stylesXml: String? = nil,
        compress: Bool = false
    ) throws -> String {
        var sheetEntries = ""
        var relEntries = ""
        for (index, sheet) in sheets.enumerated() {
            let escapedName = sheet.name
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;")
            sheetEntries += "<sheet name=\"\(escapedName)\" sheetId=\"\(index + 1)\" r:id=\"rId\(index + 1)\"/>"
            relEntries += "<Relationship Id=\"rId\(index + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(index + 1).xml\"/>"
        }
        let workbook = """
        <?xml version="1.0" encoding="UTF-8"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets>\(sheetEntries)</sheets>
        </workbook>
        """
        let rels = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(relEntries)</Relationships>
        """

        var entries: [(String, Data)] = [
            ("xl/workbook.xml", Data(workbook.utf8)),
            ("xl/_rels/workbook.xml.rels", Data(rels.utf8))
        ]
        for (index, sheet) in sheets.enumerated() {
            entries.append(("xl/worksheets/sheet\(index + 1).xml", Data(sheet.xml.utf8)))
        }
        if let sharedStrings {
            let items = sharedStrings.map { value -> String in
                let escaped = value
                    .replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                return "<si><t xml:space=\"preserve\">\(escaped)</t></si>"
            }.joined()
            let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="\(sharedStrings.count)" uniqueCount="\(sharedStrings.count)">\(items)</sst>
            """
            entries.append(("xl/sharedStrings.xml", Data(xml.utf8)))
        }
        if let stylesXml {
            entries.append(("xl/styles.xml", Data(stylesXml.utf8)))
        }

        let data = Self.makeZip(entries: entries, compress: compress)
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("fixture-\(UUID().uuidString).xlsx")
        try data.write(to: URL(fileURLWithPath: path))
        return path
    }

    private func temporaryUrl(ext: String) -> URL {
        URL(fileURLWithPath: (NSTemporaryDirectory() as NSString).appendingPathComponent("xlsx-out-\(UUID().uuidString).\(ext)"))
    }

    // Minimal ZIP writer: stored entries by default, raw-deflate when compressing.
    private static func makeZip(entries: [(name: String, data: Data)], compress: Bool) -> Data {
        var archive = Data()
        var centralDirectory = Data()
        var entryCount: UInt16 = 0

        func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }

        for entry in entries {
            let nameBytes = Data(entry.name.utf8)
            let crc = crc32(entry.data)
            let payload: Data
            let method: UInt16
            if compress, let deflated = rawDeflate(entry.data), deflated.count < entry.data.count {
                payload = deflated
                method = 8
            } else {
                payload = entry.data
                method = 0
            }

            let localHeaderOffset = UInt32(archive.count)
            append(UInt32(0x04034b50), to: &archive)
            append(UInt16(20), to: &archive)
            append(UInt16(0), to: &archive)
            append(method, to: &archive)
            append(UInt16(0), to: &archive)
            append(UInt16(0), to: &archive)
            append(crc, to: &archive)
            append(UInt32(payload.count), to: &archive)
            append(UInt32(entry.data.count), to: &archive)
            append(UInt16(nameBytes.count), to: &archive)
            append(UInt16(0), to: &archive)
            archive.append(nameBytes)
            archive.append(payload)

            append(UInt32(0x02014b50), to: &centralDirectory)
            append(UInt16(20), to: &centralDirectory)
            append(UInt16(20), to: &centralDirectory)
            append(UInt16(0), to: &centralDirectory)
            append(method, to: &centralDirectory)
            append(UInt16(0), to: &centralDirectory)
            append(UInt16(0), to: &centralDirectory)
            append(crc, to: &centralDirectory)
            append(UInt32(payload.count), to: &centralDirectory)
            append(UInt32(entry.data.count), to: &centralDirectory)
            append(UInt16(nameBytes.count), to: &centralDirectory)
            append(UInt16(0), to: &centralDirectory)
            append(UInt16(0), to: &centralDirectory)
            append(UInt16(0), to: &centralDirectory)
            append(UInt16(0), to: &centralDirectory)
            append(UInt32(0), to: &centralDirectory)
            append(localHeaderOffset, to: &centralDirectory)
            centralDirectory.append(nameBytes)
            entryCount += 1
        }

        let centralOffset = UInt32(archive.count)
        archive.append(centralDirectory)
        append(UInt32(0x06054b50), to: &archive)
        append(UInt16(0), to: &archive)
        append(UInt16(0), to: &archive)
        append(entryCount, to: &archive)
        append(entryCount, to: &archive)
        append(UInt32(centralDirectory.count), to: &archive)
        append(centralOffset, to: &archive)
        append(UInt16(0), to: &archive)
        return archive
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for index in 0..<256 {
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) != 0 ? (0xEDB88320 ^ (value >> 1)) : (value >> 1)
            }
            table[index] = value
        }
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    private static func rawDeflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let destinationCapacity = data.count + 1024
        var destination = Data(count: destinationCapacity)
        let written = destination.withUnsafeMutableBytes { destinationBuffer -> Int in
            data.withUnsafeBytes { sourceBuffer in
                compression_encode_buffer(
                    destinationBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    destinationCapacity,
                    sourceBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { return nil }
        destination.removeSubrange(written..<destinationCapacity)
        return destination
    }
}
