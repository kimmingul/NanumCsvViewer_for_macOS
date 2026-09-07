import Foundation
import CsvCore

// Keep stable core values for persistence and computation; translate only presentation.
extension AggregationFunction {
    var localizedTitle: String {
        switch self {
        case .count: L.t("Count", "개수")
        case .sum: L.t("Sum", "합계")
        case .mean: L.t("Mean", "평균")
        case .median: L.t("Median", "중앙값")
        case .min: L.t("Min", "최솟값")
        case .max: L.t("Max", "최댓값")
        case .uniqueCount: L.t("Unique Count", "고유 값 개수")
        case .standardDeviation: L.t("Std", "표준편차")
        }
    }
}

extension DateBinPeriod {
    var localizedTitle: String {
        switch self {
        case .day: L.t("Day", "일")
        case .week: L.t("Week", "주")
        case .month: L.t("Month", "월")
        case .year: L.t("Year", "년")
        }
    }
}

extension ColumnValueType {
    var localizedTitle: String {
        switch self {
        case .integer: L.t("Integer", "정수")
        case .float: L.t("Float", "실수")
        case .date: L.t("Date", "날짜")
        case .boolean: L.t("Boolean", "논리값")
        case .categorical: L.t("Categorical", "범주형")
        case .string: L.t("String", "문자열")
        case .empty: L.t("Empty", "비어 있음")
        }
    }
}

enum LocalizedPresentation {
    static func importWarning(code: String, message: String) -> String {
        if code == "sas-best-effort" {
            return L.t("SAS import is best-effort; verify critical data against SAS.", "SAS 가져오기는 best-effort입니다. 중요한 데이터는 SAS에서 확인하세요.")
        }
        return message
    }

    static func quoteWarning(_ warning: String) -> String {
        if warning == "The file ends inside an unterminated quote; rows after it were merged into the last record." {
            return L.t("The file ends inside an unterminated quote; rows after it were merged into the last record.", "파일이 닫히지 않은 따옴표 안에서 끝납니다. 이후 행이 마지막 레코드에 병합되었습니다.")
        }
        let prefix = "A row spans "
        let suffix = " lines. An unterminated quote can merge rows; this may also be a legitimate multi-line cell."
        if warning.hasPrefix(prefix), warning.hasSuffix(suffix),
           let lines = Int(warning.dropFirst(prefix.count).dropLast(suffix.count)) {
            return L.t("A row spans \(lines) lines. An unterminated quote can merge rows; this may also be a legitimate multi-line cell.", "한 행이 \(lines)줄에 걸쳐 있습니다. 닫히지 않은 따옴표가 행을 병합할 수 있지만 정상적인 여러 줄 셀일 수도 있습니다.")
        }
        return warning
    }

    static func interpretation(_ value: String) -> String {
        switch value {
        case "statistically significant (p < 0.05)": L.t("statistically significant (p < 0.05)", "통계적으로 유의함 (p < 0.05)")
        case "not statistically significant (p >= 0.05)": L.t("not statistically significant (p >= 0.05)", "통계적으로 유의하지 않음 (p >= 0.05)")
        case "sample too small": L.t("sample too small", "표본이 너무 작음")
        case "constant data": L.t("constant data", "모든 값이 동일함")
        case "deviates from normality (p < 0.05)": L.t("deviates from normality (p < 0.05)", "정규분포에서 벗어남 (p < 0.05)")
        case "consistent with normality (p >= 0.05)": L.t("consistent with normality (p >= 0.05)", "정규분포와 일치함 (p >= 0.05)")
        default: value
        }
    }

    static func error(_ error: Error) -> Error {
        guard let description = errorDescription(error) else { return error }
        let original = error as NSError
        var info = original.userInfo
        info[NSLocalizedDescriptionKey] = description
        return NSError(domain: original.domain, code: original.code, userInfo: info)
    }
    private static func filterSyntaxReason(_ reason: String) -> String {
        switch reason {
        case "Missing closing parenthesis": return L.t("Missing closing parenthesis", "닫는 괄호가 없습니다")
        case "Expected column name": return L.t("Expected column name", "열 이름이 필요합니다")
        case "Expected operator": return L.t("Expected operator", "연산자가 필요합니다")
        case "Expected comparison value": return L.t("Expected comparison value", "비교 값이 필요합니다")
        default: break
        }
        // The parser exposes token diagnostics as strings, not structured cases.
        if reason.hasPrefix("Unexpected token '"), reason.hasSuffix("'") {
            let token = String(reason.dropFirst("Unexpected token '".count).dropLast())
            return L.t("Unexpected token '\(token)'", "예상하지 못한 토큰 '\(token)'")
        }
        if reason.hasPrefix("Unsupported operator '"), reason.hasSuffix("'") {
            let token = String(reason.dropFirst("Unsupported operator '".count).dropLast())
            return L.t("Unsupported operator '\(token)'", "지원하지 않는 연산자 '\(token)'")
        }
        return reason
    }

    private static func importErrorSummary(code: String) -> String {
        switch code {
        case "unsupportedKind": L.t("Unsupported import kind.", "지원하지 않는 가져오기 형식입니다.")
        case "maxBytesExceeded": L.t("The source file exceeds the import byte limit.", "원본 파일이 가져오기 바이트 제한을 초과합니다.")
        case "timeoutExceeded": L.t("The import timed out.", "가져오기 제한 시간이 초과되었습니다.")
        case "noSheets": L.t("The file has no readable sheets or tables.", "파일에 읽을 수 있는 시트나 테이블이 없습니다.")
        case "maxRowsExceeded": L.t("The file exceeds the import row limit.", "파일이 가져오기 행 제한을 초과합니다.")
        case "maxColumnsExceeded": L.t("The file exceeds the import column limit.", "파일이 가져오기 열 제한을 초과합니다.")
        case "maxCellsExceeded": L.t("The file exceeds the import cell limit.", "파일이 가져오기 셀 제한을 초과합니다.")
        case "maxCellCharsExceeded": L.t("A cell in the file is too large to import.", "파일의 셀이 너무 커서 가져올 수 없습니다.")
        case "maxUncompressedBytesExceeded": L.t("The file expands too much to import.", "파일의 압축 해제 크기가 너무 커서 가져올 수 없습니다.")
        case "parseFailed": L.t("The file could not be parsed.", "파일을 해석할 수 없습니다.")
        case "readFailed": L.t("The file could not be read.", "파일을 읽을 수 없습니다.")
        default: L.t("Import failed.", "가져오기에 실패했습니다.")
        }
    }


    static func errorDescription(_ error: Error) -> String? {
        switch error {
        case let error as CsvError:
            switch error {
            case .unsupportedEncoding(let name):
                return L.t("'\(name)' encoding is not supported in high-speed mode. Use UTF-8 or CP949/EUC-KR.", "고속 모드에서 '\(name)' 인코딩을 지원하지 않습니다. UTF-8 또는 CP949/EUC-KR을 사용하세요.")
            case .fileOpenFailed(let path):
                return L.t("Could not open file: \(path)", "파일을 열 수 없습니다: \(path)")
            case .shortRead:
                return L.t("The file became shorter while reading. It may have been changed by another process.", "읽는 동안 파일이 짧아졌습니다. 다른 프로세스에서 변경했을 수 있습니다.")
            case .cancelled:
                return L.t("The operation was cancelled.", "작업이 취소되었습니다.")
            case .indexingInProgress:
                return L.t("Indexing is already running for this document.", "이 문서의 인덱싱이 이미 진행 중입니다.")
            case .indexingFailed:
                return L.t("Indexing failed for this document; reopen the file to try again.", "문서 인덱싱에 실패했습니다. 파일을 다시 열어 재시도하세요.")
            }
        case let error as CsvSearchError:
            switch error {
            case .invalidRegularExpression(let pattern):
                return L.t("'\(pattern)' is not a valid regular expression.", "'\(pattern)'은 유효한 정규식이 아닙니다.")
            case .unsafeRegularExpression(let pattern):
                return L.t("'\(pattern)' uses nested quantifiers that can hang the search and was rejected.", "'\(pattern)'에 검색을 멈출 수 있는 중첩 수량자가 있어 거부되었습니다.")
            }
        case let error as CsvResourceLimitError:
            switch error {
            case .pivotDimensions:
                return L.t("This pivot exceeds the safe result size (100,000 rows, 256 columns, or 1,000,000 cells). Filter the data, group dates, or move a high-cardinality field from Columns to Rows.", "이 피벗은 안전한 결과 크기(100,000행, 256열 또는 1,000,000셀)를 초과합니다. 데이터를 필터링하거나 날짜를 그룹화하거나 고유 값이 많은 필드를 열에서 행으로 이동하세요.")
            case .distinctValues(let limit):
                return L.t("This column has more than \(limit.formatted(.number.locale(L.locale))) distinct values. Use an exact-value or expression filter instead of listing every category.", "이 열에는 \(limit.formatted(.number.locale(L.locale)))개 이상의 고유 값이 있습니다. 모든 범주를 나열하는 대신 정확한 값 또는 표현식 필터를 사용하세요.")
            }
        case let error as AdvancedFilterExpressionError:
            switch error {
            case .emptyExpression:
                return L.t("Filter expression is empty.", "필터 표현식이 비어 있습니다.")
            case .unknownColumn(let name):
                return L.t("Unknown column: \(name)", "알 수 없는 열: \(name)")
            case .invalidSyntax(let reason):
                let detail = filterSyntaxReason(reason)
                return L.t("Invalid filter expression: \(detail)", "잘못된 필터 표현식: \(detail)")
            }
        case let error as WorkbookImportError:
            switch error {
            case .maxRowsExceeded: return importErrorSummary(code: "maxRowsExceeded")
            case .maxColumnsExceeded: return importErrorSummary(code: "maxColumnsExceeded")
            case .maxCellsExceeded: return importErrorSummary(code: "maxCellsExceeded")
            case .maxCellCharsExceeded: return importErrorSummary(code: "maxCellCharsExceeded")
            case .maxUncompressedBytesExceeded: return importErrorSummary(code: "maxUncompressedBytesExceeded")
            case .timedOut: return importErrorSummary(code: "timeoutExceeded")
            }
        case let error as XlsxWorkbookError:
            switch error {
            case .sheetNotFound(let name): return L.t("Sheet '\(name)' was not found.", "'\(name)' 시트를 찾을 수 없습니다.")
            case .cannotOpen(let detail), .invalidWorkbook(let detail):
                return L.t("The workbook could not be opened. Technical details: \(detail)", "통합 문서를 열 수 없습니다. 기술 세부 정보: \(detail)")
            }
        case let error as SqliteWorkbookError:
            switch error {
            case .tableNotFound(let name): return L.t("Table '\(name)' was not found.", "'\(name)' 테이블을 찾을 수 없습니다.")
            case .cannotOpen(let detail), .queryFailed(let detail):
                return L.t("The database could not be read. Technical details: \(detail)", "데이터베이스를 읽을 수 없습니다. 기술 세부 정보: \(detail)")
            }
        case let error as ImportClientError:
            switch error {
            case .cannotOpenBridgeFiles:
                return L.t("Could not open the files required for import.", "가져오기에 필요한 파일을 열 수 없습니다.")
            case .connectionInterrupted:
                return L.t("The import service connection was interrupted. Try importing the file again.", "가져오기 서비스 연결이 중단되었습니다. 파일을 다시 가져오세요.")
            case .connectionInvalidated:
                return L.t("The import service connection closed. Try importing the file again.", "가져오기 서비스 연결이 종료되었습니다. 파일을 다시 가져오세요.")
            case .invalidReply:
                return L.t("The import service returned an invalid response.", "가져오기 서비스에서 잘못된 응답을 반환했습니다.")
            case .serviceError(let code, let message):
                return importErrorSummary(code: code) + "\n\n" + L.t("Technical details (\(code)): \(message)", "기술 세부 정보(\(code)): \(message)")
            }
        default:
            return nil
        }
    }

    static func filterDescriptions(_ state: ColumnFilterState, columnNames: [String]) -> [String] {
        state.filters.map { filter in
            let name = columnNames.indices.contains(filter.column) ? columnNames[filter.column] : L.t("Column \(filter.column + 1)", "\(filter.column + 1)열")
            switch filter {
            case .selectedValues(_, let values, let includeBlanks):
                let blankLabel = L.t("(Blank)", "(빈 값)")
                if values.count > 6 {
                    let blank = includeBlanks ? ", \(blankLabel)" : ""
                    return L.t("\(name) in \(values.count.formatted(.number.locale(L.locale))) selected values\(blank)", "\(name): 선택한 값 \(values.count.formatted(.number.locale(L.locale)))개\(blank)")
                }
                var labels = values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { "\"\($0)\"" }
                if includeBlanks { labels.append(blankLabel) }
                return L.t("\(name) in \(labels.joined(separator: ", "))", "\(name): \(labels.joined(separator: ", ")) 중 하나")
            case .dateRange(_, let start, let end):
                let formatter = DateFormatter()
                formatter.locale = L.locale
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateStyle = .medium
                switch (start, end) {
                case (.some(let start), .some(let end)):
                    return L.t("\(name) between \(formatter.string(from: start)) and \(formatter.string(from: end))", "\(name): \(formatter.string(from: start))부터 \(formatter.string(from: end))까지")
                case (.some(let start), .none):
                    return "\(name) ≥ \(formatter.string(from: start))"
                case (.none, .some(let end)):
                    return "\(name) ≤ \(formatter.string(from: end))"
                case (.none, .none): return name
                }
            case .numericRange(_, let lower, let upper, let includesUpperBound):
                let symbol = includesUpperBound ? "≤" : "<"
                return "\(ColumnFilterState.numericBoundLabel(lower)) ≤ \(name) \(symbol) \(ColumnFilterState.numericBoundLabel(upper))"
            }
        }
    }
}
