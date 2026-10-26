import Foundation

/// A Newznab-compatible indexer (NZB.life, NZBgeek, DrunkenSlug, …). The API key lives in the Keychain.
nonisolated struct Indexer: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    /// What the user typed, e.g. "nzb.life" or "https://api.nzb.life/api".
    var address: String

    /// Well-known Newznab indexers to pick from when adding one, with their API addresses as
    /// Prowlarr lists them.
    static let presets: [Indexer] = [
        Indexer(name: "abNZB", address: "https://abnzb.com/api"),
        Indexer(name: "altHUB", address: "https://api.althub.co.za/api"),
        Indexer(name: "AnimeTosho", address: "https://feed.animetosho.org/api"),
        Indexer(name: "DOGnzb", address: "https://api.dognzb.cr/api"),
        Indexer(name: "DrunkenSlug", address: "https://drunkenslug.com/api"),
        Indexer(name: "GingaDADDY", address: "https://www.gingadaddy.com/api"),
        Indexer(name: "Miatrix", address: "https://www.miatrix.com/api"),
        Indexer(name: "NinjaCentral", address: "https://ninjacentral.co.za/api"),
        Indexer(name: "NZB.life", address: "https://api.nzb.life/api"),
        Indexer(name: "NZBCat", address: "https://nzb.cat/api"),
        Indexer(name: "NZBFinder", address: "https://nzbfinder.ws/api"),
        Indexer(name: "NZBgeek", address: "https://api.nzbgeek.info/api"),
        Indexer(name: "NZBNDX", address: "https://www.nzbndx.com/api"),
        Indexer(name: "NzbNoob", address: "https://www.nzbnoob.com/api"),
        Indexer(name: "NzbPlanet", address: "https://api.nzbplanet.net/api"),
        Indexer(name: "NZBStars", address: "https://nzbstars.com/api"),
        Indexer(name: "Tabula Rasa", address: "https://www.tabula-rasa.pw/api/v1/api"),
    ]

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
