import Foundation

public final class CsvRecordIndexer {
    private enum State {
        case fieldStart
        case inUnquoted
        case inQuoted
        case quoteInQuoted
    }

    private static let cr: UInt8 = 0x0D
    private static let lf: UInt8 = 0x0A

    private let index: RecordIndex
    private let fileLength: Int64
    private let delimiter: UInt8
    private let quote: UInt8
    private var state: State = .fieldStart
    private var awaitingLfAfterCr = false

    public init(index: RecordIndex, fileLength: Int64, delimiter: UInt8, firstRecordStart: Int64, quote: UInt8 = UInt8(ascii: "\"")) {
        self.index = index
        self.fileLength = fileLength
        self.delimiter = delimiter
        self.quote = quote
        if fileLength > firstRecordStart {
            index.add(firstRecordStart)
        }
    }

    public func processBuffer(_ data: Data, baseOffset: Int64) {
        data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            processBytes(base: base, count: raw.count, baseOffset: baseOffset)
        }
    }

    public func processBytes(_ bytes: [UInt8], baseOffset: Int64) {
        bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            processBytes(base: base, count: buffer.count, baseOffset: baseOffset)
        }
    }

    private func processBytes(base: UnsafePointer<UInt8>, count: Int, baseOffset: Int64) {
        var i = 0
        while i < count {
            if awaitingLfAfterCr {
                awaitingLfAfterCr = false
                if base[i] == Self.lf {
                    addStart(baseOffset + Int64(i) + 1)
                    state = .fieldStart
                    i += 1
                    continue
                }
                addStart(baseOffset + Int64(i))
                state = .fieldStart
            }

            if state == .inQuoted {
                while i < count, base[i] != quote {
                    i += 1
                }
                if i >= count { break }
                state = .quoteInQuoted
                i += 1
                continue
            }

            while i < count, !isStructural(base[i]) {
                if state == .fieldStart || state == .quoteInQuoted {
                    state = .inUnquoted
                }
                i += 1
            }
            if i >= count { break }

            let c = base[i]
            switch state {
            case .fieldStart:
                if c == quote {
                    state = .inQuoted
                } else if c == delimiter {
                    state = .fieldStart
                } else if c == Self.cr {
                    awaitingLfAfterCr = true
                    i += 1
                    continue
                } else {
                    addStart(baseOffset + Int64(i) + 1)
                    state = .fieldStart
                    i += 1
                    continue
                }

            case .inUnquoted:
                if c == delimiter {
                    state = .fieldStart
                } else if c == Self.cr {
                    awaitingLfAfterCr = true
                    i += 1
                    continue
                } else if c == Self.lf {
                    addStart(baseOffset + Int64(i) + 1)
                    state = .fieldStart
                    i += 1
                    continue
                }

            case .quoteInQuoted:
                if c == quote {
                    state = .inQuoted
                } else if c == delimiter {
                    state = .fieldStart
                } else if c == Self.cr {
                    awaitingLfAfterCr = true
                    i += 1
                    continue
                } else {
                    addStart(baseOffset + Int64(i) + 1)
                    state = .fieldStart
                    i += 1
                    continue
                }

            case .inQuoted:
                break
            }
            i += 1
        }
    }

    private func isStructural(_ byte: UInt8) -> Bool {
        byte == quote || byte == delimiter || byte == Self.cr || byte == Self.lf
    }

    private func addStart(_ offset: Int64) {
        if offset < fileLength {
            index.add(offset)
        }
    }
}
