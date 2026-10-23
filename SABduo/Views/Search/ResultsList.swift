import SwiftUI

/// Rows for a feed's results plus "Load More". Use inside a `List`.
struct ResultsList: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    let feed: ResultFeed
    let client: NewznabClient?

    var body: some View {
        ForEach(feed.results) { result in
            NavigationLink(value: SearchRoute.release(result)) {
                SearchResultRow(result: result, isSent: store.search.sentIDs.contains(result.id)) {
                    Task { await store.send(result) }
                }
            }
            .swipeActions(edge: .leading) {
                Button("Send", systemImage: "arrow.down.circle") {
                    Task { await store.send(result) }
                }
                .tint(.accentColor)
            }
            .contextMenu {
                SendMenu(result: result)
                if let details = result.detailsURL {
                    Button("Open on Indexer", systemImage: "safari") { openURL(details) }
                }
            }
        }

        if feed.canLoadMore {
            Button {
                feed.loadMore(using: client)
            } label: {
                HStack {
                    Text("Load More")
                    Spacer()
                    if feed.isLoadingMore { ProgressView() }
                }
            }
            .disabled(feed.isLoadingMore)
        }
    }
}

/// Send with an explicit priority.
struct SendMenu: View {
    @Environment(AppStore.self) private var store
    let result: SearchResult

    var body: some View {
        Section("Send to SABnzbd") {
            ForEach(Priority.allCases) { priority in
                Button("\(priority.label) Priority", systemImage: priority == .normal ? "arrow.down.circle" : "flag") {
                    Task { await store.send(result, priority: priority) }
                }
            }
        }
    }
}

/// Loading, error and empty states for a feed, shown as an overlay.
struct FeedStatus: View {
    let feed: ResultFeed
    let name: String

    var body: some View {
        if feed.results.isEmpty {
            if feed.isLoading {
                ProgressView("Loading \(name)…")
            } else if let error = feed.errorMessage {
                ContentUnavailableView("Couldn't Load Results", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if let query = feed.loadedQuery {
                if query.isEmpty {
                    ContentUnavailableView("Nothing Here Yet", systemImage: "tray", description: Text("\(name) has no releases."))
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
    }
}
