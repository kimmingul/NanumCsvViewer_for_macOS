import Foundation
import XCTest
@testable import NanumCsvViewerMac

final class DocumentOpenRoutingTests: XCTestCase {
    func testFirstSelectedUrlOpensInEmptyCurrentWindowAndRestOpenAsAdditionalDocuments() {
        let urls = [
            URL(fileURLWithPath: "/tmp/a.csv"),
            URL(fileURLWithPath: "/tmp/b.csv"),
            URL(fileURLWithPath: "/tmp/c.csv")
        ]

        let route = DocumentOpenRouting.route(urls: urls, currentWindowHasDocument: false)

        XCTAssertEqual(route.currentWindowURL, urls[0])
        XCTAssertEqual(route.additionalWindowURLs, Array(urls.dropFirst()))
    }

    func testAllSelectedUrlsOpenAsAdditionalDocumentsWhenCurrentWindowAlreadyHasDocument() {
        let urls = [
            URL(fileURLWithPath: "/tmp/a.csv"),
            URL(fileURLWithPath: "/tmp/b.csv")
        ]

        let route = DocumentOpenRouting.route(urls: urls, currentWindowHasDocument: true)

        XCTAssertNil(route.currentWindowURL)
        XCTAssertEqual(route.additionalWindowURLs, urls)
    }

    func testDetectsLegacyXlsByExtensionAndOleMagic() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("document-routing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let xlsURL = directory.appendingPathComponent("legacy.xls")
        try Data([0xD0, 0xCF, 0x11, 0xE0, 0x00]).write(to: xlsURL)
        let renamedURL = directory.appendingPathComponent("legacy.bin")
        try Data([0xD0, 0xCF, 0x11, 0xE0, 0x00]).write(to: renamedURL)
        let textURL = directory.appendingPathComponent("not-ole.xls")
        try Data("not ole".utf8).write(to: textURL)

        XCTAssertTrue(BinaryImportRouting.isLegacyXls(url: xlsURL))
        XCTAssertFalse(BinaryImportRouting.isLegacyXls(url: renamedURL))
        XCTAssertFalse(BinaryImportRouting.isLegacyXls(url: textURL))
    }

    func testDetectsSpssSavByExtensionAndMagic() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("document-routing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let savURL = directory.appendingPathComponent("survey.sav")
        try Data("$FL2more".utf8).write(to: savURL)
        let renamedURL = directory.appendingPathComponent("survey.bin")
        try Data("$FL2more".utf8).write(to: renamedURL)
        let textURL = directory.appendingPathComponent("not-sav.sav")
        try Data("not sav".utf8).write(to: textURL)

        XCTAssertTrue(BinaryImportRouting.isSpssSav(url: savURL))
        XCTAssertFalse(BinaryImportRouting.isSpssSav(url: renamedURL))
        XCTAssertFalse(BinaryImportRouting.isSpssSav(url: textURL))
    }

    func testDetectsSas7bdatByMagicOnlyWhenEnabled() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("document-routing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var header = Data(repeating: 0, count: 40)
        header.replaceSubrange(12..<32, with: Data([0xC2, 0xEA, 0x81, 0x60, 0xB3, 0x14, 0x11, 0xCF, 0xBD, 0x92, 0x08, 0x00, 0x09, 0xC7, 0x31, 0x8C, 0x18, 0x1F, 0x10, 0x11]))
        let sasURL = directory.appendingPathComponent("data.sas7bdat")
        try header.write(to: sasURL)
        let textURL = directory.appendingPathComponent("not-sas.sas7bdat")
        try Data("not sas".utf8).write(to: textURL)

        XCTAssertTrue(BinaryImportRouting.isSas7bdat(url: sasURL, enabled: true))
        XCTAssertFalse(BinaryImportRouting.isSas7bdat(url: sasURL, enabled: false))
        XCTAssertFalse(BinaryImportRouting.isSas7bdat(url: textURL, enabled: true))
    }
}
