import CsvCore
import Foundation

enum DataQualityReportFormatter {
    static func trafficLight(score: Int) -> String {
        switch score {
        case 90...:
            return "🟢"
        case 70..<90:
            return "🟡"
        case 50..<70:
            return "🟠"
        default:
            return "🔴"
        }
    }

    static func scopeLabel(_ report: DataQualityReport) -> String {
        switch report.scope {
        case .full:
            return L.t("full file", "전체 파일")
        case .partial:
            return L.t("partial", "부분")
        case .skipped:
            return L.t("skipped", "건너뜀")
        }
    }

    private static func severityLabel(_ severity: DataQualitySeverity) -> String {
        switch severity {
        case .info:
            return L.t("Info", "정보")
        case .warning:
            return L.t("Warning", "경고")
        case .error:
            return L.t("Error", "오류")
        }
    }
    private static func typeLabel(_ type: String) -> String {
        switch type {
        case "Empty": L.t("Empty", "비어 있음")
        case "Numeric": L.t("Numeric", "숫자")
        case "Date": L.t("Date", "날짜")
        case "Text": L.t("Text", "텍스트")
        default: type
        }
    }

    private static func issueMessage(_ issue: DataQualityIssue, report: DataQualityReport) -> String {
        let profile = report.columnProfiles.first { $0.column == issue.column }
        let name = profile?.name ?? issue.column.map { L.t("Column \($0 + 1)", "\($0 + 1)열") } ?? ""
        switch issue.rule {
        case .blankRate:
            return L.t("Column '\(name)' is more than half blank", "'\(name)' 열의 절반 이상이 비어 있습니다")
        case .sentinel:
            return L.t("Column '\(name)' contains sentinel/missing tokens", "'\(name)' 열에 센티널/결측 토큰이 있습니다")
        case .typeValidity:
            let type = typeLabel(profile?.dominantType ?? "")
            return L.t("Column '\(name)' is mostly \(type) but has non-conforming values", "'\(name)' 열은 대부분 \(type)이지만 맞지 않는 값이 있습니다")
        case .keyUniqueness:
            return L.t("Key column '\(name)' has duplicated values", "키 열 '\(name)'에 중복 값이 있습니다")
        case .raggedRow:
            return L.t("Rows with a field count different from the \(report.columnCount)-column header", "\(report.columnCount)열 헤더와 필드 수가 다른 행")
        case .duplicateRows:
            return L.t("Exact duplicate rows", "완전히 동일한 중복 행")
        }
    }


    static func markdown(report: DataQualityReport, fileName: String) -> String {
        var lines: [String] = []
        lines.append("# \(L.t("Data Quality Report", "데이터 품질 리포트")) — \(fileName)")
        lines.append("")
        lines.append("\(trafficLight(score: report.score)) \(L.t("Score", "점수")): **\(report.score) / 100**")
        lines.append("")
        lines.append("## \(L.t("Scan", "스캔"))")
        lines.append("- \(L.t("Rows", "행")): \(report.scannedRowCount.formatted(.number.locale(L.locale))) / \(report.rowCount.formatted(.number.locale(L.locale))) (\(scopeLabel(report)))")
        lines.append("- \(L.t("Columns", "컬럼")): \(report.columnCount)")
        if report.duplicateRowCount > 0 {
            lines.append("- \(L.t("Duplicate rows", "중복 행")): \(report.duplicateRowCount.formatted(.number.locale(L.locale)))\(report.duplicateScanTruncated ? " (~)" : "")")
        }
        lines.append("")

        lines.append("## \(L.t("Issues", "이슈")) (\(report.issues.count))")
        if report.issues.isEmpty {
            lines.append(L.t("No issues found.", "발견된 이슈가 없습니다."))
        } else {
            for issue in report.issues {
                var line = "- [\(severityLabel(issue.severity))] \(issueMessage(issue, report: report)) — \(issue.count.formatted(.number.locale(L.locale)))"
                if !issue.examples.isEmpty {
                    line += " (\(L.t("e.g.", "예:")) \(issue.examples.prefix(3).joined(separator: ", ")))"
                }
                lines.append(line)
            }
        }
        lines.append("")

        lines.append("## \(L.t("Column Profiles", "컬럼 프로필"))")
        lines.append("| \(L.t("Column", "컬럼")) | \(L.t("Type", "타입")) | \(L.t("Blank", "빈 값")) | \(L.t("Sentinel", "센티널")) | \(L.t("Distinct", "고유값")) |")
        lines.append("| --- | --- | --- | --- | --- |")
        for profile in report.columnProfiles {
            let distinct = "\(profile.distinctCount.formatted(.number.locale(L.locale)))\(profile.distinctTruncated ? "+" : "")"
            lines.append("| \(profile.name) | \(typeLabel(profile.dominantType)) | \(profile.blankCount.formatted(.number.locale(L.locale))) | \(profile.sentinelCount.formatted(.number.locale(L.locale))) | \(distinct) |")
        }
        lines.append("")

        if !report.codebook.isEmpty {
            lines.append("## \(L.t("Codebook", "코드북"))")
            for domain in report.codebook {
                let entries = domain.entries
                    .map { "\($0.value) (\($0.count.formatted(.number.locale(L.locale))))" }
                    .joined(separator: ", ")
                lines.append("- **\(domain.name)**: \(entries)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static func html(report: DataQualityReport, fileName: String) -> String {
        func escape(_ text: String) -> String {
            text
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }

        var body: [String] = []
        body.append("<h1>\(escape(L.t("Data Quality Report", "데이터 품질 리포트"))) — \(escape(fileName))</h1>")
        body.append("<p class=\"score\">\(trafficLight(score: report.score)) \(escape(L.t("Score", "점수"))): <strong>\(report.score) / 100</strong></p>")
        body.append("<h2>\(escape(L.t("Scan", "스캔")))</h2>")
        body.append("<ul>")
        body.append("<li>\(escape(L.t("Rows", "행"))): \(report.scannedRowCount.formatted(.number.locale(L.locale))) / \(report.rowCount.formatted(.number.locale(L.locale))) (\(escape(scopeLabel(report))))</li>")
        body.append("<li>\(escape(L.t("Columns", "컬럼"))): \(report.columnCount)</li>")
        if report.duplicateRowCount > 0 {
            body.append("<li>\(escape(L.t("Duplicate rows", "중복 행"))): \(report.duplicateRowCount.formatted(.number.locale(L.locale)))</li>")
        }
        body.append("</ul>")

        body.append("<h2>\(escape(L.t("Issues", "이슈"))) (\(report.issues.count))</h2>")
        if report.issues.isEmpty {
            body.append("<p>\(escape(L.t("No issues found.", "발견된 이슈가 없습니다.")))</p>")
        } else {
            body.append("<ul>")
            for issue in report.issues {
                var line = "<li><span class=\"sev-\(issue.severity.rawValue)\">[\(escape(severityLabel(issue.severity)))]</span> \(escape(issueMessage(issue, report: report))) — \(issue.count.formatted(.number.locale(L.locale)))"
                if !issue.examples.isEmpty {
                    line += " <em>(\(escape(issue.examples.prefix(3).joined(separator: ", "))))</em>"
                }
                line += "</li>"
                body.append(line)
            }
            body.append("</ul>")
        }

        body.append("<h2>\(escape(L.t("Column Profiles", "컬럼 프로필")))</h2>")
        body.append("<table><thead><tr><th>\(escape(L.t("Column", "컬럼")))</th><th>\(escape(L.t("Type", "타입")))</th><th>\(escape(L.t("Blank", "빈 값")))</th><th>\(escape(L.t("Sentinel", "센티널")))</th><th>\(escape(L.t("Distinct", "고유값")))</th></tr></thead><tbody>")
        for profile in report.columnProfiles {
            body.append("<tr><td>\(escape(profile.name))</td><td>\(escape(typeLabel(profile.dominantType)))</td><td>\(profile.blankCount.formatted(.number.locale(L.locale)))</td><td>\(profile.sentinelCount.formatted(.number.locale(L.locale)))</td><td>\(profile.distinctCount.formatted(.number.locale(L.locale)))\(profile.distinctTruncated ? "+" : "")</td></tr>")
        }
        body.append("</tbody></table>")

        if !report.codebook.isEmpty {
            body.append("<h2>\(escape(L.t("Codebook", "코드북")))</h2><ul>")
            for domain in report.codebook {
                let entries = domain.entries.map { "\(escape($0.value)) (\($0.count.formatted(.number.locale(L.locale))))" }.joined(separator: ", ")
                body.append("<li><strong>\(escape(domain.name))</strong>: \(entries)</li>")
            }
            body.append("</ul>")
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>\(escape(fileName)) — \(escape(L.t("Data Quality", "데이터 품질")))</title>
        <style>
        body { font: 13px -apple-system, sans-serif; margin: 24px; color: #1d1d1f; }
        table { border-collapse: collapse; }
        th, td { border: 1px solid #d0d0d0; padding: 4px 10px; text-align: left; }
        th { background: #f3f3f4; }
        .score { font-size: 16px; }
        .sev-error { color: #c62828; font-weight: 600; }
        .sev-warning { color: #a15c00; font-weight: 600; }
        .sev-info { color: #445; }
        </style>
        </head>
        <body>
        \(body.joined(separator: "\n"))
        </body>
        </html>
        """
    }

    static func json(report: DataQualityReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(report)
    }
}
