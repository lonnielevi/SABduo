import Foundation

/// Standard Newznab top-level categories: icons for any indexer's tree, and a fallback when caps fail.
nonisolated enum SearchCategory: Int, CaseIterable, Identifiable, Sendable {
    case all = 0
    case movies = 2000
    case tv = 5000
    case audio = 3000
    case books = 7000
    case pc = 4000
    case console = 1000
    case xxx = 6000
    case misc = 8000

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .all: "All"
        case .movies: "Movies"
        case .tv: "TV"
        case .audio: "Audio"
        case .books: "Books"
        case .pc: "PC"
        case .console: "Console"
        case .xxx: "XXX"
        case .misc: "Misc"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .movies: "film"
        case .tv: "tv"
        case .audio: "music.note"
        case .books: "book"
        case .pc: "desktopcomputer"
        case .console: "gamecontroller"
        case .xxx: "eye.slash"
        case .misc: "shippingbox"
        }
    }
}

nonisolated struct SearchResult: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    /// Direct NZB download URL (includes the indexer API key), handed to SABnzbd's `addurl`.
    var nzbURL: URL
    var detailsURL: URL?
    var published: Date?
    var size: Int64
    var category: String
    var description: String?
    /// Every `newznab:attr` on the item (size, files, group, poster, imdb, …).
    var attributes: [String: String] = [:]

    var grabs: Int? { attributes["grabs"].flatMap(Int.init) }
    /// The ID `t=details` expects; feeds put it in an attr or as the guid's last path component.
    var newznabID: String { attributes["guid"] ?? URL(string: id)?.lastPathComponent ?? id }

    /// Numeric IMDb ID zero-padded to at least 7 digits ("0133093"), as indexers store it.
    var imdbID: String? {
        guard var value = attributes["imdb"]?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if value.hasPrefix("tt") { value.removeFirst(2) }
        guard let number = Int(value), number > 0 else { return nil }
        return String(repeating: "0", count: max(0, 7 - value.count)) + value
    }

    /// Poster candidates, best first: the indexer's `coverurl`, then the cover path
    /// Newznab-family sites serve for movies (`/covers/movies/<imdb>-cover.jpg`).
    func posterURLs(siteURL: URL?) -> [URL] {
        var urls: [URL] = []
        if let cover = attributes["coverurl"].flatMap(URL.init(string:)), cover.scheme?.hasPrefix("http") == true {
            urls.append(cover)
        }
        if let imdbID, let siteURL {
            urls.append(siteURL.appending(path: "covers/movies/\(imdbID)-cover.jpg"))
        }
        return urls
    }
}

/// A favorited search term, optionally scoped to a category.
nonisolated struct SavedSearch: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var query: String
    var category: IndexerCategory?

    func matches(query other: String, category otherCategory: IndexerCategory?) -> Bool {
        query.caseInsensitiveCompare(other) == .orderedSame && category?.id == otherCategory?.id
    }
}

nonisolated struct SearchPage: Sendable {
    var results: [SearchResult]
    var offset: Int
    /// Total matches reported by the indexer, if it says.
    var total: Int?
    var apiLimits: APILimits?
}
