import Foundation
import SQLite3
import XCTest
@testable import ImportService
import ImportServiceProtocol

/// Exercises the XLSX / SQLite handlers through the real `ImportService` entry
/// points — the same path an XPC call takes — proving source materialization,
/// limit enforcement, and error mapping across the isolation boundary.
final class WorkbookImporterTests: XCTestCase {
    private let generousLimits = ImportLimits(
        maxBytes: 8 * 1024 * 1024, maxRows: 1_000_000, maxColumns: 16_384, maxCells: 10_000_000, timeoutSeconds: 10
    )

    // MARK: - XLSX

    func testServiceImportsXlsxSheet() throws {
        let source = try openHandle(makeXlsx(rows: [["a", "b"], ["1", "2"], ["3", "4"]]))
        defer { try? source.close() }
        let (output, outputURL, dir) = try makeOutput()
        defer { try? output.close(); try? FileManager.default.removeItem(at: dir) }

        let reply = expectation(description: "import")
        ImportService().importFile(
            sourceFile: ImportFileReference(fileHandle: source),
            kind: .xlsx,
            limits: generousLimits,
            outputFile: ImportFileReference(fileHandle: output),
            metadataFile: nil,
            outputURL: outputURL
        ) { result, error in
            XCTAssertNil(error)
            XCTAssertEqual(result?.rowCount, 3)
            reply.fulfill()
        }
        wait(for: [reply], timeout: 5)
        XCTAssertEqual(try String(contentsOf: outputURL, encoding: .utf8), "a,b\n1,2\n3,4\n")
    }

    func testServiceInspectsXlsxSheetNames() throws {
        let source = try openHandle(makeXlsx(rows: [["x"]], sheetName: "First"))
        defer { try? source.close() }

        let reply = expectation(description: "inspect")
        ImportService().inspectFile(
            sourceFile: ImportFileReference(fileHandle: source),
            kind: .xlsx,
            limits: generousLimits
        ) { inspection, error in
            XCTAssertNil(error)
            XCTAssertEqual(inspection?.sheetNames, ["First"])
            reply.fulfill()
        }
        wait(for: [reply], timeout: 5)
    }

    func testServiceEnforcesXlsxRowLimit() throws {
        let source = try openHandle(makeXlsx(rows: [["a"], ["1"], ["2"], ["3"]]))
        defer { try? source.close() }
        let (output, outputURL, dir) = try makeOutput()
        defer { try? output.close(); try? FileManager.default.removeItem(at: dir) }

        let limits = ImportLimits(maxBytes: 8 * 1024 * 1024, maxRows: 2, maxColumns: 16_384, maxCells: 10_000_000, timeoutSeconds: 10)
        let reply = expectation(description: "import")
        ImportService().importFile(
            sourceFile: ImportFileReference(fileHandle: source),
            kind: .xlsx,
            limits: limits,
            outputFile: ImportFileReference(fileHandle: output),
            metadataFile: nil,
            outputURL: outputURL
        ) { result, error in
            XCTAssertNil(result)
            XCTAssertEqual(error?.code, "maxRowsExceeded")
            reply.fulfill()
        }
        wait(for: [reply], timeout: 5)
    }

    func testServiceEnforcesXlsxByteLimit() throws {
        let source = try openHandle(makeXlsx(rows: [["a", "b"], ["1", "2"]]))
        defer { try? source.close() }
        let (output, outputURL, dir) = try makeOutput()
        defer { try? output.close(); try? FileManager.default.removeItem(at: dir) }

        let limits = ImportLimits(maxBytes: 32, maxRows: 1_000, maxColumns: 16_384, maxCells: 10_000, timeoutSeconds: 10)
        let reply = expectation(description: "import")
        ImportService().importFile(
            sourceFile: ImportFileReference(fileHandle: source),
            kind: .xlsx,
            limits: limits,
            outputFile: ImportFileReference(fileHandle: output),
            metadataFile: nil,
            outputURL: outputURL
        ) { result, error in
            XCTAssertNil(result)
            XCTAssertEqual(error?.code, "maxBytesExceeded")
            reply.fulfill()
        }
        wait(for: [reply], timeout: 5)
    }

    // MARK: - SQLite

    func testServiceImportsSqliteTable() throws {
        let source = try openHandle(makeSqlite())
        defer { try? source.close() }
        let (output, outputURL, dir) = try makeOutput()
        defer { try? output.close(); try? FileManager.default.removeItem(at: dir) }

        let reply = expectation(description: "import")
        ImportService().importFile(
            sourceFile: ImportFileReference(fileHandle: source),
            kind: .sqliteTable("people"),
            limits: generousLimits,
            outputFile: ImportFileReference(fileHandle: output),
            metadataFile: nil,
            outputURL: outputURL
        ) { result, error in
            XCTAssertNil(error)
            XCTAssertEqual(result?.rowCount, 2)
            reply.fulfill()
        }
        wait(for: [reply], timeout: 5)
        let csv = try String(contentsOf: outputURL, encoding: .utf8)
        XCTAssertTrue(csv.hasPrefix("id,name\n"), csv)
    }

    func testServiceInspectsSqliteTableNames() throws {
        let source = try openHandle(makeSqlite())
        defer { try? source.close() }

        let reply = expectation(description: "inspect")
        ImportService().inspectFile(
            sourceFile: ImportFileReference(fileHandle: source),
            kind: .sqlite,
            limits: generousLimits
        ) { inspection, error in
            XCTAssertNil(error)
            XCTAssertEqual(inspection?.sheetNames, ["people"])
            reply.fulfill()
        }
        wait(for: [reply], timeout: 5)
    }

    func testServiceEnforcesSqliteRowLimit() throws {
        let source = try openHandle(makeSqlite())
        defer { try? source.close() }
        let (output, outputURL, dir) = try makeOutput()
        defer { try? output.close(); try? FileManager.default.removeItem(at: dir) }

        let limits = ImportLimits(maxBytes: 8 * 1024 * 1024, maxRows: 1, maxColumns: 16_384, maxCells: 10_000_000, timeoutSeconds: 10)
        let reply = expectation(description: "import")
        ImportService().importFile(
            sourceFile: ImportFileReference(fileHandle: source),
            kind: .sqliteTable("people"),
            limits: limits,
            outputFile: ImportFileReference(fileHandle: output),
            metadataFile: nil,
            outputURL: outputURL
        ) { result, error in
            XCTAssertNil(result)
            XCTAssertEqual(error?.code, "maxRowsExceeded")
            reply.fulfill()
        }
        wait(for: [reply], timeout: 5)
    }

    func testInspectedNamesAreCappedAgainstFlood() {
        let many = (0..<(WorkbookImporter.maxInspectedParts + 500)).map { "sheet\($0)" }
        XCTAssertEqual(WorkbookImporter.cappedNames(many).count, WorkbookImporter.maxInspectedParts)

        let few = ["a", "b", "c"]
        XCTAssertEqual(WorkbookImporter.cappedNames(few), few)
    }

    // MARK: - Fixtures

    private func makeOutput() throws -> (FileHandle, URL, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wb-out-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("import.csv")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return (try FileHandle(forWritingTo: url), url, dir)
    }

    private func openHandle(_ url: URL) throws -> FileHandle {
        try FileHandle(forReadingFrom: url)
    }

    private func makeSqlite() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wb-\(UUID().uuidString).db")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close_v2(db) }
        for sql in [
            "CREATE TABLE people (id INTEGER, name TEXT)",
            "INSERT INTO people VALUES (1, 'Alice')",
            "INSERT INTO people VALUES (2, 'Bob')"
        ] {
            XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK, sql)
        }
        return url
    }

    private func makeXlsx(rows: [[String]], sheetName: String = "Sheet1") throws -> URL {
        var body = ""
        for (r, row) in rows.enumerated() {
            body += "<row r=\"\(r + 1)\">"
            for (c, value) in row.enumerated() {
                let ref = "\(columnLetters(c))\(r + 1)"
                let escaped = value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                body += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t>\(escaped)</t></is></c>"
            }
            body += "</row>"
        }
        let sheet = """
        <?xml version="1.0" encoding="UTF-8"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>\(body)</sheetData></worksheet>
        """
        let workbook = """
        <?xml version="1.0" encoding="UTF-8"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets><sheet name="\(sheetName)" sheetId="1" r:id="rId1"/></sheets></workbook>
        """
        let rels = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>
        """
        let data = Self.makeStoredZip(entries: [
            ("xl/workbook.xml", Data(workbook.utf8)),
            ("xl/_rels/workbook.xml.rels", Data(rels.utf8)),
            ("xl/worksheets/sheet1.xml", Data(sheet.utf8))
        ])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wb-\(UUID().uuidString).xlsx")
        try data.write(to: url)
        return url
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

    // Minimal stored (uncompressed) ZIP writer.
    private static func makeStoredZip(entries: [(name: String, data: Data)]) -> Data {
        var archive = Data()
        var central = Data()
        var count: UInt16 = 0

        func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }

        for entry in entries {
            let nameBytes = Data(entry.name.utf8)
            let crc = crc32(entry.data)
            let localOffset = UInt32(archive.count)
            append(UInt32(0x04034b50), to: &archive)
            append(UInt16(20), to: &archive); append(UInt16(0), to: &archive)
            append(UInt16(0), to: &archive); append(UInt16(0), to: &archive); append(UInt16(0), to: &archive)
            append(crc, to: &archive)
            append(UInt32(entry.data.count), to: &archive); append(UInt32(entry.data.count), to: &archive)
            append(UInt16(nameBytes.count), to: &archive); append(UInt16(0), to: &archive)
            archive.append(nameBytes); archive.append(entry.data)

            append(UInt32(0x02014b50), to: &central)
            append(UInt16(20), to: &central); append(UInt16(20), to: &central)
            append(UInt16(0), to: &central); append(UInt16(0), to: &central)
            append(UInt16(0), to: &central); append(UInt16(0), to: &central)
            append(crc, to: &central)
            append(UInt32(entry.data.count), to: &central); append(UInt32(entry.data.count), to: &central)
            append(UInt16(nameBytes.count), to: &central)
            append(UInt16(0), to: &central); append(UInt16(0), to: &central); append(UInt16(0), to: &central); append(UInt16(0), to: &central)
            append(UInt32(0), to: &central); append(localOffset, to: &central)
            central.append(nameBytes)
            count += 1
        }

        let centralOffset = UInt32(archive.count)
        archive.append(central)
        append(UInt32(0x06054b50), to: &archive)
        append(UInt16(0), to: &archive); append(UInt16(0), to: &archive)
        append(count, to: &archive); append(count, to: &archive)
        append(UInt32(central.count), to: &archive); append(centralOffset, to: &archive)
        append(UInt16(0), to: &archive)
        return archive
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var value = UInt32(i)
            for _ in 0..<8 { value = (value & 1) != 0 ? (0xEDB88320 ^ (value >> 1)) : (value >> 1) }
            table[i] = value
        }
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFFFFFF
    }
}
