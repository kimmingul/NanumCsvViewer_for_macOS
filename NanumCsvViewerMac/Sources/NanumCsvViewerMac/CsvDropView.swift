import AppKit

final class CsvDropView: NSView {
    var dropHandler: ((_ urls: [URL], _ text: String?) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .string])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        canImport(sender.draggingPasteboard) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        let urls = fileURLs(from: pasteboard)
        let text = pasteboard.string(forType: .string)
        guard !urls.isEmpty || text?.isEmpty == false else { return false }
        dropHandler?(urls, text)
        return true
    }

    private func canImport(_ pasteboard: NSPasteboard) -> Bool {
        !fileURLs(from: pasteboard).isEmpty || pasteboard.string(forType: .string)?.isEmpty == false
    }

    private func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        if let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) {
            let urls = objects.compactMap { object -> URL? in
                if let url = object as? URL {
                    return url
                }
                if let url = object as? NSURL {
                    return url as URL
                }
                return nil
            }
            if !urls.isEmpty {
                return urls
            }
        }
        if let urlString = pasteboard.string(forType: .fileURL),
           let url = URL(string: urlString),
           url.isFileURL {
            return [url]
        }
        return []
    }
}
