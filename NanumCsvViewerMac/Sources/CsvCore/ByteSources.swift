import Darwin
import Foundation

public protocol RandomByteSource: AnyObject {
    var length: Int64 { get }
    func read(offset: Int64, into destination: UnsafeMutableRawBufferPointer) throws
    func readData(offset: Int64, length: Int) throws -> Data
}

protocol ClosableByteSource: AnyObject {
    func close()
}

public final class FileByteSource: RandomByteSource, ClosableByteSource {
    private let fd: Int32
    public let length: Int64
    private var isClosed = false

    public init(path: String) throws {
        fd = Darwin.open(path, O_RDONLY)
        if fd < 0 { throw CsvError.fileOpenFailed(path) }

        var st = stat()
        if Darwin.fstat(fd, &st) != 0 {
            Darwin.close(fd)
            throw CsvError.fileOpenFailed(path)
        }
        length = Int64(st.st_size)
    }

    deinit {
        close()
    }

    public func close() {
        if !isClosed {
            Darwin.close(fd)
            isClosed = true
        }
    }

    public func read(offset: Int64, into destination: UnsafeMutableRawBufferPointer) throws {
        guard let base = destination.baseAddress else { return }
        var total = 0
        while total < destination.count {
            let result = Darwin.pread(fd, base.advanced(by: total), destination.count - total, off_t(offset) + off_t(total))
            if result < 0 { throw CsvError.shortRead }
            if result == 0 { throw CsvError.shortRead }
            total += result
        }
    }

    public func readData(offset: Int64, length: Int) throws -> Data {
        if length <= 0 { return Data() }
        var data = Data(count: length)
        try data.withUnsafeMutableBytes { raw in
            try read(offset: offset, into: raw)
        }
        return data
    }
}

public final class MappedFileByteSource: RandomByteSource, ClosableByteSource {
    private var baseAddress: UnsafeMutableRawPointer?
    public let length: Int64

    public init(path: String) throws {
        let fd = Darwin.open(path, O_RDONLY)
        if fd < 0 { throw CsvError.fileOpenFailed(path) }
        defer { Darwin.close(fd) }

        var st = stat()
        if Darwin.fstat(fd, &st) != 0 {
            throw CsvError.fileOpenFailed(path)
        }
        length = Int64(st.st_size)
        guard length > 0 else { return }

        let mapped = Darwin.mmap(nil, Int(length), PROT_READ, MAP_PRIVATE, fd, 0)
        if mapped == MAP_FAILED {
            throw CsvError.fileOpenFailed(path)
        }
        baseAddress = mapped
    }

    deinit {
        close()
    }

    public func close() {
        if let baseAddress {
            Darwin.munmap(baseAddress, Int(length))
            self.baseAddress = nil
        }
    }

    public func read(offset: Int64, into destination: UnsafeMutableRawBufferPointer) throws {
        guard let baseAddress, let dest = destination.baseAddress else { return }
        guard offset >= 0, length >= 0, offset + Int64(destination.count) <= length else { throw CsvError.shortRead }
        dest.copyMemory(from: baseAddress.advanced(by: Int(offset)), byteCount: destination.count)
    }

    public func readData(offset: Int64, length: Int) throws -> Data {
        guard length > 0 else { return Data() }
        guard let baseAddress else { throw CsvError.shortRead }
        guard offset >= 0, offset + Int64(length) <= self.length else { throw CsvError.shortRead }
        return Data(
            bytesNoCopy: baseAddress.advanced(by: Int(offset)),
            count: length,
            deallocator: .none
        )
    }
}

public final class MemoryFileBuffer: RandomByteSource {
    public static let chunkBits = 24
    public static let chunkSize = 1 << chunkBits
    private static let chunkMask = chunkSize - 1

    public let length: Int64
    private var chunks: [Data?]

    public init(length: Int64) {
        self.length = length
        let count = Int((length + Int64(Self.chunkSize) - 1) / Int64(Self.chunkSize))
        chunks = Array(repeating: nil, count: max(0, count))
    }

    public func setChunk(_ data: Data, at index: Int) {
        chunks[index] = data
    }

    public func read(offset: Int64, into destination: UnsafeMutableRawBufferPointer) throws {
        guard let destBase = destination.baseAddress else { return }
        var destPos = 0
        var pos = offset

        while destPos < destination.count {
            let chunkIndex = Int(pos >> Int64(Self.chunkBits))
            let within = Int(pos & Int64(Self.chunkMask))
            guard let chunk = chunks[chunkIndex] else { throw CsvError.shortRead }
            let available = chunk.count - within
            let toCopy = min(available, destination.count - destPos)
            chunk.withUnsafeBytes { source in
                if let sourceBase = source.baseAddress {
                    destBase.advanced(by: destPos).copyMemory(from: sourceBase.advanced(by: within), byteCount: toCopy)
                }
            }
            destPos += toCopy
            pos += Int64(toCopy)
        }
    }

    public func readData(offset: Int64, length: Int) throws -> Data {
        var data = Data(count: length)
        try data.withUnsafeMutableBytes { raw in
            try read(offset: offset, into: raw)
        }
        return data
    }
}
