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

    static func markdown(report: DataQualityReport, fileName: String) -> String {
        var lines: [String] = []
        lines.append("# \(L.t("Data Quality Report", "데이터 품질 리포트")) — \(fileName)")
        lines.append("")
        lines.append("\(trafficLight(score: report.score)) \(L.t("Score", "점수")): **\(report.score) / 100**")
        lines.append("")
        lines.append("## \(L.t("Scan", "스캔"))")
        lines.append("- \(L.t("Rows", "행")): \(report.scannedRowCount.formatted()) / \(report.rowCount.formatted()) (\(scopeLabel(report)))")
        lines.append("- \(L.t("Columns", "컬럼")): \(report.columnCount)")
        if report.duplicateRowCount > 0 {
            lines.append("- \(L.t("Duplicate rows", "중복 행")): \(report.duplicateRowCount.formatted())\(report.duplicateScanTruncated ? " (~)" : "")")
        }
        lines.append("")

        lines.append("## \(L.t("Issues", "이슈")) (\(report.issues.count))")
        if report.issues.isEmpty {
            lines.append(L.t("No issues found.", "발견된 이슈가 없습니다."))
        } else {
            for issue in report.issues {
                var line = "- [\(severityLabel(issue.severity))] \(issue.message) — \(issue.count.formatted())"
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
            let distinct = "\(profile.distinctCount.formatted())\(profile.distinctTruncated ? "+" : "")"
            lines.append("| \(profile.name) | \(profile.dominantType) | \(profile.blankCount.formatted()) | \(profile.sentinelCount.formatted()) | \(distinct) |")
        }
        lines.append("")

        if !report.codebook.isEmpty {
            lines.append("## \(L.t("Codebook", "코드북"))")
            for domain in report.codebook {
                let entries = domain.entries
                    .map { "\($0.value) (\($0.count.formatted()))" }
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
        body.append("<li>\(escape(L.t("Rows", "행"))): \(report.scannedRowCount.formatted()) / \(report.rowCount.formatted()) (\(escape(scopeLabel(report))))</li>")
        body.append("<li>\(escape(L.t("Columns", "컬럼"))): \(report.columnCount)</li>")
        if report.duplicateRowCount > 0 {
            body.append("<li>\(escape(L.t("Duplicate rows", "중복 행"))): \(report.duplicateRowCount.formatted())</li>")
        }
        body.append("</ul>")

        body.append("<h2>\(escape(L.t("Issues", "이슈"))) (\(report.issues.count))</h2>")
        if report.issues.isEmpty {
            body.append("<p>\(escape(L.t("No issues found.", "발견된 이슈가 없습니다.")))</p>")
        } else {
            body.append("<ul>")
            for issue in report.issues {
                var line = "<li><span class=\"sev-\(issue.severity.rawValue)\">[\(escape(severityLabel(issue.severity)))]</span> \(escape(issue.message)) — \(issue.count.formatted())"
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
            body.append("<tr><td>\(escape(profile.name))</td><td>\(profile.dominantType)</td><td>\(profile.blankCount.formatted())</td><td>\(profile.sentinelCount.formatted())</td><td>\(profile.distinctCount.formatted())\(profile.distinctTruncated ? "+" : "")</td></tr>")
        }
        body.append("</tbody></table>")

        if !report.codebook.isEmpty {
            body.append("<h2>\(escape(L.t("Codebook", "코드북")))</h2><ul>")
            for domain in report.codebook {
                let entries = domain.entries.map { "\(escape($0.value)) (\($0.count.formatted()))" }.joined(separator: ", ")
                body.append("<li><strong>\(escape(domain.name))</strong>: \(entries)</li>")
            }
            body.append("</ul>")
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>\(escape(fileName)) — Data Quality</title>
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
