import Foundation
import XCTest
@testable import CsvCore

final class ImportMetadataTests: XCTestCase {
    func testDecodesMetadataAndMapsDeclaredTypes() throws {
        let json = """
        {
          "columns": [
            {
              "name": "status",
              "label": "Employment status",
              "declaredType": "ordinal",
              "valueLabels": { "1": "Full time", "2": "Part time" }
            },
            {
              "name": "income",
              "label": "Annual income",
              "declaredType": "currency",
              "valueLabels": {}
            },
            {
              "name": "ratio",
              "declaredType": "percent",
              "valueLabels": {}
            },
            {
              "name": "score",
              "declaredType": "scientific",
              "valueLabels": {}
            }
          ],
          "rowCount": 2,
          "encoding": "UTF-8",
          "warnings": [
            { "code": "missing-values", "message": "User-missing values imported as blanks." }
          ]
        }
        """

        let metadata = try JSONDecoder().decode(ImportMetadata.self, from: Data(json.utf8))

        XCTAssertEqual(metadata.rowCount, 2)
        XCTAssertEqual(metadata.encoding, "UTF-8")
        XCTAssertEqual(metadata.columns[0].label, "Employment status")
        XCTAssertEqual(metadata.columns[0].valueLabels["1"], "Full time")
        XCTAssertEqual(metadata.warnings[0].code, "missing-values")
        XCTAssertEqual(metadata.columnTypeOverrides(), [
            0: .categorical,
            1: .float,
            2: .float,
            3: .float
        ])
        XCTAssertEqual(metadata.displayValue(rawValue: "2", columnIndex: 0), "Part time")
        XCTAssertEqual(metadata.displayValue(rawValue: "9", columnIndex: 0), "9")
    }
}
