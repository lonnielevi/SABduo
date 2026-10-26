import SwiftUI

/// Header over a search's results, with the heart that saves it. It lives in the list rather than
/// the toolbar, since an iPhone hides toolbar buttons while the search field is active.
struct ResultsHeader: View {
    @Environment(AppStore.self) private var store
    let query: String
    let category: IndexerCategory?

    var body: some View {
        let isFavorite = store.search.favorite(query: query, category: category) != nil
        VStack(alignment: .leading, spacing: 6) {
            Text("Results for “\(query)”")
                .lineLimit(1)
            // On a line of its own, so the query has the whole width.
            Button {
                store.search.toggleFavorite(query: query, category: category)
            } label: {
                Label(isFavorite ? "Favorited" : "Favorite this search", systemImage: isFavorite ? "heart.fill" : "heart")
            }
            .buttonStyle(.borderless)
            .tint(isFavorite ? .yellow : nil)
            .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
            .sensoryFeedback(.selection, trigger: isFavorite)
        }
    }
}

struct FavoriteRow: View {
    let saved: SavedSearch

    var body: some View {
        Label {
            Text(saved.query)
            Text(saved.category?.path ?? "All Categories")
        } icon: {
            Image(systemName: "heart").foregroundStyle(Color.accentColor)
        }
    }
}
