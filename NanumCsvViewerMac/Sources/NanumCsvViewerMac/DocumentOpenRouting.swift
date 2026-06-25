import Foundation

struct DocumentOpenRoute: Equatable {
    let currentWindowURL: URL?
    let additionalWindowURLs: [URL]
}

enum DocumentOpenRouting {
    static func route(urls: [URL], currentWindowHasDocument: Bool) -> DocumentOpenRoute {
        guard !urls.isEmpty else {
            return DocumentOpenRoute(currentWindowURL: nil, additionalWindowURLs: [])
        }

        if currentWindowHasDocument {
            return DocumentOpenRoute(currentWindowURL: nil, additionalWindowURLs: urls)
        }

        return DocumentOpenRoute(currentWindowURL: urls[0], additionalWindowURLs: Array(urls.dropFirst()))
    }
}
