import Foundation
@preconcurrency import CsvCore

enum AnalysisKind: String, CaseIterable, Sendable {
    case numericDistribution
    case dateHistogram
    case duplicateRows
    case groupBy
    case correlation
    case independentTTest
    case chiSquare
    case descriptiveStatistics
    case frequencyAnalysis
    case oneWayAnova
    case normalityTest
    case documentSummary

    var title: String {
        switch self {
        case .numericDistribution:
            return L.t("Numeric Distribution", "숫자 분포")
        case .dateHistogram:
            return L.t("Date Histogram", "날짜 히스토그램")
        case .duplicateRows:
            return L.t("Duplicate Rows", "중복 행")
        case .groupBy:
            return L.t("Group By", "그룹화")
        case .correlation:
            return L.t("Correlation", "상관분석")
        case .independentTTest:
            return L.t("t-test", "t-검정")
        case .chiSquare:
            return L.t("Chi-square Test", "카이제곱 검정")
        case .descriptiveStatistics:
            return L.t("Descriptive Statistics", "기술통계")
        case .frequencyAnalysis:
            return L.t("Frequency Analysis", "빈도분석")
        case .oneWayAnova:
            return L.t("One-way ANOVA", "일원배치 분산분석")
        case .normalityTest:
            return L.t("Normality Test (Shapiro-Wilk)", "정규성 검정 (Shapiro-Wilk)")
        case .documentSummary:
            return L.t("Quick Stats", "빠른 통계")
        }
    }
}

enum AnalysisRequest: Equatable, Sendable {
    case numericDistribution(column: Int, binCount: Int)
    case dateHistogram(dateColumn: Int, valueColumn: Int?, period: DateBinPeriod)
    case duplicateRows(columns: [Int])
    case groupBy(groupColumns: [Int], valueColumn: Int, functions: [AggregationFunction])
    case correlation(xColumn: Int, yColumn: Int)
    case independentTTest(groupColumn: Int, valueColumn: Int, groupA: String, groupB: String)
    case chiSquare(rowColumn: Int, columnColumn: Int)
    case descriptiveStatistics(columns: [Int])
    case frequencyAnalysis(column: Int)
    case oneWayAnova(groupColumn: Int, valueColumn: Int)
    case normalityTest(column: Int)
    case documentSummary

    var kind: AnalysisKind {
        switch self {
        case .numericDistribution:
            return .numericDistribution
        case .dateHistogram:
            return .dateHistogram
        case .duplicateRows:
            return .duplicateRows
        case .groupBy:
            return .groupBy
        case .correlation:
            return .correlation
        case .independentTTest:
            return .independentTTest
        case .chiSquare:
            return .chiSquare
        case .descriptiveStatistics:
            return .descriptiveStatistics
        case .frequencyAnalysis:
            return .frequencyAnalysis
        case .oneWayAnova:
            return .oneWayAnova
        case .normalityTest:
            return .normalityTest
        case .documentSummary:
            return .documentSummary
        }
    }

    func selectedColumns() -> [Int] {
        switch self {
        case .numericDistribution(let column, _):
            return [column]
        case .dateHistogram(let dateColumn, let valueColumn, _):
            return [dateColumn] + (valueColumn.map { [$0] } ?? [])
        case .duplicateRows(let columns):
            return columns
        case .groupBy(let groupColumns, let valueColumn, _):
            return groupColumns + [valueColumn]
        case .correlation(let xColumn, let yColumn):
            return [xColumn, yColumn]
        case .independentTTest(let groupColumn, let valueColumn, _, _):
            return [groupColumn, valueColumn]
        case .chiSquare(let rowColumn, let columnColumn):
            return [rowColumn, columnColumn]
        case .descriptiveStatistics(let columns):
            return columns
        case .frequencyAnalysis(let column):
            return [column]
        case .oneWayAnova(let groupColumn, let valueColumn):
            return [groupColumn, valueColumn]
        case .normalityTest(let column):
            return [column]
        case .documentSummary:
            return []
        }
    }

    func parameterLines(columnNames: [String]) -> [String] {
        switch self {
        case .numericDistribution(let column, let binCount):
            return [
                L.t("Column: \(columnName(column, columnNames: columnNames))", "컬럼: \(columnName(column, columnNames: columnNames))"),
                L.t("Bins: \(binCount)", "구간: \(binCount)")
            ]
        case .dateHistogram(let dateColumn, let valueColumn, let period):
            var lines = [
                L.t("Date column: \(columnName(dateColumn, columnNames: columnNames))", "날짜 컬럼: \(columnName(dateColumn, columnNames: columnNames))"),
                L.t("Period: \(period.rawValue)", "단위: \(period.rawValue)")
            ]
            lines.append(valueColumn.map {
                L.t("Value column: \(columnName($0, columnNames: columnNames))", "값 컬럼: \(columnName($0, columnNames: columnNames))")
            } ?? L.t("Value column: Count only", "값 컬럼: 개수만"))
            return lines
        case .duplicateRows(let columns):
            let names = columns.map { columnName($0, columnNames: columnNames) }.joined(separator: ", ")
            return [L.t("Columns: \(names)", "컬럼: \(names)")]
        case .groupBy(let groupColumns, let valueColumn, let functions):
            return [
                L.t("Group columns: \(groupColumns.map { columnName($0, columnNames: columnNames) }.joined(separator: ", "))", "그룹 컬럼: \(groupColumns.map { columnName($0, columnNames: columnNames) }.joined(separator: ", "))"),
                L.t("Value column: \(columnName(valueColumn, columnNames: columnNames))", "값 컬럼: \(columnName(valueColumn, columnNames: columnNames))"),
                L.t("Functions: \(functions.map(\.rawValue).joined(separator: ", "))", "집계: \(functions.map(\.rawValue).joined(separator: ", "))")
            ]
        case .correlation(let xColumn, let yColumn):
            return [
                L.t("X column: \(columnName(xColumn, columnNames: columnNames))", "X 컬럼: \(columnName(xColumn, columnNames: columnNames))"),
                L.t("Y column: \(columnName(yColumn, columnNames: columnNames))", "Y 컬럼: \(columnName(yColumn, columnNames: columnNames))")
            ]
        case .independentTTest(let groupColumn, let valueColumn, let groupA, let groupB):
            return [
                L.t("Group column: \(columnName(groupColumn, columnNames: columnNames))", "그룹 컬럼: \(columnName(groupColumn, columnNames: columnNames))"),
                L.t("Value column: \(columnName(valueColumn, columnNames: columnNames))", "값 컬럼: \(columnName(valueColumn, columnNames: columnNames))"),
                L.t("Groups: \(groupA), \(groupB)", "그룹: \(groupA), \(groupB)")
            ]
        case .chiSquare(let rowColumn, let columnColumn):
            return [
                L.t("Row column: \(columnName(rowColumn, columnNames: columnNames))", "행 컬럼: \(columnName(rowColumn, columnNames: columnNames))"),
                L.t("Column column: \(columnName(columnColumn, columnNames: columnNames))", "열 컬럼: \(columnName(columnColumn, columnNames: columnNames))")
            ]
        case .descriptiveStatistics(let columns):
            let names = columns.map { columnName($0, columnNames: columnNames) }.joined(separator: ", ")
            return [L.t("Columns: \(names)", "컬럼: \(names)")]
        case .frequencyAnalysis(let column):
            return [L.t("Column: \(columnName(column, columnNames: columnNames))", "컬럼: \(columnName(column, columnNames: columnNames))")]
        case .oneWayAnova(let groupColumn, let valueColumn):
            return [
                L.t("Group column: \(columnName(groupColumn, columnNames: columnNames))", "그룹 컬럼: \(columnName(groupColumn, columnNames: columnNames))"),
                L.t("Value column: \(columnName(valueColumn, columnNames: columnNames))", "값 컬럼: \(columnName(valueColumn, columnNames: columnNames))")
            ]
        case .normalityTest(let column):
            return [L.t("Column: \(columnName(column, columnNames: columnNames))", "컬럼: \(columnName(column, columnNames: columnNames))")]
        case .documentSummary:
            return []
        }
    }

    private func columnName(_ column: Int, columnNames: [String]) -> String {
        columnNames.indices.contains(column) ? columnNames[column] : L.t("Column \(column + 1)", "\(column + 1)열")
    }
}

struct AnalysisProvenance: Equatable, Sendable {
    let visibleRows: Int
    let totalRows: Int
    let isFiltered: Bool
    let filters: [String]
    let sortDescription: String?
    let columnNames: [String]
    let parameterLines: [String]
    let generatedAt: Date
    let elapsedMilliseconds: Int?
    var scannedRows: Int? = nil

    func withElapsed(_ elapsed: TimeInterval) -> AnalysisProvenance {
        AnalysisProvenance(
            visibleRows: visibleRows,
            totalRows: totalRows,
            isFiltered: isFiltered,
            filters: filters,
            sortDescription: sortDescription,
            columnNames: columnNames,
            parameterLines: parameterLines,
            generatedAt: generatedAt,
            elapsedMilliseconds: Int((elapsed * 1_000).rounded()),
            scannedRows: scannedRows
        )
    }

    var lines: [String] {
        var output = [
            L.t("Rows: \(visibleRows.formatted()) / \(totalRows.formatted())", "행: \(visibleRows.formatted()) / \(totalRows.formatted())"),
            L.t("View: \(isFiltered ? "Filtered current view" : "All rows")", "보기: \(isFiltered ? "필터된 현재 보기" : "전체 행")")
        ]
        if let scannedRows, scannedRows < visibleRows {
            output.append(L.t(
                "Scope: showing first \(scannedRows.formatted()) rows",
                "범위: 처음 \(scannedRows.formatted())행 기준"
            ))
        }
        if !filters.isEmpty {
            output.append(L.t("Filters: \(filters.joined(separator: " | "))", "필터: \(filters.joined(separator: " | "))"))
        }
        if let sortDescription, !sortDescription.isEmpty {
            output.append(L.t("Sort: \(sortDescription)", "정렬: \(sortDescription)"))
        }
        if !columnNames.isEmpty {
            let columnScope = columnNames.prefix(6).joined(separator: ", ") + (columnNames.count > 6 ? ", ..." : "")
            output.append(L.t("Columns: \(columnScope)", "컬럼: \(columnScope)"))
        }
        output.append(contentsOf: parameterLines)
        if let elapsedMilliseconds {
            output.append(L.t("Elapsed: \(elapsedMilliseconds) ms", "소요 시간: \(elapsedMilliseconds) ms"))
        }
        return output
    }
}

struct AnalysisMetric: Equatable, Sendable {
    let name: String
    let value: String
}

struct AnalysisTable: Equatable, Sendable {
    let title: String
    let headers: [String]
    let rows: [[String]]
    let truncated: Bool
}

enum AnalysisSection: Equatable, Sendable {
    case metrics(title: String, rows: [AnalysisMetric])
    case table(AnalysisTable)
}

struct AnalysisReport: Equatable, Sendable {
    let title: String
    let summary: String
    let provenance: AnalysisProvenance
    let sections: [AnalysisSection]

    var markdown: String {
        var lines = ["# \(title)", "", summary, "", "## \(L.t("Run Details", "실행 정보"))"]
        lines.append(contentsOf: provenance.lines.map { "- \($0)" })
        for section in sections {
            lines.append("")
            switch section {
            case .metrics(let title, let rows):
                lines.append("## \(title)")
                for row in rows {
                    lines.append("- \(row.name): \(row.value)")
                }
            case .table(let table):
                lines.append("## \(table.title)")
                lines.append(markdownTable(headers: table.headers, rows: table.rows))
                if table.truncated {
                    lines.append("")
                    lines.append(L.t("_Preview truncated. Export for the displayed preview only._", "_미리보기가 잘렸습니다. 현재 미리보기만 내보냅니다._"))
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    var tsv: String {
        var lines = [[title], [summary], provenance.lines]
            .map { $0.joined(separator: "\t") }
        for section in sections {
            lines.append("")
            switch section {
            case .metrics(let title, let rows):
                lines.append(title)
                lines.append(contentsOf: rows.map { [$0.name, $0.value].joined(separator: "\t") })
            case .table(let table):
                lines.append(table.title)
                lines.append(table.headers.joined(separator: "\t"))
                lines.append(contentsOf: table.rows.map { $0.joined(separator: "\t") })
            }
        }
        return lines.joined(separator: "\n")
    }

    var csv: String {
        var rows: [[String]] = [[title], [summary]] + provenance.lines.map { [$0] }
        for section in sections {
            rows.append([])
            switch section {
            case .metrics(let title, let metrics):
                rows.append([title])
                rows.append(contentsOf: metrics.map { [$0.name, $0.value] })
            case .table(let table):
                rows.append([table.title])
                rows.append(table.headers)
                rows.append(contentsOf: table.rows)
            }
        }
        return rows.map { $0.map(csvEscaped).joined(separator: ",") }.joined(separator: "\n")
    }

    var jsonObject: [String: Any] {
        [
            "title": title,
            "summary": summary,
            "provenance": [
                "visibleRows": provenance.visibleRows,
                "totalRows": provenance.totalRows,
                "isFiltered": provenance.isFiltered,
                "filters": provenance.filters,
                "sort": provenance.sortDescription as Any,
                "columns": provenance.columnNames,
                "parameters": provenance.parameterLines,
                "elapsedMilliseconds": provenance.elapsedMilliseconds as Any
            ],
            "sections": sections.map { section -> [String: Any] in
                switch section {
                case .metrics(let title, let rows):
                    return [
                        "type": "metrics",
                        "title": title,
                        "rows": rows.map { ["name": $0.name, "value": $0.value] }
                    ]
                case .table(let table):
                    return [
                        "type": "table",
                        "title": table.title,
                        "headers": table.headers,
                        "rows": table.rows,
                        "truncated": table.truncated
                    ]
                }
            }
        ]
    }

    func jsonData() throws -> Data {
        try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])
    }

    private func markdownTable(headers: [String], rows: [[String]]) -> String {
        guard !headers.isEmpty else { return "" }
        let header = "| " + headers.map(markdownEscaped).joined(separator: " | ") + " |"
        let rule = "| " + headers.map { _ in "---" }.joined(separator: " | ") + " |"
        let body = rows.map { row in
            "| " + headers.indices.map { index in
                markdownEscaped(row.indices.contains(index) ? row[index] : "")
            }.joined(separator: " | ") + " |"
        }
        return ([header, rule] + body).joined(separator: "\n")
    }

    private func markdownEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }

    private func csvEscaped(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}

enum AnalysisReportBuilder {
    static func make(
        request: AnalysisRequest,
        document: VirtualCsvDocument,
        columnNames: [String],
        columnStatisticsReport: ColumnStatisticsReport?,
        provenance: AnalysisProvenance,
        cancellation: CancellationFlag
    ) throws -> AnalysisReport {
        switch request {
        case .numericDistribution(let column, let binCount):
            let distribution = try document.numericDistribution(column: column, binCount: binCount, cancellation: cancellation)
            return numericDistributionReport(distribution, columnNames: columnNames, provenance: provenance)
        case .dateHistogram(let dateColumn, let valueColumn, let period):
            let histogram = try document.dateHistogram(dateColumn: dateColumn, valueColumn: valueColumn, period: period, cancellation: cancellation)
            return dateHistogramReport(histogram, columnNames: columnNames, provenance: provenance)
        case .duplicateRows(let columns):
            let duplicates = try document.findDuplicates(columns: columns, cancellation: cancellation)
            return duplicateReport(duplicates, columns: columns, columnNames: columnNames, provenance: provenance)
        case .groupBy(let groupColumns, let valueColumn, let functions):
            let result = try document.groupBy(groupColumns: groupColumns, valueColumn: valueColumn, functions: functions, cancellation: cancellation)
            return groupByReport(result, columnNames: columnNames, provenance: provenance)
        case .correlation(let xColumn, let yColumn):
            let pearson = try document.correlation(xColumn: xColumn, yColumn: yColumn, method: .pearson, cancellation: cancellation)
            let spearman = try document.correlation(xColumn: xColumn, yColumn: yColumn, method: .spearman, cancellation: cancellation)
            return correlationReport(pearson: pearson, spearman: spearman, xColumn: xColumn, yColumn: yColumn, columnNames: columnNames, provenance: provenance)
        case .independentTTest(let groupColumn, let valueColumn, let groupA, let groupB):
            let result = try document.independentTTest(groupColumn: groupColumn, valueColumn: valueColumn, groupA: groupA, groupB: groupB, cancellation: cancellation)
            return tTestReport(result, groupColumn: groupColumn, valueColumn: valueColumn, columnNames: columnNames, provenance: provenance)
        case .chiSquare(let rowColumn, let columnColumn):
            let result = try document.chiSquareTest(rowColumn: rowColumn, columnColumn: columnColumn, cancellation: cancellation)
            return chiSquareReport(result, rowColumn: rowColumn, columnColumn: columnColumn, columnNames: columnNames, provenance: provenance)
        case .descriptiveStatistics(let columns):
            let batch = try document.descriptiveStatisticsBatch(columns: columns, cancellation: cancellation)
            let results = columns.compactMap { column in batch[column].map { (column, $0) } }
            return descriptiveStatisticsReport(results, columnNames: columnNames, provenance: provenance)
        case .frequencyAnalysis(let column):
            let result = try document.frequencyAnalysis(column: column, blankLabel: L.t("(Blank)", "(빈 값)"), limit: 200, cancellation: cancellation)
            return frequencyAnalysisReport(result, column: column, columnNames: columnNames, provenance: provenance)
        case .oneWayAnova(let groupColumn, let valueColumn):
            let result = try document.oneWayAnova(groupColumn: groupColumn, valueColumn: valueColumn, cancellation: cancellation)
            return oneWayAnovaReport(result, groupColumn: groupColumn, valueColumn: valueColumn, columnNames: columnNames, provenance: provenance)
        case .normalityTest(let column):
            let result = try document.shapiroWilk(column: column, cancellation: cancellation)
            return normalityReport(result, column: column, columnNames: columnNames, provenance: provenance)
        case .documentSummary:
            return documentSummaryReport(document: document, columnNames: columnNames, columnStatisticsReport: columnStatisticsReport, provenance: provenance)
        }
    }

    private static func numericDistributionReport(_ distribution: NumericDistribution, columnNames: [String], provenance: AnalysisProvenance) -> AnalysisReport {
        let name = columnName(distribution.column, columnNames: columnNames)
        return AnalysisReport(
            title: AnalysisKind.numericDistribution.title,
            summary: L.t("Distribution for \(name), \(distribution.count.formatted()) numeric values.", "\(name)의 분포, 숫자 값 \(distribution.count.formatted())개."),
            provenance: provenance,
            sections: [
                .metrics(title: L.t("Summary", "요약"), rows: [
                    AnalysisMetric(name: "Count", value: distribution.count.formatted()),
                    AnalysisMetric(name: "Min", value: formatNumber(distribution.min)),
                    AnalysisMetric(name: "Q1", value: formatNumber(distribution.q1)),
                    AnalysisMetric(name: "Median", value: formatNumber(distribution.median)),
                    AnalysisMetric(name: "Q3", value: formatNumber(distribution.q3)),
                    AnalysisMetric(name: "Max", value: formatNumber(distribution.max)),
                    AnalysisMetric(name: "Mean", value: formatNumber(distribution.mean)),
                    AnalysisMetric(name: "Std", value: formatNumber(distribution.standardDeviation))
                ]),
                .table(AnalysisTable(
                    title: L.t("Histogram", "히스토그램"),
                    headers: [L.t("From", "시작"), L.t("To", "끝"), "Count"],
                    rows: distribution.bins.map { [formatNumber($0.lowerBound), formatNumber($0.upperBound), $0.count.formatted()] },
                    truncated: false
                ))
            ]
        )
    }

    private static func dateHistogramReport(_ histogram: DateHistogram, columnNames: [String], provenance: AnalysisProvenance) -> AnalysisReport {
        let name = columnName(histogram.dateColumn, columnNames: columnNames)
        let hasValue = histogram.valueColumn != nil
        return AnalysisReport(
            title: AnalysisKind.dateHistogram.title,
            summary: L.t("\(histogram.bins.count.formatted()) \(histogram.period.rawValue.lowercased()) bins for \(name).", "\(name)의 \(histogram.period.rawValue) 구간 \(histogram.bins.count.formatted())개."),
            provenance: provenance,
            sections: [
                .table(AnalysisTable(
                    title: L.t("Bins", "구간"),
                    headers: hasValue ? [L.t("Period", "기간"), "Count", "Sum", "Average"] : [L.t("Period", "기간"), "Count"],
                    rows: histogram.bins.map { bin in
                        hasValue
                            ? [bin.label, bin.count.formatted(), formatNumber(bin.sum ?? 0), formatNumber(bin.average ?? 0)]
                            : [bin.label, bin.count.formatted()]
                    },
                    truncated: false
                ))
            ]
        )
    }

    private static func duplicateReport(_ duplicates: [DuplicateGroup], columns: [Int], columnNames: [String], provenance: AnalysisProvenance) -> AnalysisReport {
        let rows = duplicates.prefix(100).map { group in
            [group.key.joined(separator: " | "), group.sourceRows.map { $0.formatted() }.joined(separator: ", ")]
        }
        return AnalysisReport(
            title: AnalysisKind.duplicateRows.title,
            summary: L.t("Found \(duplicates.count.formatted()) duplicate groups.", "중복 그룹 \(duplicates.count.formatted())개를 찾았습니다."),
            provenance: provenance,
            sections: [
                .table(AnalysisTable(
                    title: columns.map { columnName($0, columnNames: columnNames) }.joined(separator: " + "),
                    headers: [L.t("Key", "키"), L.t("Source rows", "원본 행")],
                    rows: rows,
                    truncated: duplicates.count > rows.count
                ))
            ]
        )
    }

    private static func groupByReport(_ result: GroupByResult, columnNames: [String], provenance: AnalysisProvenance) -> AnalysisReport {
        let headers = [L.t("Group", "그룹")] + result.functions.map(\.rawValue)
        let rows = result.rows.prefix(100).map { row in
            [row.key.joined(separator: " | ")] + result.functions.map { formatNumber(row.values[$0] ?? 0) }
        }
        return AnalysisReport(
            title: AnalysisKind.groupBy.title,
            summary: L.t("\(result.rows.count.formatted()) groups.", "그룹 \(result.rows.count.formatted())개."),
            provenance: provenance,
            sections: [
                .table(AnalysisTable(
                    title: L.t("Grouped Results", "그룹 결과"),
                    headers: headers,
                    rows: rows,
                    truncated: result.rows.count > rows.count
                ))
            ]
        )
    }

    private static func correlationReport(pearson: CorrelationResult, spearman: CorrelationResult, xColumn: Int, yColumn: Int, columnNames: [String], provenance: AnalysisProvenance) -> AnalysisReport {
        let xName = columnName(xColumn, columnNames: columnNames)
        let yName = columnName(yColumn, columnNames: columnNames)
        return AnalysisReport(
            title: AnalysisKind.correlation.title,
            summary: "\(xName) vs \(yName)",
            provenance: provenance,
            sections: [
                .metrics(title: L.t("Statistics", "통계"), rows: [
                    AnalysisMetric(name: "Pearson r", value: formatNumber(pearson.coefficient)),
                    AnalysisMetric(name: "Pearson p-value", value: formatNumber(pearson.pValue)),
                    AnalysisMetric(name: "Pearson", value: pearson.interpretation),
                    AnalysisMetric(name: "Spearman rho", value: formatNumber(spearman.coefficient)),
                    AnalysisMetric(name: "Spearman p-value", value: formatNumber(spearman.pValue)),
                    AnalysisMetric(name: "Spearman", value: spearman.interpretation),
                    AnalysisMetric(name: "n", value: pearson.sampleSize.formatted())
                ])
            ]
        )
    }

    private static func tTestReport(_ result: IndependentTTestResult, groupColumn: Int, valueColumn: Int, columnNames: [String], provenance: AnalysisProvenance) -> AnalysisReport {
        let valueName = columnName(valueColumn, columnNames: columnNames)
        let groupName = columnName(groupColumn, columnNames: columnNames)
        return AnalysisReport(
            title: AnalysisKind.independentTTest.title,
            summary: "\(valueName) by \(groupName)",
            provenance: provenance,
            sections: [
                .metrics(title: L.t("Statistics", "통계"), rows: [
                    AnalysisMetric(name: "\(result.groupA) mean", value: formatNumber(result.meanA)),
                    AnalysisMetric(name: "\(result.groupB) mean", value: formatNumber(result.meanB)),
                    AnalysisMetric(name: "t", value: formatNumber(result.tStatistic)),
                    AnalysisMetric(name: "df", value: formatNumber(result.degreesOfFreedom)),
                    AnalysisMetric(name: "p-value", value: formatNumber(result.pValue)),
                    AnalysisMetric(name: "95% CI", value: "\(formatNumber(result.confidenceIntervalLow)) to \(formatNumber(result.confidenceIntervalHigh))"),
                    AnalysisMetric(name: "Effect size", value: formatNumber(result.effectSize)),
                    AnalysisMetric(name: L.t("Interpretation", "해석"), value: result.interpretation)
                ])
            ]
        )
    }

    private static func chiSquareReport(_ result: ChiSquareResult, rowColumn: Int, columnColumn: Int, columnNames: [String], provenance: AnalysisProvenance) -> AnalysisReport {
        let rowName = columnName(rowColumn, columnNames: columnNames)
        let columnNameText = columnName(columnColumn, columnNames: columnNames)
        let rows = result.rowLabels.enumerated().map { index, rowLabel in
            [rowLabel] + result.observed[index].map { formatNumber($0) }
        }
        return AnalysisReport(
            title: AnalysisKind.chiSquare.title,
            summary: "\(rowName) x \(columnNameText)",
            provenance: provenance,
            sections: [
                .metrics(title: L.t("Statistics", "통계"), rows: [
                    AnalysisMetric(name: "Chi-square", value: formatNumber(result.statistic)),
                    AnalysisMetric(name: "df", value: result.degreesOfFreedom.formatted()),
                    AnalysisMetric(name: "p-value", value: formatNumber(result.pValue)),
                    AnalysisMetric(name: L.t("Interpretation", "해석"), value: result.interpretation)
                ]),
                .table(AnalysisTable(
                    title: L.t("Observed Counts", "관측 빈도"),
                    headers: [rowName] + result.columnLabels,
                    rows: rows,
                    truncated: false
                ))
            ]
        )
    }

    private static func documentSummaryReport(document: VirtualCsvDocument, columnNames: [String], columnStatisticsReport: ColumnStatisticsReport?, provenance: AnalysisProvenance) -> AnalysisReport {
        var sections: [AnalysisSection] = [
            .metrics(title: L.t("Document", "문서"), rows: [
                AnalysisMetric(name: L.t("Rows", "행"), value: "\(document.displayRowCount.formatted()) / \(document.dataRowsAvailable.formatted())"),
                AnalysisMetric(name: L.t("Columns", "컬럼"), value: columnNames.count.formatted()),
                AnalysisMetric(name: L.t("File size", "파일 크기"), value: ByteCountFormatter.string(fromByteCount: document.fileLength, countStyle: .file)),
                AnalysisMetric(name: L.t("Encoding", "인코딩"), value: document.encodingName),
                AnalysisMetric(name: L.t("Storage", "저장 방식"), value: document.inMemory ? "RAM" : "Disk")
            ])
        ]
        if let columnStatisticsReport {
            sections.append(.table(AnalysisTable(
                title: L.t("Columns", "컬럼"),
                headers: [L.t("Column", "컬럼"), L.t("Type", "타입"), L.t("Non-null", "Non-null"), L.t("Unique", "고유값")],
                rows: columnStatisticsReport.columns.map {
                    [$0.name, $0.inferredType.rawValue, $0.nonNullCount.formatted(), $0.uniqueCount.formatted()]
                },
                truncated: false
            )))
        }
        return AnalysisReport(
            title: AnalysisKind.documentSummary.title,
            summary: L.t("Document-wide summary of the current CSV.", "현재 CSV의 문서 단위 요약입니다."),
            provenance: provenance,
            sections: sections
        )
    }

    private static func descriptiveStatisticsReport(_ results: [(Int, DescriptiveStatisticsResult)], columnNames: [String], provenance: AnalysisProvenance) -> AnalysisReport {
        let names = results.map { columnName($0.0, columnNames: columnNames) }
        let statRows: [(String, (DescriptiveStatisticsResult) -> String)] = [
            ("N", { $0.count.formatted() }),
            (L.t("Missing", "결측"), { $0.missingCount.formatted() }),
            (L.t("Mean", "평균"), { formatNumber($0.mean) }),
            (L.t("Std Dev", "표준편차"), { formatNumber($0.standardDeviation) }),
            (L.t("Std Error", "표준오차"), { formatNumber($0.standardError) }),
            ("95% CI", { "\(formatNumber($0.confidenceIntervalLow)) ~ \(formatNumber($0.confidenceIntervalHigh))" }),
            ("Min", { formatNumber($0.minimum) }),
            ("Q1", { formatNumber($0.quartile1) }),
            (L.t("Median", "중앙값"), { formatNumber($0.median) }),
            ("Q3", { formatNumber($0.quartile3) }),
            ("Max", { formatNumber($0.maximum) }),
            (L.t("Range", "범위"), { formatNumber($0.range) }),
            ("IQR", { formatNumber($0.interquartileRange) }),
            (L.t("Mode", "최빈값"), { $0.modes.isEmpty ? "-" : $0.modes.prefix(3).map(formatNumber).joined(separator: ", ") }),
            (L.t("Skewness", "왜도"), { formatNumber($0.skewness) }),
            (L.t("Kurtosis", "첨도"), { formatNumber($0.excessKurtosis) }),
            ("CV", { formatNumber($0.coefficientOfVariation) })
        ]
        let rows = statRows.map { name, extract in
            [name] + results.map { extract($0.1) }
        }
        return AnalysisReport(
            title: AnalysisKind.descriptiveStatistics.title,
            summary: L.t("Descriptive statistics for \(names.joined(separator: ", ")).", "\(names.joined(separator: ", "))의 기술통계입니다."),
            provenance: provenance,
            sections: [
                .table(AnalysisTable(
                    title: L.t("Statistics", "통계"),
                    headers: [L.t("Statistic", "통계량")] + names,
                    rows: rows,
                    truncated: false
                ))
            ]
        )
    }

    private static func frequencyAnalysisReport(_ result: FrequencyAnalysisResult, column: Int, columnNames: [String], provenance: AnalysisProvenance) -> AnalysisReport {
        let name = columnName(column, columnNames: columnNames)
        return AnalysisReport(
            title: AnalysisKind.frequencyAnalysis.title,
            summary: L.t("\(result.distinctCount.formatted()) distinct values in \(name).", "\(name)의 고유값 \(result.distinctCount.formatted())개."),
            provenance: provenance,
            sections: [
                .table(AnalysisTable(
                    title: name,
                    headers: [L.t("Value", "값"), L.t("Count", "빈도"), "%", L.t("Cumulative %", "누적 %")],
                    rows: result.entries.map {
                        [$0.value, $0.count.formatted(), formatNumber($0.percent), formatNumber($0.cumulativePercent)]
                    },
                    truncated: result.entries.count < result.distinctCount
                ))
            ]
        )
    }

    private static func oneWayAnovaReport(_ result: OneWayAnovaResult, groupColumn: Int, valueColumn: Int, columnNames: [String], provenance: AnalysisProvenance) -> AnalysisReport {
        let valueName = columnName(valueColumn, columnNames: columnNames)
        let groupName = columnName(groupColumn, columnNames: columnNames)
        return AnalysisReport(
            title: AnalysisKind.oneWayAnova.title,
            summary: "\(valueName) by \(groupName)",
            provenance: provenance,
            sections: [
                .metrics(title: L.t("Statistics", "통계"), rows: [
                    AnalysisMetric(name: "F", value: formatNumber(result.fStatistic)),
                    AnalysisMetric(name: "df", value: "\(result.degreesOfFreedomBetween), \(result.degreesOfFreedomWithin)"),
                    AnalysisMetric(name: "p-value", value: formatPValue(result.pValue)),
                    AnalysisMetric(name: "Eta-squared", value: formatNumber(result.etaSquared)),
                    AnalysisMetric(name: L.t("Interpretation", "해석"), value: result.interpretation)
                ]),
                .table(AnalysisTable(
                    title: L.t("Groups", "그룹"),
                    headers: [L.t("Group", "그룹"), "N", L.t("Mean", "평균"), L.t("Std Dev", "표준편차")],
                    rows: result.groups.map {
                        [$0.name, $0.count.formatted(), formatNumber($0.mean), formatNumber($0.standardDeviation)]
                    },
                    truncated: false
                ))
            ]
        )
    }

    private static func normalityReport(_ result: ShapiroWilkResult, column: Int, columnNames: [String], provenance: AnalysisProvenance) -> AnalysisReport {
        let name = columnName(column, columnNames: columnNames)
        var metrics = [
            AnalysisMetric(name: "W", value: String(format: "%.5f", result.wStatistic)),
            AnalysisMetric(name: "p-value", value: formatPValue(result.pValue)),
            AnalysisMetric(name: "n", value: result.sampleSize.formatted()),
            AnalysisMetric(name: L.t("Interpretation", "해석"), value: result.interpretation)
        ]
        if result.sampleSize > 5_000 {
            metrics.append(AnalysisMetric(
                name: L.t("Note", "참고"),
                value: L.t("p-value approximation is less accurate above n = 5000.", "n이 5000을 넘으면 p값 근사의 정확도가 떨어집니다.")
            ))
        }
        return AnalysisReport(
            title: AnalysisKind.normalityTest.title,
            summary: name,
            provenance: provenance,
            sections: [.metrics(title: L.t("Statistics", "통계"), rows: metrics)]
        )
    }

    private static func formatPValue(_ value: Double) -> String {
        guard value.isFinite else { return "-" }
        if value != 0, value < 0.001 {
            return String(format: "%.3e", value)
        }
        return String(format: "%.4f", value)
    }

    private static func columnName(_ column: Int, columnNames: [String]) -> String {
        columnNames.indices.contains(column) ? columnNames[column] : L.t("Column \(column + 1)", "\(column + 1)열")
    }

    private static func formatNumber(_ value: Double) -> String {
        if value.rounded(.towardZero) == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.3f", value)
    }
}
