// Run with Xcode's SwiftSyntax libraries (see --help). This tool never evaluates source expressions.
import Foundation
import SwiftParser
import SwiftSyntax

let supportedLanguageCodes = ["en", "ko", "ja", "zh-Hans", "zh-Hant", "fr", "es", "de", "pt-BR", "it", "ru", "vi", "id", "th", "pl", "nl"]

struct CatalogFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

struct Entry: Codable {
    let key: String
    let korean: String
    let location: String
    let usesPrintf: Bool
}

final class CatalogVisitor: SyntaxVisitor {
    var entries: [Entry] = []
    var failures: [String] = []
    let file: String
    let locations: SourceLocationConverter

    init(file: String, tree: SourceFileSyntax) {
        self.file = file
        locations = SourceLocationConverter(fileName: file, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let member = node.calledExpression.as(MemberAccessExprSyntax.self),
              member.base?.trimmedDescription == "L", member.declName.baseName.text == "t" else {
            return .visitChildren
        }
        let location = locations.location(for: node.positionAfterSkippingLeadingTrivia)
        let label = "\(file):\(location.line)"
        do {
            let arguments = Array(node.arguments)
            guard arguments.count == 2,
                  let english = arguments[0].expression.as(StringLiteralExprSyntax.self),
                  let korean = arguments[1].expression.as(StringLiteralExprSyntax.self) else {
                throw CatalogFailure("L.t requires two string literals, not expanded String values")
            }
            let expressions = english.segments.compactMap { $0.as(ExpressionSegmentSyntax.self) }.map(expressionIdentity)
            let englishTemplate = try template(english, expressions: expressions, reorder: false)
            let koreanTemplate = try template(korean, expressions: expressions, reorder: true)
            let usesPrintf = node.parent?.as(LabeledExprSyntax.self)?.label?.text == "format"
            entries.append(Entry(key: englishTemplate, korean: koreanTemplate, location: label, usesPrintf: usesPrintf))
        } catch {
            failures.append("\(label): \(error)")
        }
        return .visitChildren
    }

    private func expressionIdentity(_ segment: ExpressionSegmentSyntax) -> String {
        segment.expressions.tokens(viewMode: .sourceAccurate).map(\.text).joined(separator: "\u{1f}")
    }

    private func template(_ literal: StringLiteralExprSyntax, expressions: [String], reorder: Bool) throws -> String {
        var rewritten = literal
        let sentinel = "NANUM_INTERPOLATION_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))_"
        var replacements: [(String, Int)] = []
        var seen: [String: Int] = [:]
        var ordinal = 0
        rewritten.segments = StringLiteralSegmentListSyntax(try literal.segments.map { segment in
            guard let expression = segment.as(ExpressionSegmentSyntax.self) else { return segment }
            let index: Int
            if reorder {
                let identity = expressionIdentity(expression)
                let matches = expressions.indices.filter { expressions[$0] == identity }
                guard !matches.isEmpty else {
                    throw CatalogFailure("Korean interpolation does not match an English expression: \(expression.trimmedDescription)")
                }
                let occurrence = seen[identity, default: 0]
                index = matches[min(occurrence, matches.count - 1)]
                seen[identity] = occurrence + 1
            } else {
                index = ordinal
            }
            let marker = "\(sentinel)\(ordinal)_END"
            replacements.append((marker, index))
            ordinal += 1
            return .stringSegment(StringSegmentSyntax(content: .stringSegment(marker)))
        })
        guard var value = rewritten.representedLiteralValue else {
            throw CatalogFailure("Unable to decode Swift string literal")
        }
        value = value.replacingOccurrences(of: "{", with: "{{").replacingOccurrences(of: "}", with: "}}")
        for (marker, index) in replacements {
            value = value.replacingOccurrences(of: marker, with: "{\(index)}")
        }
        return value
    }
}

func placeholderIndices(_ template: String) throws -> [Int] {
    var indices: [Int] = []
    var cursor = template.startIndex
    while cursor < template.endIndex {
        let character = template[cursor]
        let next = template.index(after: cursor)
        if character == "{" {
            if next < template.endIndex, template[next] == "{" {
                cursor = template.index(after: next)
                continue
            }
            guard let end = template[next...].firstIndex(of: "}"),
                  !template[next..<end].isEmpty,
                  template[next..<end].allSatisfy({ $0.isASCII && $0.isNumber }),
                  let index = Int(template[next..<end]) else {
                throw CatalogFailure("Malformed placeholder in \(template)")
            }
            indices.append(index)
            cursor = template.index(after: end)
        } else if character == "}" {
            guard next < template.endIndex, template[next] == "}" else {
                throw CatalogFailure("Unescaped closing brace in \(template)")
            }
            cursor = template.index(after: next)
        } else {
            cursor = next
        }
    }
    return indices.sorted()
}

func printfConversions(_ template: String) -> [String] {
    let regex = try! NSRegularExpression(pattern: #"%(?:[0-9]+\$)?[-+ #0']*(?:[0-9]+|\*)?(?:\.(?:[0-9]+|\*))?(?:hh|ll|[hlLzjtq])?[@diuoxXfFeEgGaAcCsSpn%]"#)
    return regex.matches(in: template, range: NSRange(template.startIndex..., in: template)).compactMap {
        guard let range = Range($0.range, in: template) else { return nil }
        return String(template[range])
    }
}

func saveJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(value)
    data.append(0x0a)
    try data.write(to: url, options: .atomic)
}

func run() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    if args.contains("--help") {
        print("""
        Usage: swift -I <toolchain>/usr/lib/swift/host -L <toolchain>/usr/lib/swift/host \
        -lSwiftSyntax -lSwiftParser Scripts/localization-catalog.swift --extract|--check [package-root]
        Run from NanumCsvViewerMac, or supply its path as package-root.
        --extract writes en.json and ko.json from all source L.t calls; existing non-English catalogs are untouched.
        --check validates source/catalog parity, every supported language, placeholders, and printf conversions.
        Templates use numbered {0} placeholders; literal braces are doubled as {{ and }}.
        Interpolation expressions are parsed with SwiftSyntax and matched by Swift token identity, including reordered Korean arguments.
        Conflicting Korean translations for a shared English key are reported; the most frequent variant wins (lexical tie-break).
        """)
        return
    }
    guard args.first == "--extract" || args.first == "--check" else { throw CatalogFailure("Expected --extract or --check; use --help") }
    let root = URL(fileURLWithPath: args.count > 1 ? args[1] : FileManager.default.currentDirectoryPath, isDirectory: true)
    let sourceRoot = root.appendingPathComponent("Sources/NanumCsvViewerMac", isDirectory: true)
    let resourceRoot = sourceRoot.appendingPathComponent("Resources/Localization", isDirectory: true)
    guard let files = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil) else { throw CatalogFailure("Cannot enumerate \(sourceRoot.path)") }
    var entries: [Entry] = []
    var failures: [String] = []
    let swiftFiles = files.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" && $0.lastPathComponent != "Localization.swift" }.sorted { $0.path < $1.path }
    for file in swiftFiles {
        let source = try String(contentsOf: file, encoding: .utf8)
        let tree = Parser.parse(source: source)
        guard !tree.hasError else { throw CatalogFailure("Swift parse error in \(file.path)") }
        let visitor = CatalogVisitor(file: file.lastPathComponent, tree: tree)
        visitor.walk(tree)
        entries += visitor.entries
        failures += visitor.failures
    }
    guard failures.isEmpty else { throw CatalogFailure(failures.joined(separator: "\n")) }
    let grouped = Dictionary(grouping: entries, by: \.key)
    let english = grouped.mapValues { $0[0].key }
    // A prose percentage ("95% CI") is not a printf conversion. Only format:
    // arguments have printf semantics; preserve their conversion order as well as types.
    let printfKeys = Set(entries.filter(\.usesPrintf).map(\.key))
    var korean: [String: String] = [:]
    for key in grouped.keys.sorted() {
        let variants = Dictionary(grouping: grouped[key]!, by: \.korean)
        let ordered = variants.keys.sorted {
            let firstCount = variants[$0]!.count
            let secondCount = variants[$1]!.count
            return firstCount == secondCount ? $0 < $1 : firstCount > secondCount
        }
        korean[key] = ordered[0]
        if ordered.count > 1 {
            let details = ordered.map { "\($0.debugDescription) at \(variants[$0]!.map(\.location).joined(separator: ", "))" }.joined(separator: "; ")
            print("Conflict \(key.debugDescription): \(details). Selected \(ordered[0].debugDescription)")
        }
    }
    for (key, value) in korean {
        guard try placeholderIndices(key) == placeholderIndices(value) else { failures.append("ko: placeholder mismatch for \(key)"); continue }
        if printfKeys.contains(key), printfConversions(key) != printfConversions(value) { failures.append("ko: printf mismatch for \(key)") }
    }
    guard failures.isEmpty else { throw CatalogFailure(failures.joined(separator: "\n")) }
    if args.first == "--extract" {
        try FileManager.default.createDirectory(at: resourceRoot, withIntermediateDirectories: true)
        try saveJSON(english, to: resourceRoot.appendingPathComponent("en.json"))
        try saveJSON(korean, to: resourceRoot.appendingPathComponent("ko.json"))
        print("Extracted \(entries.count) calls / \(english.count) keys to \(resourceRoot.path)")
    } else {
        for code in supportedLanguageCodes {
            let url = resourceRoot.appendingPathComponent("\(code).json")
            guard let data = try? Data(contentsOf: url) else { failures.append("Missing catalog: \(code)"); continue }
            let catalog = try JSONDecoder().decode([String: String].self, from: data)
            let missing = Set(english.keys).subtracting(catalog.keys).sorted()
            let extra = Set(catalog.keys).subtracting(english.keys).sorted()
            failures += missing.map { "\(code): missing \($0)" }
            failures += extra.map { "\(code): obsolete \($0)" }
            for (key, value) in catalog {
                if value.isEmpty { failures.append("\(code): empty translation for \(key)") }
                if try placeholderIndices(key) != placeholderIndices(value) { failures.append("\(code): placeholder mismatch for \(key)") }
                if printfKeys.contains(key), printfConversions(key) != printfConversions(value) { failures.append("\(code): printf mismatch for \(key)") }
            }
            if code == "en", catalog != english { failures.append("English catalog differs from source extraction") }
            if code == "ko", catalog != korean { failures.append("Korean catalog differs from source extraction") }
        }
        guard failures.isEmpty else { throw CatalogFailure(failures.joined(separator: "\n")) }
        print("Validated \(supportedLanguageCodes.count) languages / \(english.count) keys / \(entries.count) calls")
    }
}

do { try run() } catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
