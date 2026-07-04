import Foundation

/// Multiple named saved views (bookmarks) per file path. Names are the
/// bookmark identity: saving with an existing name replaces it in place and
/// marks it most-recent. Replaces the v1.7 one-view-per-file storage.
public struct SavedViewStore: Equatable, Codable, Sendable {
    private var viewsByPath: [String: [SavedCsvView]]
    // Names in most-recent-first order per path, so deleting the current
    // most-recent bookmark falls back to the next-most-recently-saved one
    // rather than to display (insertion) order.
    private var recencyByPath: [String: [String]]

    public init() {
        viewsByPath = [:]
        recencyByPath = [:]
    }

    private enum CodingKeys: String, CodingKey {
        case viewsByPath
        case recencyByPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        viewsByPath = try container.decodeIfPresent([String: [SavedCsvView]].self, forKey: .viewsByPath) ?? [:]
        recencyByPath = try container.decodeIfPresent([String: [String]].self, forKey: .recencyByPath) ?? [:]
    }

    /// Rebuilds the store from the legacy `[path: base64(SavedCsvView)]` map.
    /// Undecodable entries are skipped so a corrupt legacy value cannot block
    /// the migration.
    public init(migratingLegacyMap legacyMap: [String: String]) {
        self.init()
        for (path, encoded) in legacyMap {
            guard let data = Data(base64Encoded: encoded),
                  let view = try? JSONDecoder().decode(SavedCsvView.self, from: data) else {
                continue
            }
            save(view, forPath: path)
        }
    }

    public mutating func save(_ view: SavedCsvView, forPath path: String) {
        var views = viewsByPath[path] ?? []
        if let index = views.firstIndex(where: { $0.name == view.name }) {
            views[index] = view
        } else {
            views.append(view)
        }
        viewsByPath[path] = views
        var recency = recencyByPath[path] ?? []
        recency.removeAll { $0 == view.name }
        recency.insert(view.name, at: 0)
        recencyByPath[path] = recency
    }

    public mutating func remove(name: String, forPath path: String) {
        guard var views = viewsByPath[path] else { return }
        views.removeAll { $0.name == name }
        if views.isEmpty {
            viewsByPath[path] = nil
            recencyByPath[path] = nil
        } else {
            viewsByPath[path] = views
            var recency = recencyByPath[path] ?? []
            recency.removeAll { $0 == name }
            recencyByPath[path] = recency
        }
    }

    public func views(forPath path: String) -> [SavedCsvView] {
        viewsByPath[path] ?? []
    }

    public func names(forPath path: String) -> [String] {
        views(forPath: path).map(\.name)
    }

    public func view(named name: String, forPath path: String) -> SavedCsvView? {
        views(forPath: path).first { $0.name == name }
    }

    public func mostRecent(forPath path: String) -> SavedCsvView? {
        guard let name = recencyByPath[path]?.first(where: { view(named: $0, forPath: path) != nil }) else { return nil }
        return view(named: name, forPath: path)
    }
}
