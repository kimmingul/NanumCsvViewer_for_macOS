import Foundation

public struct DistinctColumnValue: Equatable, Sendable {
    public let value: String
    public let count: Int

    public init(value: String, count: Int) {
        self.value = value
        self.count = count
    }
}

public final class VirtualCsvDocument: @unchecked Sendable {
    private static let configLock = NSLock()
    nonisolated(unsafe) private static var persistentIndexEnabledStorage = true
    nonisolated(unsafe) private static var deletePersistentIndexOnCloseStorage = false
    nonisolated(unsafe) private static var persistentIndexDirectoryOverrideStorage: URL?

    public static var persistentIndexEnabled: Bool {
        get { configLock.withLock { persistentIndexEnabledStorage } }
        set { configLock.withLock { persistentIndexEnabledStorage = newValue } }
    }

    public static var deletePersistentIndexOnClose: Bool {
        get { configLock.withLock { deletePersistentIndexOnCloseStorage } }
        set { configLock.withLock { deletePersistentIndexOnCloseStorage = newValue } }
    }

    public static var persistentIndexDirectoryOverride: URL? {
        get { configLock.withLock { persistentIndexDirectoryOverrideStorage } }
        set { configLock.withLock { persistentIndexDirectoryOverrideStorage = newValue } }
    }

    /// Analysis, charts, and pivot scans stop after this many display rows
    /// (Windows twin behavior); exports and filtering always use the full view.
    nonisolated(unsafe) private static var analysisRowLimitStorage = 2_000_000

    public static var analysisRowLimit: Int {
        get { configLock.withLock { analysisRowLimitStorage } }
        set { configLock.withLock { analysisRowLimitStorage = max(1, newValue) } }
    }

    public var analysisRowsTruncated: Bool {
        displayRowCount > Self.analysisRowLimit
    }

    var analysisRowScanBound: Int {
        Swift.min(displayRowCount, Self.analysisRowLimit)
    }

    public static var ramBufferBudgetBytes: Int64 {
        let physical = Int64(ProcessInfo.processInfo.physicalMemory)
        return min(max(1_500_000_000, physical / 4), 8_000_000_000)
    }

    public static func persistentIndexDirectoryURL() -> URL {
        if let persistentIndexDirectoryOverride {
            return persistentIndexDirectoryOverride
        }
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("com.nanum.csvviewer.mac", isDirectory: true)
            .appendingPathComponent("Indexes", isDirectory: true)
    }

    public static func ensurePersistentIndexDirectory() throws -> URL {
        let directory = persistentIndexDirectoryURL()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public static func persistentIndexURL(forCSVAt path: String) -> URL {
        let sourceURL = URL(fileURLWithPath: path)
        let standardizedPath = sourceURL.standardizedFileURL.path
        let baseName = sanitizedIndexBaseName(sourceURL.lastPathComponent)
        let hash = stablePathHash(standardizedPath)
        return persistentIndexDirectoryURL()
            .appendingPathComponent("\(baseName)-\(hash).ncvidx", isDirectory: false)
    }

    public static func clearPersistentIndexDirectory() throws {
        let directory = try ensurePersistentIndexDirectory()
        let items = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for item in items {
            try FileManager.default.removeItem(at: item)
        }
    }

    private static var rowCacheCapacity: Int {
        let physical = ProcessInfo.processInfo.physicalMemory
        if physical >= 32 * 1_024 * 1_024 * 1_024 { return 65_536 }
        if physical >= 16 * 1_024 * 1_024 * 1_024 { return 32_768 }
        return 8_192
    }
    private static let readUnit = MemoryFileBuffer.chunkSize
    private static let maxRecoveredHeaderEmbeddedLineBreaks = 4
    private static let sidecarVersion = 2
    private static let sidecarMaxBytes = 256 * 1_024 * 1_024

    private let path: String
    private let index = RecordIndex()
    private let cache = RowCache(capacity: rowCacheCapacity)
    private let diskSource: RandomByteSource
    private let ramBufferPending: MemoryFileBuffer?

    private let stateLock = NSLock()
    private let viewLock = NSLock()
    private let sourceLock = NSLock()
    private let persistentIndexLock = NSLock()

    private var encoding: String.Encoding
    private let preamble: Int
    private var delimiterByte: UInt8 = UInt8(ascii: ",")
    private var headerStart: Int64 = 0
    private var headerEnd: Int64 = 0
    private var viewMap: [Int]?
    private var ramBuffer: MemoryFileBuffer?
    private var indexingCompleteValue = false
    private var persistentIndexDeleteRequested = false
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

    public enum ExportFormat: String, Sendable {
        case csv
        case markdown
        case json
        case html
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

    public func deletePersistentIndex() {
        persistentIndexLock.lock()
        persistentIndexDeleteRequested = true
        try? FileManager.default.removeItem(atPath: sidecarPath)
        try? FileManager.default.removeItem(atPath: legacySidecarPath)
        persistentIndexLock.unlock()
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

        if Self.persistentIndexEnabled {
            tryLoadPersistentIndex()
        }
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

    /// Lock-protected shared state for the concurrent chunk scan; Swift 6
    /// forbids capturing mutable locals in concurrently-executing closures.
    private final class ParallelScanState: @unchecked Sendable {
        let lock = NSLock()
        var chunkOffsets: [[Int64]?]
        var chunkData: [Data?]
        var foundQuote = false
        var firstError: Error?
        var completed = 0

        init(chunkCount: Int, collectData: Bool) {
            chunkOffsets = Array(repeating: nil, count: chunkCount)
            chunkData = collectData ? Array(repeating: nil, count: chunkCount) : []
        }
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
        let state = ParallelScanState(chunkCount: chunkCount, collectData: ramBufferPending != nil)
        let quote = UInt8(ascii: "\"")
        let cr: UInt8 = 0x0D
        let lf: UInt8 = 0x0A

        DispatchQueue.concurrentPerform(iterations: chunkCount) { chunkIndex in
            state.lock.lock()
            let shouldStop = state.foundQuote || state.firstError != nil
            state.lock.unlock()
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

                state.lock.lock()
                if localFoundQuote {
                    state.foundQuote = true
                }
                state.chunkOffsets[chunkIndex] = offsets
                if !state.chunkData.isEmpty {
                    state.chunkData[chunkIndex] = data.count == Int(chunkLength) ? data : data.prefix(Int(chunkLength))
                }
                state.completed += 1
                let done = state.completed
                state.lock.unlock()

                if done & 0x3 == 0 || done == chunkCount {
                    let processed = min(fileLength, Int64(done) * chunkSize)
                    let scanPercent = min(70, Int(Int64(done) * 70 / Int64(max(1, chunkCount))))
                    progress(IndexProgress(bytesProcessed: processed, fileLength: fileLength, rowsSoFar: 0, percentOverride: scanPercent))
                }
            } catch {
                state.lock.lock()
                if state.firstError == nil { state.firstError = error }
                state.lock.unlock()
            }
        }

        if let firstError = state.firstError { throw firstError }
        if state.foundQuote {
            progress(IndexProgress(bytesProcessed: 0, fileLength: fileLength, rowsSoFar: 0, percentOverride: 0))
            return false
        }

        index.add(Int64(preamble))
        for chunkIndex in state.chunkOffsets.indices {
            let offsets = state.chunkOffsets[chunkIndex]
            for offset in offsets ?? [] {
                index.add(offset)
            }
            if chunkIndex & 0x3 == 0 || chunkIndex == state.chunkOffsets.count - 1 {
                index.publish()
                let mergePercent = 70 + Int(Int64(chunkIndex + 1) * 29 / Int64(max(1, state.chunkOffsets.count)))
                progress(IndexProgress(bytesProcessed: fileLength, fileLength: fileLength, rowsSoFar: index.count, percentOverride: mergePercent))
            }
        }
        index.publish()
        markIndexingComplete()

        if let pending = ramBufferPending {
            for index in state.chunkData.indices {
                if let data = state.chunkData[index] {
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
        if indexingComplete {
            progress(IndexProgress(bytesProcessed: fileLength, fileLength: fileLength, rowsSoFar: index.count))
            return
        }

        if recoverMalformedHeader {
            try runMalformedHeaderRecoveryIndexing(progress: progress, cancellation: cancellation)
            schedulePersistentIndexSaveIfNeeded()
            return
        }

        if try runParallelSimpleIndexing(progress: progress, cancellation: cancellation) {
            schedulePersistentIndexSaveIfNeeded()
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
        schedulePersistentIndexSaveIfNeeded()
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

    public func distinctValues(
        column: Int,
        withinCurrentView: Bool,
        limit: Int?,
        progress: ((Int) -> Void)?,
        cancellation: CancellationFlag
    ) throws -> [DistinctColumnValue] {
        guard column >= 0, column < columnCount else { return [] }
        let baseMap = withinCurrentView ? (viewMapSnapshot() ?? Self.identity(dataRowsAvailable)) : Self.identity(dataRowsAvailable)
        var counts: [String: Int] = [:]
        counts.reserveCapacity(min(baseMap.count, 1_024))

        for index in baseMap.indices {
            if index & 0xFFFF == 0 { try cancellation.check() }
            let dataRow = baseMap[index]
            let fields = try getDataRowUncached(dataRow)
            let value = column < fields.count ? fields[column] : ""
            counts[value, default: 0] += 1
            if index & 0x3FFFF == 0, !baseMap.isEmpty {
                progress?(Int(Int64(index) * 100 / Int64(baseMap.count)))
            }
        }

        progress?(100)
        let sorted = counts
            .map { DistinctColumnValue(value: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.value.localizedCaseInsensitiveCompare(rhs.value) == .orderedAscending
            }
        guard let limit, limit >= 0 else { return sorted }
        return Array(sorted.prefix(limit))
    }

    public func facetSummaries(
        columns: [FacetColumnRequest],
        basePredicate: (@Sendable ([String]) -> Bool)? = nil,
        columnPredicates: [Int: @Sendable ([String]) -> Bool] = [:],
        histogramBinCount: Int = 6,
        topValueLimit: Int = 6,
        distinctCap: Int = 10_000,
        rowCap: Int? = nil,
        progress: ((Int) -> Void)? = nil,
        cancellation: CancellationFlag
    ) throws -> FacetReport {
        var seenColumns = Set<Int>()
        let requests = columns.filter { $0.column >= 0 && $0.column < columnCount && seenColumns.insert($0.column).inserted }
        let total = dataRowsAvailable
        let scanned = rowCap.map { min(total, max(0, $0)) } ?? total
        guard !requests.isEmpty else {
            return FacetReport(summaries: [], scannedRowCount: scanned, totalRowCount: total)
        }

        struct FacetAccumulator {
            var counts: [String: Int] = [:]
            var overflowCount = 0
            var distinctTruncated = false
            var minValue = Double.infinity
            var maxValue = -Double.infinity
            var numericCount = 0
            var nonNumericCount = 0
        }

        // Each facet is computed excluding its own column's filter so an active
        // selection stays visible and clicking it again toggles it off.
        let predicatePairs = columnPredicates.map { (column: $0.key, predicate: $0.value) }

        func contribution(_ fields: [String]) -> (allPass: Bool, soleFailedColumn: Int?)? {
            if let basePredicate, !basePredicate(fields) { return nil }
            var failedColumn = -1
            for pair in predicatePairs where !pair.predicate(fields) {
                if failedColumn >= 0 { return nil }
                failedColumn = pair.column
            }
            return failedColumn >= 0 ? (false, failedColumn) : (true, nil)
        }

        var accumulators = [FacetAccumulator](repeating: FacetAccumulator(), count: requests.count)
        for index in 0..<scanned {
            if index & 0x3FFF == 0 { try cancellation.check() }
            let fields = try getDataRowUncached(index)
            guard let rowContribution = contribution(fields) else { continue }
            for (slot, request) in requests.enumerated() {
                if let soleFailed = rowContribution.soleFailedColumn, soleFailed != request.column { continue }
                let value = request.column < fields.count ? fields[request.column] : ""
                if accumulators[slot].counts[value] != nil || accumulators[slot].counts.count < distinctCap {
                    accumulators[slot].counts[value, default: 0] += 1
                } else {
                    accumulators[slot].distinctTruncated = true
                    accumulators[slot].overflowCount += 1
                }
                if request.wantsHistogram {
                    let trimmed = value.trimmingCharacters(in: .whitespaces)
                    if let number = Double(trimmed), number.isFinite {
                        accumulators[slot].numericCount += 1
                        accumulators[slot].minValue = Swift.min(accumulators[slot].minValue, number)
                        accumulators[slot].maxValue = Swift.max(accumulators[slot].maxValue, number)
                    } else {
                        accumulators[slot].nonNumericCount += 1
                    }
                }
            }
            if index & 0xFFFF == 0, scanned > 0 {
                progress?(Int(Int64(index) * 100 / Int64(scanned)))
            }
        }

        func topValuesContent(_ accumulator: FacetAccumulator) -> FacetSummary.Content {
            let sorted = accumulator.counts
                .map { FacetValueBin(value: $0.key, count: $0.value) }
                .sorted { lhs, rhs in
                    if lhs.count != rhs.count { return lhs.count > rhs.count }
                    return lhs.value.localizedCaseInsensitiveCompare(rhs.value) == .orderedAscending
                }
            let bins = Array(sorted.prefix(max(0, topValueLimit)))
            let remainder = sorted.dropFirst(max(0, topValueLimit)).reduce(0) { $0 + $1.count }
            return .topValues(
                bins: bins,
                otherCount: remainder + accumulator.overflowCount,
                distinctTruncated: accumulator.distinctTruncated
            )
        }

        func histogramBounds(_ accumulator: FacetAccumulator) -> (min: Double, max: Double)? {
            guard accumulator.numericCount > 0, accumulator.minValue < accumulator.maxValue else { return nil }
            return (accumulator.minValue, accumulator.maxValue)
        }

        func parsedNumericKeys(_ accumulator: FacetAccumulator) -> [(value: Double, count: Int)]? {
            guard !accumulator.distinctTruncated else { return nil }
            var parsed: [(Double, Int)] = []
            parsed.reserveCapacity(accumulator.counts.count)
            for (key, count) in accumulator.counts {
                let trimmed = key.trimmingCharacters(in: .whitespaces)
                guard let number = Double(trimmed), number.isFinite else { continue }
                parsed.append((number, count))
            }
            return parsed
        }

        func binIndex(for value: Double, min: Double, width: Double, binCount: Int) -> Int {
            Swift.min(binCount - 1, Swift.max(0, Int((value - min) / width)))
        }

        var summaries = [FacetSummary?](repeating: nil, count: requests.count)
        var rebinSlots: [Int] = []
        var binStorage: [Int: [Int]] = [:]

        for (slot, request) in requests.enumerated() {
            let accumulator = accumulators[slot]
            guard request.wantsHistogram, let bounds = histogramBounds(accumulator) else {
                summaries[slot] = FacetSummary(column: request.column, content: topValuesContent(accumulator))
                continue
            }
            let binCount = max(1, histogramBinCount)
            if let parsed = parsedNumericKeys(accumulator) {
                let distinctNumericCount = Set(parsed.map(\.value)).count
                if distinctNumericCount <= binCount {
                    summaries[slot] = FacetSummary(column: request.column, content: topValuesContent(accumulator))
                    continue
                }
                let width = (bounds.max - bounds.min) / Double(binCount)
                var counts = [Int](repeating: 0, count: binCount)
                for (value, count) in parsed {
                    counts[binIndex(for: value, min: bounds.min, width: width, binCount: binCount)] += count
                }
                summaries[slot] = FacetSummary(
                    column: request.column,
                    content: Self.histogramContent(
                        counts: counts,
                        min: bounds.min,
                        max: bounds.max,
                        numericCount: accumulator.numericCount,
                        nonNumericCount: accumulator.nonNumericCount
                    )
                )
            } else {
                rebinSlots.append(slot)
                binStorage[slot] = [Int](repeating: 0, count: binCount)
            }
        }

        if !rebinSlots.isEmpty {
            let binCount = max(1, histogramBinCount)
            for index in 0..<scanned {
                if index & 0x3FFF == 0 { try cancellation.check() }
                let fields = try getDataRowUncached(index)
                guard let rowContribution = contribution(fields) else { continue }
                for slot in rebinSlots {
                    if let soleFailed = rowContribution.soleFailedColumn, soleFailed != requests[slot].column { continue }
                    let request = requests[slot]
                    let accumulator = accumulators[slot]
                    guard let bounds = histogramBounds(accumulator) else { continue }
                    let value = request.column < fields.count ? fields[request.column] : ""
                    let trimmed = value.trimmingCharacters(in: .whitespaces)
                    guard let number = Double(trimmed), number.isFinite else { continue }
                    let width = (bounds.max - bounds.min) / Double(binCount)
                    binStorage[slot]?[binIndex(for: number, min: bounds.min, width: width, binCount: binCount)] += 1
                }
            }
            for slot in rebinSlots {
                let request = requests[slot]
                let accumulator = accumulators[slot]
                guard let bounds = histogramBounds(accumulator), let counts = binStorage[slot] else {
                    summaries[slot] = FacetSummary(column: request.column, content: topValuesContent(accumulator))
                    continue
                }
                summaries[slot] = FacetSummary(
                    column: request.column,
                    content: Self.histogramContent(
                        counts: counts,
                        min: bounds.min,
                        max: bounds.max,
                        numericCount: accumulator.numericCount,
                        nonNumericCount: accumulator.nonNumericCount
                    )
                )
            }
        }

        progress?(100)
        return FacetReport(
            summaries: summaries.compactMap { $0 },
            scannedRowCount: scanned,
            totalRowCount: total
        )
    }

    private static func histogramContent(
        counts: [Int],
        min: Double,
        max: Double,
        numericCount: Int,
        nonNumericCount: Int
    ) -> FacetSummary.Content {
        let width = (max - min) / Double(counts.count)
        let bins = counts.enumerated().map { index, count in
            FacetHistogramBin(
                lowerBound: min + Double(index) * width,
                upperBound: index == counts.count - 1 ? max : min + Double(index + 1) * width,
                count: count
            )
        }
        return .histogram(bins: bins, numericCount: numericCount, nonNumericCount: nonNumericCount)
    }

    public func exportCurrentView(to outputPath: String, selectedColumns: [Int]? = nil, cancellation: CancellationFlag) throws {
        try exportCurrentView(to: outputPath, format: .csv, selectedColumns: selectedColumns, cancellation: cancellation)
    }

    /// Exports the current view. Returns `true` if any character could not be
    /// represented in the target encoding and was substituted (only possible
    /// for a non-UTF-8 CSV export), so the caller can warn about lossy output.
    @discardableResult
    public func exportCurrentView(
        to outputPath: String,
        format: ExportFormat,
        encodingName: String = CsvEncodingName.utf8,
        selectedColumns: [Int]? = nil,
        progress: ((Int) -> Void)? = nil,
        cancellation: CancellationFlag
    ) throws -> Bool {
        let columns = (selectedColumns ?? Array(0..<columnCount)).filter { $0 >= 0 && $0 < columnCount }
        // Encoding/BOM only apply to CSV (the format opened by Korean tools);
        // JSON/HTML/Markdown are conventionally UTF-8 and a BOM would corrupt
        // JSON, so they are always written as plain UTF-8.
        let (encoding, byteOrderMark) = format == .csv
            ? EncodingDetector.exportEncoding(named: encodingName)
            : (String.Encoding.utf8, false)
        FileManager.default.createFile(atPath: outputPath, contents: nil)
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: outputPath))
        defer { try? handle.close() }

        if byteOrderMark {
            try handle.write(contentsOf: Data([0xEF, 0xBB, 0xBF]))
        }
        var lossy = false
        func write(_ text: String) throws {
            if let exact = text.data(using: encoding, allowLossyConversion: false) {
                try handle.write(contentsOf: exact)
            } else {
                // A character is unrepresentable in the target encoding (e.g. an
                // emoji in CP949). Substitute rather than fail the whole export,
                // but record it so the caller can warn.
                lossy = true
                try handle.write(contentsOf: text.data(using: encoding, allowLossyConversion: true) ?? Data(text.utf8))
            }
        }

        let totalRows = displayRowCount
        func reportProgress(_ row: Int) {
            if row & 0x3FFF == 0 {
                progress?(totalRows > 0 ? Int(Int64(row) * 100 / Int64(totalRows)) : 100)
            }
        }

        func writeCsvLine(_ fields: [String]) throws {
            let line = fields.map(Self.csvEscaped).joined(separator: ",") + "\n"
            try write(line)
        }

        let headers = columns.map { header[$0] }
        let jsonHeaders = Self.uniqueJsonHeaders(headers)
        switch format {
        case .csv:
            try writeCsvLine(headers)
            for row in 0..<displayRowCount {
                if row & 0x3FFF == 0 { try cancellation.check() }
                let fields = try getDisplayRow(row)
                reportProgress(row)
                try writeCsvLine(columns.map { $0 < fields.count ? fields[$0] : "" })
            }
        case .markdown:
            try write("| " + headers.map(Self.markdownEscaped).joined(separator: " | ") + " |\n")
            try write("| " + Array(repeating: "---", count: headers.count).joined(separator: " | ") + " |\n")
            for row in 0..<displayRowCount {
                if row & 0x3FFF == 0 { try cancellation.check() }
                let fields = try getDisplayRow(row)
                reportProgress(row)
                let selected = columns.map { $0 < fields.count ? fields[$0] : "" }
                try write("| " + selected.map(Self.markdownEscaped).joined(separator: " | ") + " |\n")
            }
        case .json:
            try write("[\n")
            for row in 0..<displayRowCount {
                if row & 0x3FFF == 0 { try cancellation.check() }
                let fields = try getDisplayRow(row)
                reportProgress(row)
                var object: [String: String] = [:]
                for (index, column) in columns.enumerated() {
                    object[jsonHeaders[index]] = column < fields.count ? fields[column] : ""
                }
                let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
                let text = String(decoding: data, as: UTF8.self)
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map { "  " + $0 }
                    .joined(separator: "\n")
                try write(text)
                try write(row == displayRowCount - 1 ? "\n" : ",\n")
            }
            try write("]")
        case .html:
            try write("<!doctype html>\n<html>\n<head><meta charset=\"utf-8\"><title>Nanum CSV Viewer Export</title></head>\n<body>\n<table>\n")
            try write("<thead><tr>" + headers.map { "<th>\(Self.htmlEscaped($0))</th>" }.joined() + "</tr></thead>\n<tbody>\n")
            for row in 0..<displayRowCount {
                if row & 0x3FFF == 0 { try cancellation.check() }
                let fields = try getDisplayRow(row)
                reportProgress(row)
                let selected = columns.map { $0 < fields.count ? fields[$0] : "" }
                try write("<tr>" + selected.map { "<td>\(Self.htmlEscaped($0))</td>" }.joined() + "</tr>\n")
            }
            try write("</tbody>\n</table>\n</body>\n</html>")
        }
        // Only report 100% on success — a thrown write/encode error or a
        // cancellation must not leave a failed export reading as complete.
        progress?(100)
        return lossy
    }

    public func findNext(query: CsvSearchQuery, start: Int, wrap: Bool, cancellation: CancellationFlag) throws -> CsvSearchMatch? {
        let total = displayRowCount
        guard total > 0 else { return nil }
        let boundedStart = max(0, min(start, total))
        let matcher = try CsvSearchMatcher(query: query)

        if let match = try findNextInRange(matcher: matcher, range: boundedStart..<total, cancellation: cancellation) {
            return match
        }
        if wrap, boundedStart > 0 {
            return try findNextInRange(matcher: matcher, range: 0..<boundedStart, cancellation: cancellation)
        }
        return nil
    }

    private func findNextInRange(matcher: CsvSearchMatcher, range: Range<Int>, cancellation: CancellationFlag) throws -> CsvSearchMatch? {
        for viewRow in range {
            if viewRow & 0x3FFF == 0 { try cancellation.check() }
            let row = try getDisplayRow(viewRow)
            if let match = matcher.firstMatch(in: row) {
                return CsvSearchMatch(
                    viewRow: viewRow,
                    sourceRowNumber: getSourceRowNumber(viewRow),
                    column: match.column,
                    value: match.value
                )
            }
        }
        return nil
    }

    public func findDuplicates(columns: [Int], cancellation: CancellationFlag) throws -> [DuplicateGroup] {
        let columns = columns.filter { $0 >= 0 && $0 < columnCount }
        guard !columns.isEmpty else { return [] }
        var indexMap: [Int: Int] = [:]
        var ordered: [Int] = []
        for column in columns where indexMap[column] == nil {
            indexMap[column] = ordered.count
            ordered.append(column)
        }
        // Project to only the compared columns while streaming; still holds one
        // reduced row per scanned row (duplicate groups reference every member).
        var rows: [(fields: [String], sourceRow: Int64)] = []
        rows.reserveCapacity(min(displayRowCount, Self.analysisRowLimit))
        try forEachDataRow(cancellation: cancellation) { dataRow, full in
            rows.append((ordered.map { $0 >= 0 && $0 < full.count ? full[$0] : "" }, Int64(dataRow) + 1))
        }
        return CsvAnalytics.findDuplicates(rows: rows, columns: columns.map { indexMap[$0] ?? 0 })
    }

    public func groupBy(groupColumns: [Int], valueColumn: Int, functions: [AggregationFunction], cancellation: CancellationFlag) throws -> GroupByResult {
        let groupColumns = groupColumns.filter { $0 >= 0 && $0 < columnCount }
        guard !groupColumns.isEmpty, valueColumn >= 0, valueColumn < columnCount else {
            return GroupByResult(groupColumns: groupColumns, valueColumn: valueColumn, functions: functions, rows: [])
        }
        let projected = try projectedDisplayRows(columns: groupColumns + [valueColumn], cancellation: cancellation)
        let result = CsvAnalytics.groupBy(
            rows: projected.rows,
            groupColumns: groupColumns.map { projected.indexMap[$0] ?? 0 },
            valueColumn: projected.indexMap[valueColumn] ?? 0,
            functions: functions
        )
        // Report original column indices, not the projected positions.
        return GroupByResult(groupColumns: groupColumns, valueColumn: valueColumn, functions: result.functions, rows: result.rows)
    }

    public func numericDistribution(column: Int, binCount: Int = 10, cancellation: CancellationFlag) throws -> NumericDistribution {
        guard column >= 0, column < columnCount else {
            return CsvAnalytics.numericDistribution(values: [], column: column, binCount: binCount)
        }
        var values: [Double] = []
        try forEachDisplayRow(cancellation: cancellation) { row in
            guard column < row.count,
                  let value = Double(row[column].trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
            values.append(value)
        }
        return CsvAnalytics.numericDistribution(values: values, column: column, binCount: binCount)
    }

    public func dateHistogram(dateColumn: Int, valueColumn: Int? = nil, period: DateBinPeriod, cancellation: CancellationFlag) throws -> DateHistogram {
        let valueColumn = valueColumn.flatMap { $0 >= 0 && $0 < columnCount ? $0 : nil }
        let projected = try projectedDisplayRows(columns: [dateColumn] + (valueColumn.map { [$0] } ?? []), cancellation: cancellation)
        let result = CsvAnalytics.dateHistogram(
            rows: projected.rows,
            dateColumn: projected.indexMap[dateColumn] ?? 0,
            valueColumn: valueColumn.flatMap { projected.indexMap[$0] },
            period: period
        )
        return DateHistogram(dateColumn: dateColumn, valueColumn: valueColumn, period: result.period, bins: result.bins)
    }

    public func pivotTable(
        rowColumns: [Int],
        columnColumns: [Int],
        valueColumn: Int,
        function: AggregationFunction,
        filters: [PivotFilter] = [],
        dateGroupings: [Int: DateBinPeriod] = [:],
        cancellation: CancellationFlag
    ) throws -> PivotTableResult {
        let rowColumns = rowColumns.filter { $0 >= 0 && $0 < columnCount }
        let columnColumns = columnColumns.filter { $0 >= 0 && $0 < columnCount }
        let filters = filters.filter { $0.column >= 0 && $0.column < columnCount }
        let dateGroupings = dateGroupings.filter { column, _ in column >= 0 && column < columnCount }
        guard valueColumn >= 0, valueColumn < columnCount else {
            return PivotTableResult(
                rowColumns: rowColumns,
                rowColumnNames: rowColumns.map { header[$0] },
                columnColumns: columnColumns,
                valueColumn: valueColumn,
                function: function,
                rowKeys: [],
                columnKeys: [],
                values: [:]
            )
        }
        // Project to only the columns the pivot references and remap every
        // column-index parameter, so the scan stays at O(rows × usedColumns).
        let usedColumns = rowColumns + columnColumns + [valueColumn] + filters.map(\.column) + Array(dateGroupings.keys)
        let projected = try projectedDisplayRows(columns: usedColumns, cancellation: cancellation)
        func remap(_ column: Int) -> Int { projected.indexMap[column] ?? 0 }
        let remappedFilters = filters.map { PivotFilter(column: remap($0.column), selectedValue: $0.selectedValue) }
        let remappedDateGroupings = Dictionary(uniqueKeysWithValues: dateGroupings.map { (remap($0.key), $0.value) })
        let rowColumnNames = rowColumns.map { header[$0].isEmpty ? "Column \($0 + 1)" : header[$0] }
        let result = try CsvAnalytics.pivotTable(
            rows: projected.rows,
            rowColumns: rowColumns.map(remap),
            rowColumnNames: rowColumnNames,
            columnColumns: columnColumns.map(remap),
            valueColumn: remap(valueColumn),
            function: function,
            filters: remappedFilters,
            dateGroupings: remappedDateGroupings,
            cancellation: cancellation
        )
        // Report original column indices; keys/values are data, not indices.
        return PivotTableResult(
            rowColumns: rowColumns,
            rowColumnNames: rowColumnNames,
            columnColumns: columnColumns,
            valueColumn: valueColumn,
            function: result.function,
            rowKeys: result.rowKeys,
            columnKeys: result.columnKeys,
            values: result.values
        )
    }

    public func pivotFilterValues(
        column: Int,
        dateGrouping: DateBinPeriod?,
        limit: Int = 500,
        rowLimit: Int = 50_000,
        cancellation: CancellationFlag
    ) throws -> [String] {
        guard column >= 0, column < columnCount else { return [] }
        var values: Set<String> = []
        let dateGroupings = dateGrouping.map { [column: $0] } ?? [:]
        let upperBound = min(displayRowCount, max(0, rowLimit))
        for viewRow in 0..<upperBound {
            if viewRow & 0x3FFF == 0 { try cancellation.check() }
            let row = try getDisplayRow(viewRow)
            values.insert(CsvAnalytics.pivotKeyValue(row: row, column: column, dateGroupings: dateGroupings))
            if values.count >= limit {
                break
            }
        }
        return values.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    public func correlation(xColumn: Int, yColumn: Int, method: CorrelationMethod, cancellation: CancellationFlag) throws -> CorrelationResult {
        var pairs: [(Double, Double)] = []
        try forEachDisplayRow(cancellation: cancellation) { row in
            guard xColumn < row.count, yColumn < row.count,
                  let x = Double(row[xColumn].trimmingCharacters(in: .whitespacesAndNewlines)),
                  let y = Double(row[yColumn].trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
            pairs.append((x, y))
        }
        return CsvStatistics.correlation(pairs: pairs, method: method)
    }

    public func independentTTest(groupColumn: Int, valueColumn: Int, groupA: String, groupB: String, cancellation: CancellationFlag) throws -> IndependentTTestResult {
        var a: [Double] = []
        var b: [Double] = []
        try forEachDisplayRow(cancellation: cancellation) { row in
            guard groupColumn < row.count, valueColumn < row.count,
                  let value = Double(row[valueColumn].trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
            if row[groupColumn] == groupA {
                a.append(value)
            } else if row[groupColumn] == groupB {
                b.append(value)
            }
        }
        return CsvStatistics.independentTTest(groupA: groupA, a: a, groupB: groupB, b: b)
    }

    public func pairedTTest(beforeColumn: Int, afterColumn: Int, cancellation: CancellationFlag) throws -> PairedTTestResult {
        var before: [Double] = []
        var after: [Double] = []
        try forEachDisplayRow(cancellation: cancellation) { row in
            guard beforeColumn < row.count, afterColumn < row.count,
                  let b = Double(row[beforeColumn].trimmingCharacters(in: .whitespacesAndNewlines)),
                  let a = Double(row[afterColumn].trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
            before.append(b)
            after.append(a)
        }
        return CsvStatistics.pairedTTest(before: before, after: after)
    }

    public func chiSquareTest(rowColumn: Int, columnColumn: Int, cancellation: CancellationFlag) throws -> ChiSquareResult {
        var pairs: [(String, String)] = []
        try forEachDisplayRow(cancellation: cancellation) { row in
            guard rowColumn < row.count, columnColumn < row.count else { return }
            pairs.append((row[rowColumn], row[columnColumn]))
        }
        return CsvStatistics.chiSquare(rows: pairs)
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

    /// Streams display rows (current filter/sort order) up to the analysis cap,
    /// one at a time, so an analysis/chart/pivot scan never materializes the
    /// whole view. Reads bypass the row cache (like `distinctValues` and
    /// `facetSummaries`) so a full scan does not evict the visible-row cache.
    public func forEachDisplayRow(cancellation: CancellationFlag, _ body: ([String]) throws -> Void) throws {
        // Avoids materializing an identity map for huge unfiltered files — that
        // allocation is exactly what this streaming API exists to prevent.
        try forEachDataRow(cancellation: cancellation) { _, row in try body(row) }
    }

    /// Like `forEachDisplayRow` but also yields each row's underlying data-row
    /// index (for callers that need the source row number).
    func forEachDataRow(cancellation: CancellationFlag, _ body: (Int, [String]) throws -> Void) throws {
        let limit = Self.analysisRowLimit
        if let baseMap = viewMapSnapshot() {
            let bound = min(baseMap.count, limit)
            for index in 0..<bound {
                if index & 0xFFF == 0 { try cancellation.check() }
                let dataRow = baseMap[index]
                try body(dataRow, try getDataRowUncached(dataRow))
            }
        } else {
            let bound = min(dataRowsAvailable, limit)
            for dataRow in 0..<bound {
                if dataRow & 0xFFF == 0 { try cancellation.check() }
                try body(dataRow, try getDataRowUncached(dataRow))
            }
        }
    }

    /// Streams the view and keeps only `columns` (deduplicated, in the given
    /// order) per row, so aggregators that consume `[[String]]` run at
    /// O(rows × usedColumns) memory instead of O(rows × allColumns). Returns
    /// the reduced rows and a map from original column index to its position
    /// in the projected rows.
    func projectedDisplayRows(columns: [Int], cancellation: CancellationFlag) throws -> (rows: [[String]], indexMap: [Int: Int]) {
        var indexMap: [Int: Int] = [:]
        var ordered: [Int] = []
        for column in columns where indexMap[column] == nil {
            indexMap[column] = ordered.count
            ordered.append(column)
        }
        var rows: [[String]] = []
        rows.reserveCapacity(min(displayRowCount, Self.analysisRowLimit))
        try forEachDisplayRow(cancellation: cancellation) { row in
            rows.append(ordered.map { $0 >= 0 && $0 < row.count ? row[$0] : "" })
        }
        return (rows, indexMap)
    }

    private static func csvEscaped(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private static func uniqueJsonHeaders(_ headers: [String]) -> [String] {
        var counts: [String: Int] = [:]
        return headers.enumerated().map { index, header in
            let base = header.isEmpty ? "Column \(index + 1)" : header
            let count = (counts[base] ?? 0) + 1
            counts[base] = count
            return count == 1 ? base : "\(base) (\(count))"
        }
    }

    private static func markdownEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\r\n", with: "<br>")
            .replacingOccurrences(of: "\n", with: "<br>")
            .replacingOccurrences(of: "\r", with: "<br>")
    }

    private static func htmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func identity(_ count: Int) -> [Int] {
        count <= 0 ? [] : Array(0..<count)
    }
}

private extension VirtualCsvDocument {
    static var sidecarMagic: [UInt8] {
        Array("NanumCsvIdx2\n".utf8)
    }

    var sidecarPath: String {
        Self.persistentIndexURL(forCSVAt: path).path
    }

    var legacySidecarPath: String {
        path + ".ncvidx"
    }

    func tryLoadPersistentIndex() {
        let url = URL(fileURLWithPath: sidecarPath)
        guard Self.sidecarHasCurrentMagic(at: url),
              let data = try? Data(contentsOf: url),
              let sidecar = PersistentIndexSidecar(data: data),
              sidecar.version == Self.sidecarVersion,
              sidecar.fileLength == fileLength,
              sidecar.modificationTime == currentModificationTime(),
              sidecar.delimiter == delimiterByte,
              sidecar.headerStart == headerStart,
              sidecar.headerEnd == headerEnd,
              !sidecar.offsets.isEmpty else {
            return
        }
        index.replace(with: sidecar.offsets)
        markIndexingComplete()
    }

    static func sidecarHasCurrentMagic(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return Array(handle.readData(ofLength: sidecarMagic.count)) == sidecarMagic
    }

    func schedulePersistentIndexSaveIfNeeded() {
        guard Self.persistentIndexEnabled, indexingComplete else { return }
        DispatchQueue.global(qos: .utility).async {
            self.savePersistentIndexIfNeeded()
        }
    }

    func savePersistentIndexIfNeeded() {
        guard Self.persistentIndexEnabled, indexingComplete else { return }
        guard index.count * Int64(MemoryLayout<Int64>.size) <= Int64(Self.sidecarMaxBytes) else { return }
        let offsets = index.offsets()
        let sidecar = PersistentIndexSidecar(
            version: Self.sidecarVersion,
            fileLength: fileLength,
            modificationTime: currentModificationTime(),
            delimiter: delimiterByte,
            headerStart: headerStart,
            headerEnd: headerEnd,
            offsets: offsets
        )
        let data = sidecar.encoded()
        guard (try? Self.ensurePersistentIndexDirectory()) != nil else { return }
        persistentIndexLock.lock()
        defer { persistentIndexLock.unlock() }
        guard !persistentIndexDeleteRequested else { return }
        try? FileManager.default.removeItem(atPath: legacySidecarPath)
        try? data.write(to: URL(fileURLWithPath: sidecarPath), options: .atomic)
    }

    func currentModificationTime() -> TimeInterval {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    }

    static func sanitizedIndexBaseName(_ name: String) -> String {
        let raw = name.isEmpty ? "csv" : name
        let replaced = String(raw.map { character in
            character == ":" ? "_" : character
        })
        let limited = replaced.count > 80 ? String(replaced.prefix(80)) : replaced
        return limited.isEmpty ? "csv" : limited
    }

    static func stablePathHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}

private struct PersistentIndexSidecar {
    let version: Int
    let fileLength: Int64
    let modificationTime: TimeInterval
    let delimiter: UInt8
    let headerStart: Int64
    let headerEnd: Int64
    let offsets: [Int64]

    init(
        version: Int,
        fileLength: Int64,
        modificationTime: TimeInterval,
        delimiter: UInt8,
        headerStart: Int64,
        headerEnd: Int64,
        offsets: [Int64]
    ) {
        self.version = version
        self.fileLength = fileLength
        self.modificationTime = modificationTime
        self.delimiter = delimiter
        self.headerStart = headerStart
        self.headerEnd = headerEnd
        self.offsets = offsets
    }

    init?(data: Data) {
        var reader = BinarySidecarReader(data: data)
        guard reader.readMagic(VirtualCsvDocument.sidecarMagic),
              let version = reader.readUInt64(),
              let fileLength = reader.readInt64(),
              let modificationTime = reader.readDouble(),
              let delimiter = reader.readUInt8(),
              let headerStart = reader.readInt64(),
              let headerEnd = reader.readInt64(),
              let offsetCount = reader.readUInt64(),
              offsetCount <= UInt64(Int.max) else {
            return nil
        }

        var offsets: [Int64] = []
        offsets.reserveCapacity(Int(offsetCount))
        for _ in 0..<offsetCount {
            guard let offset = reader.readInt64() else { return nil }
            offsets.append(offset)
        }

        guard reader.isFinished else { return nil }
        self.version = Int(version)
        self.fileLength = fileLength
        self.modificationTime = modificationTime
        self.delimiter = delimiter
        self.headerStart = headerStart
        self.headerEnd = headerEnd
        self.offsets = offsets
    }

    func encoded() -> Data {
        var data = Data()
        data.reserveCapacity(VirtualCsvDocument.sidecarMagic.count + 49 + offsets.count * MemoryLayout<Int64>.size)
        data.append(contentsOf: VirtualCsvDocument.sidecarMagic)
        data.appendLittleEndian(UInt64(version))
        data.appendLittleEndian(fileLength)
        data.appendLittleEndian(modificationTime.bitPattern)
        data.append(delimiter)
        data.appendLittleEndian(headerStart)
        data.appendLittleEndian(headerEnd)
        data.appendLittleEndian(UInt64(offsets.count))
        for offset in offsets {
            data.appendLittleEndian(offset)
        }
        return data
    }
}

private struct BinarySidecarReader {
    let data: Data
    var offset = 0

    var isFinished: Bool {
        offset == data.count
    }

    mutating func readMagic(_ magic: [UInt8]) -> Bool {
        guard data.count >= magic.count else { return false }
        for index in magic.indices where data[index] != magic[index] {
            return false
        }
        offset = magic.count
        return true
    }

    mutating func readUInt8() -> UInt8? {
        guard offset < data.count else { return nil }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func readUInt64() -> UInt64? {
        guard offset + MemoryLayout<UInt64>.size <= data.count else { return nil }
        var value: UInt64 = 0
        for index in 0..<MemoryLayout<UInt64>.size {
            value |= UInt64(data[offset + index]) << UInt64(index * 8)
        }
        offset += MemoryLayout<UInt64>.size
        return value
    }

    mutating func readInt64() -> Int64? {
        readUInt64().map { Int64(bitPattern: $0) }
    }

    mutating func readDouble() -> Double? {
        readUInt64().map { Double(bitPattern: $0) }
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt64) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { append(contentsOf: $0) }
    }

    mutating func appendLittleEndian(_ value: Int64) {
        appendLittleEndian(UInt64(bitPattern: value))
    }
}
