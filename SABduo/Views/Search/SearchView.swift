import SwiftUI

struct SearchView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.rootActions) private var actions
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var search = store.search
        let indexer = store.activeIndexer
        let client = store.newznabClient(for: indexer)

        List {
            ForEach(search.results) { result in
                SearchResultRow(result: result, isSent: search.sentIDs.contains(result.id)) {
                    Task { await store.send(result) }
                }
                .swipeActions(edge: .leading) {
                    Button("Send", systemImage: "arrow.down.circle") {
                        Task { await store.send(result) }
                    }
                    .tint(.accentColor)
                }
                .contextMenu {
                    Section("Send to SABnzbd") {
                        ForEach(Priority.allCases) { priority in
                            Button("\(priority.label) Priority", systemImage: priority == .normal ? "arrow.down.circle" : "flag") {
                                Task { await store.send(result, priority: priority) }
                            }
                        }
                    }
                    if let details = result.detailsURL {
                        Button("Open on Indexer", systemImage: "safari") { openURL(details) }
                    }
                }
            }

            if search.canLoadMore {
                Button {
                    search.loadMore(using: client)
                } label: {
                    HStack {
                        Text("Load More")
                        Spacer()
                        if search.isLoadingMore { ProgressView() }
                    }
                }
                .disabled(search.isLoadingMore)
            }
        }
        .overlay { emptyState(indexer: indexer, client: client) }
        .searchable(text: $search.query, prompt: indexer.map { "Search \($0.name)" } ?? "Search")
        .onSubmit(of: .search) { search.submit(using: client) }
        .onChange(of: search.category) {
            // Re-run the current search in the new category; only costs an API hit if there's a search.
            if search.hasSearched { search.submit(using: client) }
        }
        .onChange(of: search.indexerID) {
            search.reset()
        }
        .navigationTitle("Search")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("Category", selection: $search.category) {
                        ForEach(SearchCategory.allCases) { category in
                            Label(category.label, systemImage: category.systemImage).tag(category)
                        }
                    }
                    if store.indexers.count > 1 {
                        Picker("Indexer", selection: $search.indexerID) {
                            ForEach(store.indexers) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                } label: {
                    Label(search.category.label, systemImage: search.category == .all
                        ? "line.3.horizontal.decrease.circle"
                        : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
    }

    @ViewBuilder
    private func emptyState(indexer: Indexer?, client: NewznabClient?) -> some View {
        let search = store.search
        if indexer == nil || client == nil {
            ContentUnavailableView {
                Label("No Indexer", systemImage: "magnifyingglass")
            } description: {
                Text("Add a Newznab indexer such as NZB.life with its API key.")
            } actions: {
                Button("Add Indexer", action: actions.showSettings)
            }
        } else if search.isSearching {
            ProgressView("Searching \(indexer?.name ?? "")…")
        } else if let error = search.errorMessage, search.results.isEmpty {
            ContentUnavailableView("Search Failed", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if let searched = search.searched, search.results.isEmpty {
            ContentUnavailableView.search(text: searched.query)
        } else if !search.hasSearched {
            ContentUnavailableView("Search \(indexer?.name ?? "")", systemImage: "magnifyingglass", description: Text("Results can be sent straight to SABnzbd."))
        }
    }
}
