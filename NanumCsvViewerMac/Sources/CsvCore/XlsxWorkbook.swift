import Foundation

public enum XlsxWorkbookError: Error, Equatable {
    case cannotOpen(String)
    case invalidWorkbook(String)
    case sheetNotFound(String)
}

/// Read-only access to Excel .xlsx/.xlsm packages. Sheets are exported to
/// temporary CSV files so the existing CSV engine works unchanged — the same
/// temp-CSV bridge SqliteWorkbook uses.
public enum XlsxWorkbook {
    public static func hasXlsxExtension(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ["xlsx", "xlsm"].contains(ext)
    }

    public static func isXlsxFile(path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4), data.count == 4 else { return false }
        return data[0] == 0x50 && data[1] == 0x4B && data[2] == 0x03 && data[3] == 0x04
    }

    public static func sheetNames(path: String) throws -> [String] {
        try workbookInfo(path: path).sheets.map(\.name)
    }

    /// Exports one sheet to a CSV file and returns the number of rows written.
    @discardableResult
    public static func exportSheetToCsv(
        path: String,
        sheet: String,
        destination: URL,
        cancellation: CancellationFlag = CancellationFlag()
    ) throws -> Int {
        let archive: ZipArchiveReader
        do {
            archive = try ZipArchiveReader(path: path)
        } catch {
            throw XlsxWorkbookError.cannotOpen("\(error)")
        }
        let info = try workbookInfo(archive: archive)
        guard let target = info.sheets.first(where: { $0.name == sheet }) else {
            throw XlsxWorkbookError.sheetNotFound(sheet)
        }
        guard archive.contains(target.entryPath) else {
            throw XlsxWorkbookError.invalidWorkbook("missing worksheet part \(target.entryPath)")
        }

        let sharedStrings = try readSharedStrings(archive: archive)
        let dateStyles = try readDateStyleFlags(archive: archive)
        let sheetData = try archive.read(target.entryPath)

        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        let writer = SheetCsvWriter(
            handle: handle,
            sharedStrings: sharedStrings,
            dateStyles: dateStyles,
            date1904: info.date1904,
            cancellation: cancellation
        )
        let parser = XMLParser(data: sheetData)
        parser.delegate = writer
        guard parser.parse() else {
            if let error = writer.thrownError {
                throw error
            }
            throw XlsxWorkbookError.invalidWorkbook(parser.parserError.map { "\($0)" } ?? "worksheet parse failed")
        }
        if let error = writer.thrownError {
            throw error
        }
        try writer.finish()
        return writer.rowsWritten
    }

    // MARK: - Workbook structure

    struct SheetInfo {
        let name: String
        let entryPath: String
    }

    struct WorkbookInfo {
        let sheets: [SheetInfo]
        let date1904: Bool
    }

    static func workbookInfo(path: String) throws -> WorkbookInfo {
        let archive: ZipArchiveReader
        do {
            archive = try ZipArchiveReader(path: path)
        } catch {
            throw XlsxWorkbookError.cannotOpen("\(error)")
        }
        return try workbookInfo(archive: archive)
    }

    private static func workbookInfo(archive: ZipArchiveReader) throws -> WorkbookInfo {
        guard archive.contains("xl/workbook.xml") else {
            throw XlsxWorkbookError.invalidWorkbook("xl/workbook.xml missing")
        }
        let workbookData = try archive.read("xl/workbook.xml")
        let workbookParserDelegate = WorkbookXmlDelegate()
        let workbookParser = XMLParser(data: workbookData)
        workbookParser.delegate = workbookParserDelegate
        guard workbookParser.parse() else {
            throw XlsxWorkbookError.invalidWorkbook("workbook.xml parse failed")
        }

        var relationshipTargets: [String: String] = [:]
        if archive.contains("xl/_rels/workbook.xml.rels") {
            let relsData = try archive.read("xl/_rels/workbook.xml.rels")
            let relsDelegate = RelationshipsXmlDelegate()
            let relsParser = XMLParser(data: relsData)
            relsParser.delegate = relsDelegate
            guard relsParser.parse() else {
                throw XlsxWorkbookError.invalidWorkbook("workbook.xml.rels parse failed")
            }
            relationshipTargets = relsDelegate.targets
        }

        let sheets = workbookParserDelegate.sheets.enumerated().map { index, sheet -> SheetInfo in
            let target = sheet.relationshipId.flatMap { relationshipTargets[$0] }
                ?? "worksheets/sheet\(index + 1).xml"
            let normalized: String
            if target.hasPrefix("/") {
                normalized = String(target.dropFirst())
            } else {
                normalized = "xl/" + target
            }
            return SheetInfo(name: sheet.name, entryPath: normalized)
        }
        guard !sheets.isEmpty else {
            throw XlsxWorkbookError.invalidWorkbook("workbook has no sheets")
        }
        return WorkbookInfo(sheets: sheets, date1904: workbookParserDelegate.date1904)
    }

    private static func readSharedStrings(archive: ZipArchiveReader) throws -> [String] {
        guard archive.contains("xl/sharedStrings.xml") else { return [] }
        let data = try archive.read("xl/sharedStrings.xml")
        let delegate = SharedStringsXmlDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw XlsxWorkbookError.invalidWorkbook("sharedStrings.xml parse failed")
        }
        return delegate.strings
    }

    /// Per-cellXf flags: true when the style's number format renders dates.
    private static func readDateStyleFlags(archive: ZipArchiveReader) throws -> [Bool] {
        guard archive.contains("xl/styles.xml") else { return [] }
        let data = try archive.read("xl/styles.xml")
        let delegate = StylesXmlDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw XlsxWorkbookError.invalidWorkbook("styles.xml parse failed")
        }
        return delegate.cellFormatIsDate
    }

    static func isBuiltinDateFormat(_ id: Int) -> Bool {
        (14...22).contains(id) || (45...47).contains(id)
    }

    static func customFormatLooksLikeDate(_ code: String) -> Bool {
        var stripped = ""
        var inBracket = false
        var inQuote = false
        for character in code {
            switch character {
            case "[" where !inQuote:
                inBracket = true
            case "]" where !inQuote:
                inBracket = false
            case "\"":
                inQuote.toggle()
            default:
                if !inBracket && !inQuote {
                    stripped.append(character)
                }
            }
        }
        let lowered = stripped.lowercased()
        return lowered.contains("y") || lowered.contains("d")
            || (lowered.contains("m") && (lowered.contains("h") || lowered.contains("s")))
    }

    static func dateString(fromSerial serial: Double, date1904: Bool) -> String {
        // Excel's 1900 epoch is 1899-12-30 once the phantom Feb 29, 1900 is
        // absorbed; the 1904 system starts at 1904-01-01.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let epochComponents = date1904
            ? DateComponents(year: 1904, month: 1, day: 1)
            : DateComponents(year: 1899, month: 12, day: 30)
        guard let epoch = calendar.date(from: epochComponents) else { return "\(serial)" }
        let date = epoch.addingTimeInterval(serial * 86_400)
        let fraction = serial - serial.rounded(.down)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = fraction > 1e-9 ? "yyyy-MM-dd HH:mm:ss" : "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func columnIndex(fromReference reference: String) -> Int? {
        var value = 0
        var sawLetter = false
        for character in reference {
            guard let ascii = character.asciiValue else { return nil }
            if ascii >= 65, ascii <= 90 {
                value = value * 26 + Int(ascii - 64)
                sawLetter = true
            } else if ascii >= 97, ascii <= 122 {
                value = value * 26 + Int(ascii - 96)
                sawLetter = true
            } else {
                break
            }
        }
        return sawLetter ? value - 1 : nil
    }

    static func csvEscaped(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}

// MARK: - XML delegates

private final class WorkbookXmlDelegate: NSObject, XMLParserDelegate {
    struct Sheet {
        let name: String
        let relationshipId: String?
    }

    var sheets: [Sheet] = []
    var date1904 = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        switch elementName {
        case "sheet":
            let name = attributes["name"] ?? "Sheet\(sheets.count + 1)"
            sheets.append(Sheet(name: name, relationshipId: attributes["r:id"] ?? attributes["id"]))
        case "workbookPr":
            date1904 = attributes["date1904"] == "1" || attributes["date1904"]?.lowercased() == "true"
        default:
            break
        }
    }
}

private final class RelationshipsXmlDelegate: NSObject, XMLParserDelegate {
    var targets: [String: String] = [:]

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        guard elementName == "Relationship",
              let id = attributes["Id"],
              let target = attributes["Target"] else { return }
        targets[id] = target
    }
}

private final class SharedStringsXmlDelegate: NSObject, XMLParserDelegate {
    var strings: [String] = []
    private var current = ""
    private var insideItem = false
    private var insideText = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        switch elementName {
        case "si":
            insideItem = true
            current = ""
        case "t" where insideItem:
            insideText = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideText {
            current += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        switch elementName {
        case "t":
            insideText = false
        case "si":
            insideItem = false
            strings.append(current)
        default:
            break
        }
    }
}

private final class StylesXmlDelegate: NSObject, XMLParserDelegate {
    var cellFormatIsDate: [Bool] = []
    private var customDateFormatIds: Set<Int> = []
    private var insideCellXfs = false
    private var pendingCellXfNumFmtIds: [Int] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        switch elementName {
        case "numFmt":
            if let idText = attributes["numFmtId"], let id = Int(idText),
               let code = attributes["formatCode"],
               XlsxWorkbook.customFormatLooksLikeDate(code) {
                customDateFormatIds.insert(id)
            }
        case "cellXfs":
            insideCellXfs = true
        case "xf" where insideCellXfs:
            pendingCellXfNumFmtIds.append(attributes["numFmtId"].flatMap(Int.init) ?? 0)
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        guard elementName == "cellXfs" else { return }
        insideCellXfs = false
        cellFormatIsDate = pendingCellXfNumFmtIds.map { id in
            XlsxWorkbook.isBuiltinDateFormat(id) || customDateFormatIds.contains(id)
        }
    }
}

/// Streams `<row>`/`<c>` worksheet elements straight into a CSV file. Rows are
/// padded to the widest row seen so far, and skipped row numbers become empty
/// rows so the CSV keeps the sheet's vertical alignment.
private final class SheetCsvWriter: NSObject, XMLParserDelegate {
    private let handle: FileHandle
    private let sharedStrings: [String]
    private let dateStyles: [Bool]
    private let date1904: Bool
    private let cancellation: CancellationFlag

    private var currentRowNumber = 0
    private var lastWrittenRowNumber = 0
    private var maxColumnCount = 0
    private var rowValues: [String] = []
    private var cellColumn = 0
    private var cellType = ""
    private var cellStyle = -1
    private var textBuffer = ""
    private var capturingValue = false
    private var insideInlineString = false

    private(set) var rowsWritten = 0
    private(set) var thrownError: Error?

    init(
        handle: FileHandle,
        sharedStrings: [String],
        dateStyles: [Bool],
        date1904: Bool,
        cancellation: CancellationFlag
    ) {
        self.handle = handle
        self.sharedStrings = sharedStrings
        self.dateStyles = dateStyles
        self.date1904 = date1904
        self.cancellation = cancellation
    }

    func finish() throws {
        try handle.synchronize()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        switch elementName {
        case "row":
            currentRowNumber = attributes["r"].flatMap(Int.init) ?? (lastWrittenRowNumber + 1)
            rowValues = []
        case "c":
            cellColumn = attributes["r"].flatMap(XlsxWorkbook.columnIndex(fromReference:)) ?? rowValues.count
            cellType = attributes["t"] ?? ""
            cellStyle = attributes["s"].flatMap(Int.init) ?? -1
            textBuffer = ""
        case "is":
            insideInlineString = true
        case "v", "t":
            if elementName == "v" || insideInlineString {
                capturingValue = true
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturingValue {
            textBuffer += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        switch elementName {
        case "v", "t":
            capturingValue = false
        case "is":
            insideInlineString = false
        case "c":
            storeCurrentCell()
        case "row":
            emitCurrentRow(parser: parser)
        default:
            break
        }
    }

    private func storeCurrentCell() {
        let value: String
        switch cellType {
        case "s":
            let index = Int(textBuffer.trimmingCharacters(in: .whitespaces)) ?? -1
            value = sharedStrings.indices.contains(index) ? sharedStrings[index] : ""
        case "b":
            value = textBuffer.trimmingCharacters(in: .whitespaces) == "1" ? "TRUE" : "FALSE"
        case "inlineStr", "str", "e":
            value = textBuffer
        default:
            let trimmed = textBuffer.trimmingCharacters(in: .whitespaces)
            if cellStyle >= 0, dateStyles.indices.contains(cellStyle), dateStyles[cellStyle],
               let serial = Double(trimmed), serial.isFinite {
                value = XlsxWorkbook.dateString(fromSerial: serial, date1904: date1904)
            } else {
                value = trimmed
            }
        }

        while rowValues.count < cellColumn {
            rowValues.append("")
        }
        if cellColumn < rowValues.count {
            rowValues[cellColumn] = value
        } else {
            rowValues.append(value)
        }
        textBuffer = ""
    }

    private func emitCurrentRow(parser: XMLParser) {
        do {
            try cancellation.check()
            maxColumnCount = max(maxColumnCount, rowValues.count)

            // Fill vertical gaps left by empty rows the XML omits entirely.
            while lastWrittenRowNumber + 1 < currentRowNumber {
                try writeLine([String](repeating: "", count: maxColumnCount))
                lastWrittenRowNumber += 1
            }

            var padded = rowValues
            while padded.count < maxColumnCount {
                padded.append("")
            }
            try writeLine(padded)
            lastWrittenRowNumber = currentRowNumber
        } catch {
            thrownError = error
            parser.abortParsing()
        }
    }

    private func writeLine(_ fields: [String]) throws {
        let line = fields.map(XlsxWorkbook.csvEscaped).joined(separator: ",") + "\n"
        try handle.write(contentsOf: Data(line.utf8))
        rowsWritten += 1
    }
}
