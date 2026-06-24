import Foundation

public final class VirtualCsvDocument: @unchecked Sendable {
    public static var ramBufferBudgetBytes: Int64 {
        let physical = Int64(ProcessInfo.processInfo.physicalMemory)
        return min(max(1_500_000_000, physical / 4), 8_000_000_000)
    }

    private static var rowCacheCapacity: Int {
        let physical = ProcessInfo.processInfo.physicalMemory
        if physical >= 32 * 1_024 * 1_024 * 1_024 { return 65_536 }
        if physical >= 16 * 1_024 * 1_024 * 1_024 { return 32_768 }
        return 8_192
    }
    private static let readUnit = MemoryFileBuffer.chunkSize
    private static let maxRecoveredHeaderEmbeddedLineBreaks = 4

    private let path: String
    private let index = RecordIndex()
    private let cache = RowCache(capacity: rowCacheCapacity)
    private let diskSource: RandomByteSource
    private let ramBufferPending: MemoryFileBuffer?

    private let stateLock = NSLock()
    private let viewLock = NSLock()
    private let sourceLock = NSLock()

    private var encoding: String.Encoding
    private let preamble: Int
    private var delimiterByte: UInt8 = UInt8(ascii: ",")
    private var headerStart: Int64 = 0
    private var headerEnd: Int64 = 0
    private var viewMap: [Int]?
    private var ramBuffer: MemoryFileBuffer?
    private var indexingCompleteValue = false
    private var recoverMalformedHeader = false

    public let fileLength: Int64
    public private(set) var header: [String] = []
    public private(set) var encodingName: String
    public let willUseRam: Bool

    public var columnCount: Int { header.count }
    public var delimiter: Character { Character(UnicodeScalar(delimiterByte)) }
    public var inMemory: Bool {
        sourceLock.lock()
        defer { sourceLock.unlock() }
        return ramBuffer != nil
    }

    public var indexingComplete: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return indexingCompleteValue
    }

    public var isFiltered: Bool {
        viewLock.lock()
        defer { viewLock.unlock() }
        return viewMap != nil
    }

    private init(path: String, detection: EncodingDetectionResult) throws {
        self.path = path
        encoding = detection.encoding
        preamble = detection.preambleLength
        encodingName = detection.displayName
        if let mapped = try? MappedFileByteSource(path: path) {
            diskSource = mapped
        } else {
            diskSource = try FileByteSource(path: path)
        }
        fileLength = diskSource.length
        willUseRam = fileLength <= Self.ramBufferBudgetBytes
        ramBufferPending = willUseRam ? MemoryFileBuffer(length: fileLength) : nil
    }

    deinit {
        (diskSource as? ClosableByteSource)?.close()
    }

    public static func open(path: String) throws -> VirtualCsvDocument {
        let detection = try EncodingDetector.detect(path: path)
        if !detection.isByteIndexable {
            throw CsvError.unsupportedEncoding(detection.displayName)
        }
        let document = try VirtualCsvDocument(path: path, detection: detection)
        try document.initialize()
        return document
    }

    private func initialize() throws {
        let sampleLength = Int(min(Int64(1 << 20), fileLength))
        let sample = try diskSource.readData(offset: 0, length: sampleLength)
        delimiterByte = Self.detectDelimiter(in: sample, preamble: preamble)

        let tmp = RecordIndex()
        let probe = CsvRecordIndexer(index: tmp, fileLength: fileLength, delimiter: delimiterByte, firstRecordStart: Int64(preamble))
        probe.processBuffer(sample, baseOffset: 0)
        tmp.publish()

        headerStart = Int64(preamble)
        let strictHeaderEnd = tmp.count >= 2 ? tmp[1] : min(Int64(sampleLength), fileLength)
        let physicalHeaderEnd = Self.firstPhysicalLineEnd(in: sample, preamble: preamble, fileLength: fileLength)
        recoverMalformedHeader = Self.shouldRecoverMalformedHeader(
            sample: sample,
            preamble: preamble,
            strictHeaderEnd: strictHeaderEnd,
            physicalHeaderEnd: physicalHeaderEnd
        )
        headerEnd = recoverMalformedHeader ? physicalHeaderEnd : strictHeaderEnd
        header = try decodeAndParse(start: headerStart, end: headerEnd, repairUnbalancedQuotes: recoverMalformedHeader)
    }

    private static func detectDelimiter(in sample: Data, preamble: Int) -> UInt8 {
        let candidates: [UInt8] = [UInt8(ascii: ","), UInt8(ascii: ";"), UInt8(ascii: "\t"), UInt8(ascii: "|")]
        var counts = Array(repeating: 0, count: candidates.count)
        var inQuotes = false
        let quote = UInt8(ascii: "\"")

        sample.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            var i = min(preamble, raw.count)
            while i < raw.count {
                let b = base[i]
                if b == quote {
                    inQuotes.toggle()
                    i += 1
                    continue
                }
                if inQuotes {
                    i += 1
                    continue
                }
                if b == 0x0A || b == 0x0D { break }
                for c in candidates.indices where b == candidates[c] {
                    counts[c] += 1
                }
                i += 1
            }
        }

        var best = 0
        for i in 1..<counts.count where counts[i] > counts[best] {
            best = i
        }
        return counts[best] > 0 ? candidates[best] : UInt8(ascii: ",")
    }

    private static func firstPhysicalLineEnd(in sample: Data, preamble: Int, fileLength: Int64) -> Int64 {
        sample.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else {
                return min(Int64(sample.count), fileLength)
            }
            var i = min(preamble, raw.count)
            while i < raw.count {
                let byte = base[i]
                if byte == 0x0A {
                    return Int64(i + 1)
                }
                if byte == 0x0D {
                    if i + 1 < raw.count, base[i + 1] == 0x0A {
                        return Int64(i + 2)
                    }
                    return Int64(i + 1)
                }
                i += 1
            }
            return min(Int64(sample.count), fileLength)
        }
    }

    private static func shouldRecoverMalformedHeader(sample: Data, preamble: Int, strictHeaderEnd: Int64, physicalHeaderEnd: Int64) -> Bool {
        guard strictHeaderEnd > physicalHeaderEnd else { return false }
        guard hasUnbalancedQuotes(in: sample, start: preamble, end: Int(min(physicalHeaderEnd, Int64(sample.count)))) else {
            return false
        }
        let lineBreaks = physicalLineBreakCount(in: sample, start: preamble, end: Int(min(strictHeaderEnd, Int64(sample.count))))
        return lineBreaks > maxRecoveredHeaderEmbeddedLineBreaks
    }

    private static func physicalLineBreakCount(in sample: Data, start: Int, end: Int) -> Int {
        sample.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            var count = 0
            var i = max(0, min(start, raw.count))
            let upper = max(i, min(end, raw.count))
            while i < upper {
                let byte = base[i]
                if byte == 0x0A {
                    count += 1
                } else if byte == 0x0D {
                    count += 1
                    if i + 1 < upper, base[i + 1] == 0x0A {
                        i += 1
                    }
                }
                i += 1
            }
            return count
        }
    }

    private static func hasUnbalancedQuotes(in sample: Data, start: Int, end: Int) -> Bool {
        sample.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return false }
            var quoteCount = 0
            var i = max(0, min(start, raw.count))
            let upper = max(i, min(end, raw.count))
            while i < upper {
                if base[i] == UInt8(ascii: "\"") {
                    if i + 1 < upper, base[i + 1] == UInt8(ascii: "\"") {
                        i += 2
                        continue
                    }
                    quoteCount += 1
                }
                i += 1
            }
            return quoteCount % 2 == 1
        }
    }

    private static func hasUnbalancedQuotes(_ line: String) -> Bool {
        let scalars = Array(line.unicodeScalars)
        let quote = UnicodeScalar(UInt8(ascii: "\""))
        var quoteCount = 0
        var i = 0
        while i < scalars.count {
            if scalars[i] == quote {
                if i + 1 < scalars.count, scalars[i + 1] == quote {
                    i += 2
                    continue
                }
                quoteCount += 1
            }
            i += 1
        }
        return quoteCount % 2 == 1
    }

    private static func parseLineIgnoringQuotes(_ line: String, delimiter: Character) -> [String] {
        var fields: [String] = []
        var current = ""
        for character in line {
            if character == delimiter {
                fields.append(current)
                current = ""
            } else if character != "\"" {
                current.append(character)
            }
        }
        fields.append(current)
        return fields
    }

    private func runParallelSimpleIndexing(progress: @escaping (IndexProgress) -> Void, cancellation: CancellationFlag) throws -> Bool {
        guard fileLength > Int64(preamble) else {
            markIndexingComplete()
            progress(IndexProgress(bytesProcessed: fileLength, fileLength: fileLength, rowsSoFar: index.count))
            return true
        }

        let sampleLength = Int(min(Int64(8 * 1_024 * 1_024), fileLength))
        let sample = try diskSource.readData(offset: 0, length: sampleLength)
        if sample.contains(UInt8(ascii: "\"")) {
            return false
        }

        let chunkSize = Int64(Self.readUnit)
        let chunkCount = Int((fileLength + chunkSize - 1) / chunkSize)
        var chunkOffsets = Array<[Int64]?>(repeating: nil, count: chunkCount)
        var chunkData: [Data?] = ramBufferPending == nil ? [] : Array<Data?>(repeating: nil, count: chunkCount)
        var foundQuote = false
        var firstError: Error?
        var completed = 0
        let lock = NSLock()
        let quote = UInt8(ascii: "\"")
        let cr: UInt8 = 0x0D
        let lf: UInt8 = 0x0A

        DispatchQueue.concurrentPerform(iterations: chunkCount) { chunkIndex in
            lock.lock()
            let shouldStop = foundQuote || firstError != nil
            lock.unlock()
            if shouldStop { return }

            do {
                if chunkIndex & 0x3 == 0 { try cancellation.check() }
                let chunkStart = Int64(chunkIndex) * chunkSize
                let chunkLength = min(chunkSize, fileLength - chunkStart)
                let needsLookahead = chunkStart + chunkLength < fileLength
                let data = try diskSource.readData(offset: chunkStart, length: Int(chunkLength + (needsLookahead ? 1 : 0)))
                let scanStart = max(Int64(preamble), chunkStart)
                var offsets: [Int64] = []
                var localFoundQuote = false

                if scanStart < chunkStart + chunkLength {
                    let localStart = Int(scanStart - chunkStart)
                    let localEnd = Int(chunkLength)
                    data.withUnsafeBytes { raw in
                        guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
                        var i = localStart
                        while i < localEnd {
                            let byte = base[i]
                            if byte == quote {
                                localFoundQuote = true
                                return
                            }
                            if byte == lf {
                                let nextOffset = chunkStart + Int64(i) + 1
                                if nextOffset < fileLength {
                                    offsets.append(nextOffset)
                                }
                            } else if byte == cr {
                                let next = i + 1 < raw.count ? base[i + 1] : 0
                                if next != lf {
                                    let nextOffset = chunkStart + Int64(i) + 1
                                    if nextOffset < fileLength {
                                        offsets.append(nextOffset)
                                    }
                                }
                            }
                            i += 1
                        }
                    }
                }

                lock.lock()
                if localFoundQuote {
                    foundQuote = true
                }
                chunkOffsets[chunkIndex] = offsets
                if !chunkData.isEmpty {
                    chunkData[chunkIndex] = data.count == Int(chunkLength) ? data : data.prefix(Int(chunkLength))
                }
                completed += 1
                let done = completed
                lock.unlock()

                if done & 0x3 == 0 || done == chunkCount {
                    let processed = min(fileLength, Int64(done) * chunkSize)
                    progress(IndexProgress(bytesProcessed: processed, fileLength: fileLength, rowsSoFar: 0))
                }
            } catch {
                lock.lock()
                if firstError == nil { firstError = error }
                lock.unlock()
            }
        }

        if let firstError { throw firstError }
        if foundQuote { return false }

        index.add(Int64(preamble))
        for offsets in chunkOffsets {
            for offset in offsets ?? [] {
                index.add(offset)
            }
        }
        index.publish()
        markIndexingComplete()

        if let pending = ramBufferPending {
            for index in chunkData.indices {
                if let data = chunkData[index] {
                    pending.setChunk(data, at: index)
                }
            }
            sourceLock.lock()
            ramBuffer = pending
            sourceLock.unlock()
        }

        progress(IndexProgress(bytesProcessed: fileLength, fileLength: fileLength, rowsSoFar: self.index.count))
        return true
    }

    private func markIndexingComplete() {
        cache.clear()
        stateLock.lock()
        indexingCompleteValue = true
        stateLock.unlock()
    }

    public func runIndexing(progress: @escaping (IndexProgress) -> Void, cancellation: CancellationFlag) throws {
        if recoverMalformedHeader {
            try runMalformedHeaderRecoveryIndexing(progress: progress, cancellation: cancellation)
            return
        }

        if try runParallelSimpleIndexing(progress: progress, cancellation: cancellation) {
            return
        }

        let indexer = CsvRecordIndexer(index: index, fileLength: fileLength, delimiter: delimiterByte, firstRecordStart: Int64(preamble))
        var offset: Int64 = 0
        var chunkIndex = 0
        var lastReport: Int64 = 0

        while offset < fileLength {
            try cancellation.check()
            let length = Int(min(Int64(Self.readUnit), fileLength - offset))
            let chunk = try diskSource.readData(offset: offset, length: length)
            ramBufferPending?.setChunk(chunk, at: chunkIndex)
            indexer.processBuffer(chunk, baseOffset: offset)
            index.publish()

            let processed = offset + Int64(length)
            if processed - lastReport >= Int64(Self.readUnit) || processed >= fileLength {
                lastReport = processed
                progress(IndexProgress(bytesProcessed: processed, fileLength: fileLength, rowsSoFar: index.count))
            }

            offset = processed
            chunkIndex += 1
        }

        index.publish()
        markIndexingComplete()

        if let pending = ramBufferPending {
            sourceLock.lock()
            ramBuffer = pending
            sourceLock.unlock()
        }

        progress(IndexProgress(bytesProcessed: fileLength, fileLength: fileLength, rowsSoFar: index.count))
    }

    private func runMalformedHeaderRecoveryIndexing(progress: @escaping (IndexProgress) -> Void, cancellation: CancellationFlag) throws {
        index.add(headerStart)
        let indexer = CsvRecordIndexer(index: index, fileLength: fileLength, delimiter: delimiterByte, firstRecordStart: headerEnd)
        var offset: Int64 = 0
        var lastReport: Int64 = 0

        while offset < fileLength {
            try cancellation.check()
            let length = Int(min(Int64(Self.readUnit), fileLength - offset))
            let chunk = try diskSource.readData(offset: offset, length: length)
            ramBufferPending?.setChunk(chunk, at: Int(offset / Int64(Self.readUnit)))

            let processed = offset + Int64(length)
            let processStart = max(offset, headerEnd)
            if processStart < processed {
                let localStart = Int(processStart - offset)
                indexer.processBuffer(Data(chunk[localStart..<length]), baseOffset: processStart)
                index.publish()
            }

            if processed - lastReport >= Int64(Self.readUnit) || processed >= fileLength {
                lastReport = processed
                progress(IndexProgress(bytesProcessed: processed, fileLength: fileLength, rowsSoFar: index.count))
            }

            offset = processed
        }

        index.publish()
        markIndexingComplete()

        if let pending = ramBufferPending {
            sourceLock.lock()
            ramBuffer = pending
            sourceLock.unlock()
        }

        progress(IndexProgress(bytesProcessed: fileLength, fileLength: fileLength, rowsSoFar: index.count))
    }

    private var rawDataRowCount: Int64 {
        let rows = indexingComplete ? index.count - 1 : index.count - 2
        return max(0, rows)
    }

    public var rowCountTruncated: Bool {
        rawDataRowCount > Int64(Int32.max)
    }

    public var dataRowsAvailable: Int {
        Int(min(Int64(Int32.max), rawDataRowCount))
    }

    public var displayRowCount: Int {
        viewLock.lock()
        let mapCount = viewMap?.count
        viewLock.unlock()
        return mapCount ?? dataRowsAvailable
    }

    private func viewMapSnapshot() -> [Int]? {
        viewLock.lock()
        defer { viewLock.unlock() }
        return viewMap
    }

    private func setViewMap(_ map: [Int]?) {
        viewLock.lock()
        viewMap = map
        viewLock.unlock()
    }

    private func mapToDataRow(_ viewIndex: Int) -> Int? {
        if let map = viewMapSnapshot() {
            guard viewIndex >= 0 && viewIndex < map.count else { return nil }
            return map[viewIndex]
        }
        return viewIndex >= 0 && viewIndex < dataRowsAvailable ? viewIndex : nil
    }

    public func getDisplayRow(_ viewIndex: Int) throws -> [String] {
        guard let dataRow = mapToDataRow(viewIndex) else { return [""] }
        return try getDataRow(dataRow)
    }

    public func getSourceRowNumber(_ viewIndex: Int) -> Int64 {
        guard let dataRow = mapToDataRow(viewIndex) else { return 0 }
        return Int64(dataRow) + 1
    }

    public func displayIndexForSourceRowNumber(_ sourceRowNumber: Int64) -> Int? {
        guard sourceRowNumber > 0 else { return nil }
        let dataRow = Int(sourceRowNumber - 1)
        if let map = viewMapSnapshot() {
            return map.firstIndex(of: dataRow)
        }
        return dataRow < dataRowsAvailable ? dataRow : nil
    }

    public func cachedDisplayRow(_ viewIndex: Int) -> [String]? {
        guard let dataRow = mapToDataRow(viewIndex) else { return nil }
        return cache.get(dataRow)
    }

    public func prefetchDisplayRows(in range: Range<Int>, cancellation: CancellationFlag) {
        let lower = max(0, range.lowerBound)
        let upper = min(displayRowCount, range.upperBound)
        guard lower < upper else { return }
        for viewRow in lower..<upper {
            do {
                if viewRow & 0x3F == 0 { try cancellation.check() }
                if cachedDisplayRow(viewRow) == nil {
                    _ = try getDisplayRow(viewRow)
                }
            } catch {
                return
            }
        }
    }

    public func getDataRow(_ dataRow: Int) throws -> [String] {
        if let cached = cache.get(dataRow) {
            return cached
        }
        guard let fields = try parseDataRowIfAvailable(dataRow) else {
            return [""]
        }
        cache.add(row: dataRow, fields: fields)
        return fields
    }

    public func getDataRowUncached(_ dataRow: Int) throws -> [String] {
        try parseDataRowIfAvailable(dataRow) ?? [""]
    }

    private func parseDataRowIfAvailable(_ dataRow: Int) throws -> [String]? {
        let record = Int64(dataRow) + 1
        let count = index.count
        guard record >= 1, record < count else { return nil }
        let start = index[record]
        let end = record + 1 < count ? index[record + 1] : fileLength
        guard end > start else { return nil }
        return try decodeAndParse(start: start, end: end)
    }

    private func currentSource() -> RandomByteSource {
        sourceLock.lock()
        let source: RandomByteSource = ramBuffer ?? diskSource
        sourceLock.unlock()
        return source
    }

    private func decodeAndParse(start: Int64, end: Int64, repairUnbalancedQuotes: Bool = false) throws -> [String] {
        let line = try decodeLine(start: start, end: end)
        if repairUnbalancedQuotes, Self.hasUnbalancedQuotes(line) {
            return Self.parseLineIgnoringQuotes(line, delimiter: delimiter)
        }
        return CsvRowParser.parse(line, delimiter: delimiter)
    }

    private func decodeLine(start: Int64, end: Int64) throws -> String {
        let length = Int(end - start)
        guard length > 0 else { return "" }

        let data = try currentSource().readData(offset: start, length: length)
        var trimmedLength = data.count
        data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            while trimmedLength > 0 {
                let last = base[trimmedLength - 1]
                if last != 0x0A, last != 0x0D { break }
                trimmedLength -= 1
            }
        }

        let trimmed = trimmedLength == data.count ? data : data.prefix(trimmedLength)
        return String(data: trimmed, encoding: encoding) ?? String(decoding: trimmed, as: UTF8.self)
    }

    private func dataRowColumnEquals(dataRow: Int, column: Int, encodedValue: Data) throws -> Bool {
        guard let field = try dataRowColumnData(dataRow: dataRow, column: column) else { return false }
        return field == encodedValue
    }

    private func dataRowColumnData(dataRow: Int, column: Int) throws -> Data? {
        let record = Int64(dataRow) + 1
        let count = index.count
        guard record >= 1, record < count else { return nil }
        let start = index[record]
        let end = record + 1 < count ? index[record + 1] : fileLength
        let data = try currentSource().readData(offset: start, length: Int(end - start))
        return Self.csvFieldData(data: data, column: column, delimiter: delimiterByte, quote: UInt8(ascii: "\""))
    }

    private static func csvFieldData(data: Data, column: Int, delimiter: UInt8, quote: UInt8) -> Data? {
        let cr: UInt8 = 0x0D
        let lf: UInt8 = 0x0A

        return data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
            var currentColumn = 0
            var i = 0

            while currentColumn < column, i < raw.count {
                var inQuotes = false
                var atFieldStart = true
                while i < raw.count {
                    let byte = base[i]
                    if atFieldStart, byte == quote {
                        inQuotes = true
                        atFieldStart = false
                        i += 1
                        continue
                    }
                    atFieldStart = false
                    if inQuotes {
                        if byte == quote {
                            if i + 1 < raw.count, base[i + 1] == quote {
                                i += 2
                                continue
                            }
                            inQuotes = false
                        }
                        i += 1
                        continue
                    }
                    if byte == delimiter {
                        currentColumn += 1
                        i += 1
                        break
                    }
                    if byte == cr || byte == lf {
                        return nil
                    }
                    i += 1
                }
            }

            guard currentColumn == column, i < raw.count else { return nil }
            var field = Data()
            field.reserveCapacity(min(128, raw.count - i))
            var inQuotes = false
            var atFieldStart = true

            while i < raw.count {
                let byte = base[i]
                if atFieldStart, byte == quote {
                    inQuotes = true
                    atFieldStart = false
                    i += 1
                    continue
                }
                atFieldStart = false

                if inQuotes {
                    if byte == quote {
                        if i + 1 < raw.count, base[i + 1] == quote {
                            field.append(quote)
                            i += 2
                            continue
                        }
                        inQuotes = false
                        i += 1
                        continue
                    }
                    field.append(byte)
                    i += 1
                    continue
                }

                if byte == delimiter || byte == cr || byte == lf {
                    break
                }
                field.append(byte)
                i += 1
            }

            return field
        }
    }

    public func changeEncoding(to name: String) throws {
        encoding = EncodingDetector.encoding(named: name)
        encodingName = name
        cache.clear()
        header = try decodeAndParse(start: headerStart, end: headerEnd)
    }

    public func analyzeColumns(sampleLimit: Int = 5_000, cancellation: CancellationFlag) throws -> ColumnStatisticsReport {
        let total = min(max(0, sampleLimit), dataRowsAvailable)
        var rows: [[String]] = []
        rows.reserveCapacity(total)
        for row in 0..<total {
            if row & 0x3FFF == 0 { try cancellation.check() }
            rows.append(try getDataRowUncached(row))
        }
        return ColumnStatisticsBuilder.summarize(headers: header, rows: rows)
    }

    public func applyFilter(_ predicate: @escaping ([String]) -> Bool, progress: ((Int) -> Void)?, cancellation: CancellationFlag) throws {
        let total = dataRowsAvailable
        var matches: [Int] = []
        matches.reserveCapacity(min(total, 1 << 16))

        for row in 0..<total {
            if row & 0xFFFF == 0 { try cancellation.check() }
            if predicate(try getDataRowUncached(row)) {
                matches.append(row)
            }
            if row & 0x3FFFF == 0 {
                progress?(total == 0 ? 100 : Int(Int64(row) * 100 / Int64(total)))
            }
        }

        setViewMap(matches)
        progress?(100)
    }

    public func filterWithinView(_ predicate: @escaping ([String]) -> Bool, progress: ((Int) -> Void)?, cancellation: CancellationFlag) throws {
        let baseMap = viewMapSnapshot() ?? Self.identity(dataRowsAvailable)
        var result: [Int] = []
        result.reserveCapacity(min(baseMap.count, 1 << 16))

        for i in baseMap.indices {
            if i & 0xFFFF == 0 { try cancellation.check() }
            let dataRow = baseMap[i]
            if predicate(try getDataRowUncached(dataRow)) {
                result.append(dataRow)
            }
            if i & 0x3FFFF == 0, !baseMap.isEmpty {
                progress?(Int(Int64(i) * 100 / Int64(baseMap.count)))
            }
        }

        setViewMap(result)
        progress?(100)
    }

    public func filterColumnEquals(column: Int, value: String, withinCurrentView: Bool, progress: ((Int) -> Void)?, cancellation: CancellationFlag) throws {
        guard column >= 0, let encodedValue = value.data(using: encoding) else {
            if withinCurrentView {
                try filterWithinView({ fields in column >= 0 && column < fields.count && fields[column] == value }, progress: progress, cancellation: cancellation)
            } else {
                try applyFilter({ fields in column >= 0 && column < fields.count && fields[column] == value }, progress: progress, cancellation: cancellation)
            }
            return
        }

        let baseMap = withinCurrentView ? (viewMapSnapshot() ?? Self.identity(dataRowsAvailable)) : Self.identity(dataRowsAvailable)
        var result: [Int] = []
        result.reserveCapacity(min(baseMap.count, 1 << 16))

        for i in baseMap.indices {
            if i & 0xFFFF == 0 { try cancellation.check() }
            let dataRow = baseMap[i]
            if try dataRowColumnEquals(dataRow: dataRow, column: column, encodedValue: encodedValue) {
                result.append(dataRow)
            }
            if i & 0x3FFFF == 0, !baseMap.isEmpty {
                progress?(Int(Int64(i) * 100 / Int64(baseMap.count)))
            }
        }

        setViewMap(result)
        progress?(100)
    }

    public func filterColumnContains(column: Int, term: String, withinCurrentView: Bool, progress: ((Int) -> Void)?, cancellation: CancellationFlag) throws {
        guard column >= 0 else {
            if withinCurrentView {
                try filterWithinView({ fields in fields.contains { $0.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil } }, progress: progress, cancellation: cancellation)
            } else {
                try applyFilter({ fields in fields.contains { $0.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil } }, progress: progress, cancellation: cancellation)
            }
            return
        }

        let baseMap = withinCurrentView ? (viewMapSnapshot() ?? Self.identity(dataRowsAvailable)) : Self.identity(dataRowsAvailable)
        var result: [Int] = []
        result.reserveCapacity(min(baseMap.count, 1 << 16))

        for i in baseMap.indices {
            if i & 0xFFFF == 0 { try cancellation.check() }
            let dataRow = baseMap[i]
            let fieldData = try dataRowColumnData(dataRow: dataRow, column: column) ?? Data()
            let field = String(data: fieldData, encoding: encoding) ?? String(decoding: fieldData, as: UTF8.self)
            if field.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                result.append(dataRow)
            }
            if i & 0x3FFFF == 0, !baseMap.isEmpty {
                progress?(Int(Int64(i) * 100 / Int64(baseMap.count)))
            }
        }

        setViewMap(result)
        progress?(100)
    }

    public func sort(column: Int, ascending: Bool, progress: ((Int) -> Void)?, cancellation: CancellationFlag) throws {
        try sort(keys: [SortKey(column: column, ascending: ascending)], progress: progress, cancellation: cancellation)
    }

    public func sort(keys sortKeys: [SortKey], progress: ((Int) -> Void)?, cancellation: CancellationFlag) throws {
        guard !sortKeys.isEmpty else {
            progress?(100)
            return
        }
        if sortKeys.count == 1 {
            try sortSingleColumn(key: sortKeys[0], progress: progress, cancellation: cancellation)
            return
        }

        let baseMap = viewMapSnapshot() ?? Self.identity(dataRowsAvailable)
        let count = baseMap.count
        var textKeys = Array(repeating: Array(repeating: "", count: count), count: sortKeys.count)
        var numericKeys = Array(repeating: Array(repeating: 0.0, count: count), count: sortKeys.count)
        var allNumeric = Array(repeating: count > 0, count: sortKeys.count)

        for i in baseMap.indices {
            if i & 0xFFFF == 0 { try cancellation.check() }
            let row = try getDataRowUncached(baseMap[i])
            for j in sortKeys.indices {
                let column = sortKeys[j].column
                let key = column >= 0 && column < row.count ? row[column] : ""
                textKeys[j][i] = key
                if allNumeric[j] {
                    if key.isEmpty {
                        numericKeys[j][i] = -Double.infinity
                    } else if let value = Double(key.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        numericKeys[j][i] = value
                    } else {
                        allNumeric[j] = false
                    }
                }
            }
            if i & 0x3FFFF == 0, count > 0 {
                progress?(Int(Int64(i) * 100 / Int64(count)))
            }
        }

        let sortedIndexes = Self.identity(count).sorted { lhs, rhs in
            for j in sortKeys.indices {
                let comparison: ComparisonResult
                if allNumeric[j] {
                    let l = numericKeys[j][lhs]
                    let r = numericKeys[j][rhs]
                    comparison = l == r ? .orderedSame : (l < r ? .orderedAscending : .orderedDescending)
                } else {
                    comparison = textKeys[j][lhs].localizedCaseInsensitiveCompare(textKeys[j][rhs])
                }
                if comparison != .orderedSame {
                    let isAscending = sortKeys[j].ascending
                    return isAscending ? comparison == .orderedAscending : comparison == .orderedDescending
                }
            }
            return baseMap[lhs] < baseMap[rhs]
        }

        setViewMap(sortedIndexes.map { baseMap[$0] })
        progress?(100)
    }

    private func sortSingleColumn(key sortKey: SortKey, progress: ((Int) -> Void)?, cancellation: CancellationFlag) throws {
        let baseMap = viewMapSnapshot() ?? Self.identity(dataRowsAvailable)
        let count = baseMap.count
        var textKeys = Array(repeating: "", count: count)
        var numericKeys = Array(repeating: 0.0, count: count)
        var allNumeric = count > 0

        for i in baseMap.indices {
            if i & 0xFFFF == 0 { try cancellation.check() }
            let fieldData = try dataRowColumnData(dataRow: baseMap[i], column: sortKey.column) ?? Data()
            let key = String(data: fieldData, encoding: encoding) ?? String(decoding: fieldData, as: UTF8.self)
            textKeys[i] = key
            if allNumeric {
                if key.isEmpty {
                    numericKeys[i] = -Double.infinity
                } else if let value = Double(key.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    numericKeys[i] = value
                } else {
                    allNumeric = false
                }
            }
            if i & 0x3FFFF == 0, count > 0 {
                progress?(Int(Int64(i) * 100 / Int64(count)))
            }
        }

        let sortedIndexes = Self.identity(count).sorted { lhs, rhs in
            let comparison: ComparisonResult
            if allNumeric {
                let l = numericKeys[lhs]
                let r = numericKeys[rhs]
                comparison = l == r ? .orderedSame : (l < r ? .orderedAscending : .orderedDescending)
            } else {
                comparison = textKeys[lhs].localizedCaseInsensitiveCompare(textKeys[rhs])
            }
            if comparison != .orderedSame {
                return sortKey.ascending ? comparison == .orderedAscending : comparison == .orderedDescending
            }
            return baseMap[lhs] < baseMap[rhs]
        }

        setViewMap(sortedIndexes.map { baseMap[$0] })
        progress?(100)
    }

    public func resetViewOrder() {
        viewLock.lock()
        if viewMap != nil {
            viewMap!.sort()
        }
        viewLock.unlock()
    }

    public func clearView() {
        setViewMap(nil)
    }

    private static func identity(_ count: Int) -> [Int] {
        count <= 0 ? [] : Array(0..<count)
    }
}
