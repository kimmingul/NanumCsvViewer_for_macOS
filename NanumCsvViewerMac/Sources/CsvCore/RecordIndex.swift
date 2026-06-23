import Foundation

public final class RecordIndex {
    private static let segmentBits = 20
    private static let segmentSize = 1 << segmentBits
    private static let segmentMask = segmentSize - 1

    private let segmentLock = NSLock()
    private let countLock = NSLock()
    private var segments: [UnsafeMutablePointer<Int64>] = []
    private var publishedCount: Int64 = 0
    private var writeCount: Int64 = 0
    private var currentSegmentIndex = -1
    private var currentSegment: UnsafeMutablePointer<Int64>?

    public init() {}

    deinit {
        for pointer in segments {
            pointer.deallocate()
        }
    }

    public var count: Int64 {
        countLock.lock()
        defer { countLock.unlock() }
        return publishedCount
    }

    public func add(_ offset: Int64) {
        let c = writeCount
        let segmentIndex = Int(c >> Int64(Self.segmentBits))
        let within = Int(c & Int64(Self.segmentMask))

        if segmentIndex != currentSegmentIndex {
            segmentLock.lock()
            while segmentIndex >= segments.count {
                let pointer = UnsafeMutablePointer<Int64>.allocate(capacity: Self.segmentSize)
                pointer.initialize(repeating: 0, count: Self.segmentSize)
                segments.append(pointer)
            }
            currentSegment = segments[segmentIndex]
            currentSegmentIndex = segmentIndex
            segmentLock.unlock()
        }

        currentSegment![within] = offset
        writeCount = c + 1
    }

    public func publish() {
        countLock.lock()
        publishedCount = writeCount
        countLock.unlock()
    }

    public subscript(index: Int64) -> Int64 {
        let segmentIndex = Int(index >> Int64(Self.segmentBits))
        let within = Int(index & Int64(Self.segmentMask))
        segmentLock.lock()
        let pointer = segments[segmentIndex]
        segmentLock.unlock()
        return pointer[within]
    }
}
