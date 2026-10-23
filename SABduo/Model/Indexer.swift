import Foundation

/// A Newznab-compatible indexer (NZB.life, NZBgeek, DrunkenSlug, …). The API key lives in the Keychain.
nonisolated struct Indexer: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    /// What the user typed, e.g. "nzb.life" or "https://api.nzb.life/api".
    var address: String

    static let nzbLife = Indexer(name: "NZB.life", address: "https://api.nzb.life/api")

    var keychainAccount: String { "indexer.\(id.uuidString)" }

    /// Newznab endpoints live at `<host>/api`; accept a bare host or a full URL.
    var apiURL: URL? {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard var components = URLComponents(string: text), components.host?.isEmpty == false else { return nil }
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix("/api") { path += "/api" }
        components.path = path
        components.query = nil
        return components.url
    }
}

extension Indexer {
    private static let defaultsKey = "indexers"

    static func loadAll(from defaults: UserDefaults = .standard) -> [Indexer] {
        guard let data = defaults.data(forKey: defaultsKey),
              let indexers = try? JSONDecoder().decode([Indexer].self, from: data)
        else { return [] }
        return indexers
    }

    static func saveAll(_ indexers: [Indexer], to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(indexers) {
            defaults.set(data, forKey: defaultsKey)
        }
    }
}
