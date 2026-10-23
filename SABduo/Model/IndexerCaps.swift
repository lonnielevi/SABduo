import Foundation

/// What an indexer advertises through `t=caps`.
nonisolated struct IndexerCaps: Equatable, Sendable {
    var title = ""
    var version = ""
    var appVersion = ""
    var email = ""
    var siteURL: URL?
    var imageURL: URL?
    var maxResults: Int?
    var defaultResults: Int?
    var registrationAvailable: Bool?
    var registrationOpen: Bool?
    var searchModes: [SearchCapability] = []
    var categories: [IndexerCategory] = []
    var groupCount = 0
    var genreCount = 0
    var apiLimits: APILimits?
}

nonisolated struct SearchCapability: Identifiable, Equatable, Sendable {
    /// Element name, e.g. "search", "tv-search", "movie-search".
    var name: String
    var available: Bool
    var parameters: [String]

    var id: String { name }

    var label: String {
        name.replacingOccurrences(of: "-", with: " ").capitalized
    }
}

nonisolated struct IndexerCategory: Identifiable, Hashable, Codable, Sendable {
    var id: Int
    var name: String
    var detail: String?
    var parentName: String?
    var subcategories: [IndexerCategory] = []

    /// "Movies › HD" for a subcategory, "Movies" for a top-level one.
    var path: String { parentName.map { "\($0) › \(name)" } ?? name }

    /// Newznab category IDs group by thousand: 2040 (Movies › HD) belongs to 2000.
    var systemImage: String {
        SearchCategory(rawValue: id / 1000 * 1000)?.systemImage ?? "folder"
    }

    /// Used when an indexer's caps can't be loaded.
    static let standard: [IndexerCategory] = SearchCategory.allCases
        .filter { $0 != .all }
        .map { IndexerCategory(id: $0.rawValue, name: $0.label) }
}

/// API/grab usage. Reported by some indexers in caps or as `newznab:apilimits` in results.
nonisolated struct APILimits: Equatable, Sendable {
    var apiCurrent: Int?
    var apiMax: Int?
    var grabCurrent: Int?
    var grabMax: Int?

    init?(_ attributes: [String: String]) {
        apiCurrent = attributes["apicurrent"].flatMap(Int.init)
        apiMax = attributes["apimax"].flatMap(Int.init)
        grabCurrent = attributes["grabcurrent"].flatMap(Int.init)
        grabMax = attributes["grabmax"].flatMap(Int.init)
        if apiCurrent == nil, apiMax == nil, grabCurrent == nil, grabMax == nil { return nil }
    }
}
