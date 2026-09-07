import Foundation
import XCTest
@testable import NanumCsvViewerMac

final class LocalizationTests: XCTestCase {
    func testTranslationReordersArgumentsWithoutInterpretingUserData() {
        let name = "매출 {1} \"2026\"\n.csv"
        let count = "42"
        let text: L.Text = "File \(name): \(count) rows {sample}"
        let catalog = ["File {0}: {1} rows {{sample}}": "{1}행 — {0} {{표본}}"]

        XCTAssertEqual(L.translate(text, catalog: catalog), "42행 — 매출 {1} \"2026\"\n.csv {표본}")
    }

    func testMissingOrMalformedTranslationFallsBackWithoutLosingValues() {
        let value = "{0}"
        let text: L.Text = "Value: \(value)"

        XCTAssertEqual(L.translate(text, catalog: [:]), "Value: {0}")
        XCTAssertEqual(L.translate(text, catalog: ["Value: {0}": "Valeur: {1}"]), "Value: {0}")
        XCTAssertEqual(L.translate(text, catalog: ["Value: {0}": "Valeur"]), "Value: {0}")
        XCTAssertEqual(L.translate(text, catalog: ["Value: {0}": "{0} {0}"]), "Value: {0}")
        XCTAssertEqual(L.translate(text, catalog: ["Value: {0}": "Valeur: {0"]), "Value: {0}")
        XCTAssertEqual(L.translate("Open", catalog: ["Open": ""]), "Open")
    }

    func testInterpolationIsEvaluatedOnceAndKoreanAuthoringLiteralIsLazy() {
        var evaluations = 0
        func nextValue() -> String {
            evaluations += 1
            return "value-\(evaluations)"
        }

        let result = L.t("Uncatalogued value: \(nextValue())", "카탈로그에 없는 값: \(nextValue())")

        XCTAssertEqual(evaluations, 1)
        XCTAssertEqual(result, "Uncatalogued value: value-1")
    }

    func testLanguageNegotiationUsesEntirePreferredListAndExplicitScripts() {
        XCTAssertEqual(L.resolveLanguage(preferredLanguages: ["ar-SA", "fr-CA", "ko-KR"]), "fr")
        XCTAssertEqual(L.resolveLanguage(preferredLanguages: ["zh-TW", "en-US"]), "zh-Hant")
        XCTAssertEqual(L.resolveLanguage(preferredLanguages: ["zh_HK"]), "zh-Hant")
        XCTAssertEqual(L.resolveLanguage(preferredLanguages: ["zh-Hans-HK"]), "zh-Hans")
        XCTAssertEqual(L.resolveLanguage(preferredLanguages: ["zh-Hant-CN"]), "zh-Hant")
        XCTAssertEqual(L.resolveLanguage(preferredLanguages: ["pt-PT"]), "pt-BR")
        XCTAssertEqual(L.resolveLanguage(preferredLanguages: ["ar", "he"]), "en")
    }

    func testValidOverrideWinsAndStaleOverrideDoesNotHideSystemPreference() {
        XCTAssertEqual(L.resolveLanguage(preferredLanguages: ["ko-KR"], selectedLanguageCode: "nl"), "nl")
        XCTAssertEqual(L.resolveLanguage(preferredLanguages: ["ja-JP"], selectedLanguageCode: "removed-language"), "ja")
    }

    func testLocalizedFloatingPointPreservesPrecisionWithoutBinaryNoise() {
        let locale = Locale(identifier: "de-DE")
        XCTAssertEqual(L.formatFloatingPoint(1234.56789, locale: locale), "1.234,56789")
        XCTAssertEqual(L.formatFloatingPoint(Float(0.1), locale: locale), "0,1")
        XCTAssertEqual(L.formatFloatingPoint(0.000000001, locale: locale), "0,000000001")
    }

    func testPackagedKoreanCatalogRendersExtractedDynamicTemplate() throws {
        let url = try XCTUnwrap(L.catalogURL(languageCode: "ko"))
        let catalog = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
        let name = "売上.csv"
        let text: L.Text = "Column: \(name)"

        XCTAssertEqual(L.translate(text, catalog: catalog), "컬럼: 売上.csv")
    }
}
