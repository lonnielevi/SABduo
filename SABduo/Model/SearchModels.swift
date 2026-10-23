import Foundation

/// Standard Newznab top-level categories.
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
    var grabs: Int?
}

nonisolated struct SearchPage: Sendable {
    var results: [SearchResult]
    var offset: Int
    /// Total matches reported by the indexer, if it says.
    var total: Int?
}
