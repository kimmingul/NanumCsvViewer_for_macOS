import Foundation
import XPC

@objc public protocol ImportServiceProtocol {
    func inspectFile(
        sourceFile: ImportFileReference,
        kind: ImportKind,
        limits: ImportLimits,
        reply: @escaping (ImportInspection?, ImportError?) -> Void
    )

    func importFile(
        sourceFile: ImportFileReference,
        kind: ImportKind,
        limits: ImportLimits,
        outputFile: ImportFileReference,
        metadataFile: ImportFileReference?,
        outputURL: URL,
        reply: @escaping (ImportResult?, ImportError?) -> Void
    )
}

public enum ImportServiceXPCInterface {
    public static func make() -> NSXPCInterface {
        NSXPCInterface(with: ImportServiceProtocol.self)
    }
}

@objc(ImportFileReference)
public final class ImportFileReference: NSObject, NSSecureCoding, @unchecked Sendable {
    public static let supportsSecureCoding = true

    public let fileHandle: FileHandle
    private let fileDescriptor: Int32

    public init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
        fileDescriptor = fileHandle.fileDescriptor
    }

    public init?(coder: NSCoder) {
        guard let coder = coder as? NSXPCCoder,
              let xpcObject = coder.decodeXPCObject(ofType: XPC_TYPE_FD, forKey: "fd") else {
            return nil
        }
        let fd = xpc_fd_dup(xpcObject)
        guard fd >= 0 else {
            return nil
        }
        fileHandle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        fileDescriptor = fd
    }

    public func encode(with coder: NSCoder) {
        guard let coder = coder as? NSXPCCoder,
              let xpcObject = xpc_fd_create(fileDescriptor) else {
            return
        }
        coder.encodeXPCObject(xpcObject, forKey: "fd")
    }
}

@objc(ImportKind)
public final class ImportKind: NSObject, NSSecureCoding, @unchecked Sendable {
    public static let supportsSecureCoding = true

    public static let echo = ImportKind("echo")
    public static let xls = ImportKind("xls")
    public static let sav = ImportKind("sav")
    public static let sas7bdat = ImportKind("sas7bdat")
    private static let xlsSheetPrefix = "xls-sheet:"

    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static func xlsSheet(_ sheetName: String) -> ImportKind {
        ImportKind(xlsSheetPrefix + sheetName)
    }

    public var xlsSheetName: String? {
        guard rawValue.hasPrefix(Self.xlsSheetPrefix) else { return nil }
        return String(rawValue.dropFirst(Self.xlsSheetPrefix.count))
    }

    public init?(coder: NSCoder) {
        guard let rawValue = coder.decodeObject(of: NSString.self, forKey: "rawValue") as String? else {
            return nil
        }
        self.rawValue = rawValue
    }

    public func encode(with coder: NSCoder) {
        coder.encode(rawValue as NSString, forKey: "rawValue")
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ImportKind else { return false }
        return rawValue == other.rawValue
    }

    public override var hash: Int {
        rawValue.hashValue
    }
}

@objc(ImportInspection)
public final class ImportInspection: NSObject, NSSecureCoding, @unchecked Sendable {
    public static let supportsSecureCoding = true

    public let sheetNames: [String]

    public init(sheetNames: [String]) {
        self.sheetNames = sheetNames
    }

    public init?(coder: NSCoder) {
        guard let sheetNames = coder.decodeObject(of: [NSArray.self, NSString.self], forKey: "sheetNames") as? [String] else {
            return nil
        }
        self.sheetNames = sheetNames
    }

    public func encode(with coder: NSCoder) {
        coder.encode(sheetNames as NSArray, forKey: "sheetNames")
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ImportInspection else { return false }
        return sheetNames == other.sheetNames
    }

    public override var hash: Int {
        sheetNames.hashValue
    }
}

@objc(ImportLimits)
public final class ImportLimits: NSObject, NSSecureCoding, @unchecked Sendable {
    public static let supportsSecureCoding = true

    public let maxBytes: Int64
    public let maxRows: Int64
    public let maxColumns: Int
    public let maxCells: Int64
    public let timeoutSeconds: TimeInterval

    public init(maxBytes: Int64, maxRows: Int64, maxColumns: Int, maxCells: Int64, timeoutSeconds: TimeInterval) {
        self.maxBytes = maxBytes
        self.maxRows = maxRows
        self.maxColumns = maxColumns
        self.maxCells = maxCells
        self.timeoutSeconds = timeoutSeconds
    }

    public init?(coder: NSCoder) {
        maxBytes = coder.decodeInt64(forKey: "maxBytes")
        maxRows = coder.decodeInt64(forKey: "maxRows")
        maxColumns = coder.decodeInteger(forKey: "maxColumns")
        maxCells = coder.decodeInt64(forKey: "maxCells")
        timeoutSeconds = coder.decodeDouble(forKey: "timeoutSeconds")
    }

    public func encode(with coder: NSCoder) {
        coder.encode(maxBytes, forKey: "maxBytes")
        coder.encode(maxRows, forKey: "maxRows")
        coder.encode(maxColumns, forKey: "maxColumns")
        coder.encode(maxCells, forKey: "maxCells")
        coder.encode(timeoutSeconds, forKey: "timeoutSeconds")
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ImportLimits else { return false }
        return maxBytes == other.maxBytes
            && maxRows == other.maxRows
            && maxColumns == other.maxColumns
            && maxCells == other.maxCells
            && timeoutSeconds == other.timeoutSeconds
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(maxBytes)
        hasher.combine(maxRows)
        hasher.combine(maxColumns)
        hasher.combine(maxCells)
        hasher.combine(timeoutSeconds)
        return hasher.finalize()
    }
}

@objc(ImportWarning)
public final class ImportWarning: NSObject, NSSecureCoding, @unchecked Sendable {
    public static let supportsSecureCoding = true

    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }

    public init?(coder: NSCoder) {
        guard
            let code = coder.decodeObject(of: NSString.self, forKey: "code") as String?,
            let message = coder.decodeObject(of: NSString.self, forKey: "message") as String?
        else {
            return nil
        }
        self.code = code
        self.message = message
    }

    public func encode(with coder: NSCoder) {
        coder.encode(code as NSString, forKey: "code")
        coder.encode(message as NSString, forKey: "message")
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ImportWarning else { return false }
        return code == other.code && message == other.message
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(code)
        hasher.combine(message)
        return hasher.finalize()
    }
}

@objc(ImportResult)
public final class ImportResult: NSObject, NSSecureCoding, @unchecked Sendable {
    public static let supportsSecureCoding = true

    public let csvURL: URL
    public let metadataURL: URL?
    public let warnings: [ImportWarning]
    public let rowCount: Int64
    public let columnCount: Int

    public init(csvURL: URL, metadataURL: URL?, warnings: [ImportWarning], rowCount: Int64, columnCount: Int) {
        self.csvURL = csvURL
        self.metadataURL = metadataURL
        self.warnings = warnings
        self.rowCount = rowCount
        self.columnCount = columnCount
    }

    public init?(coder: NSCoder) {
        guard
            let csvURL = coder.decodeObject(of: NSURL.self, forKey: "csvURL") as URL?,
            let warnings = coder.decodeObject(of: [NSArray.self, ImportWarning.self], forKey: "warnings") as? [ImportWarning]
        else {
            return nil
        }
        self.csvURL = csvURL
        metadataURL = coder.decodeObject(of: NSURL.self, forKey: "metadataURL") as URL?
        self.warnings = warnings
        rowCount = coder.decodeInt64(forKey: "rowCount")
        columnCount = coder.decodeInteger(forKey: "columnCount")
    }

    public func encode(with coder: NSCoder) {
        coder.encode(csvURL as NSURL, forKey: "csvURL")
        coder.encode(metadataURL as NSURL?, forKey: "metadataURL")
        coder.encode(warnings as NSArray, forKey: "warnings")
        coder.encode(rowCount, forKey: "rowCount")
        coder.encode(columnCount, forKey: "columnCount")
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ImportResult else { return false }
        return csvURL == other.csvURL
            && metadataURL == other.metadataURL
            && warnings == other.warnings
            && rowCount == other.rowCount
            && columnCount == other.columnCount
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(csvURL)
        hasher.combine(metadataURL)
        hasher.combine(warnings)
        hasher.combine(rowCount)
        hasher.combine(columnCount)
        return hasher.finalize()
    }
}

@objc(ImportError)
public final class ImportError: NSObject, NSSecureCoding, @unchecked Sendable {
    public static let supportsSecureCoding = true

    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }

    public init?(coder: NSCoder) {
        guard
            let code = coder.decodeObject(of: NSString.self, forKey: "code") as String?,
            let message = coder.decodeObject(of: NSString.self, forKey: "message") as String?
        else {
            return nil
        }
        self.code = code
        self.message = message
    }

    public func encode(with coder: NSCoder) {
        coder.encode(code as NSString, forKey: "code")
        coder.encode(message as NSString, forKey: "message")
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ImportError else { return false }
        return code == other.code && message == other.message
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(code)
        hasher.combine(message)
        return hasher.finalize()
    }
}
