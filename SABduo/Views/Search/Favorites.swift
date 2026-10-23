import SwiftUI

/// Stars the search a feed is showing.
struct FavoriteButton: View {
    @Environment(AppStore.self) private var store
    let query: String
    let category: IndexerCategory?

    var body: some View {
        let isFavorite = store.search.favorite(query: query, category: category) != nil
        Button(isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: isFavorite ? "star.fill" : "star") {
            store.search.toggleFavorite(query: query, category: category)
        }
        .tint(isFavorite ? .yellow : nil)
        .sensoryFeedback(.selection, trigger: isFavorite)
    }
}

struct FavoriteRow: View {
    let saved: SavedSearch

    var body: some View {
        Label {
            Text(saved.query)
            Text(saved.category?.path ?? "All Categories")
        } icon: {
            Image(systemName: "star.fill").foregroundStyle(.yellow)
        }
    }
}

/// Favorites offered while typing in a search field; tapping one runs it.
struct FavoriteSuggestions: View {
    @Environment(AppStore.self) private var store
    let typed: String
    /// Limit to one category's favorites (a browse screen), or nil for all of them.
    var category: IndexerCategory?
    let run: (SavedSearch) -> Void

    var body: some View {
        let needle = typed.trimmingCharacters(in: .whitespaces)
        let matches = store.search.favorites.filter { saved in
            (category == nil || saved.category?.id == category?.id)
                && (needle.isEmpty || saved.query.localizedCaseInsensitiveContains(needle))
        }
        if !matches.isEmpty {
            Section("Favorites") {
                ForEach(matches) { saved in
                    Button { run(saved) } label: { FavoriteRow(saved: saved) }
                }
            }
        }
    }
}
