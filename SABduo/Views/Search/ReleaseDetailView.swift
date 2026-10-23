import SwiftUI

/// Everything the indexer knows about one release, with send controls.
struct ReleaseDetailView: View {
    @Environment(AppStore.self) private var store
    @State private var release: SearchResult
    @State private var isLoadingDetails = false

    init(result: SearchResult) {
        _release = State(initialValue: result)
    }

    /// Attributes shown in their own rows; the rest go under "All Attributes".
    private static let featuredKeys: Set<String> = [
        "size", "grabs", "files", "comments", "group", "poster", "password", "usenetdate", "guid", "category",
        "imdb", "imdbtitle", "imdbyear", "imdbscore", "tvdbid", "tvmazeid", "rageid", "tvtitle", "season", "episode",
        "genre", "year", "rating",
    ]

    var body: some View {
        let sent = store.search.sentIDs.contains(release.id)
        let a = release.attributes

        Form {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    PosterView(urls: release.posterURLs(siteURL: store.search.siteURL(for: store.activeIndexer)))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(release.title)
                            .font(.headline)
                            .textSelection(.enabled)
                        if let title = a["imdbtitle"] {
                            Text([title, a["imdbyear"]].compactMap { $0 }.joined(separator: " · "))
                                .font(.subheadline.weight(.medium))
                        }
                        if !release.category.isEmpty {
                            Text(release.category).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
            }

            Section {
                Button(sent ? "Sent to SABnzbd" : "Send to SABnzbd", systemImage: sent ? "checkmark.circle.fill" : "arrow.down.circle") {
                    Task { await store.send(release) }
                }
                .disabled(sent || !store.isConfigured)
                Menu {
                    SendMenu(result: release)
                } label: {
                    Label("Send with Priority…", systemImage: "flag")
                }
                .disabled(!store.isConfigured)
            }

            Section("Release") {
                if release.size > 0 {
                    LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: release.size, countStyle: .file))
                }
                if let published = release.published {
                    LabeledContent("Posted") {
                        VStack(alignment: .trailing) {
                            Text(published.formatted(date: .abbreviated, time: .shortened))
                            Text(published, format: .relative(presentation: .named)).font(.caption)
                        }
                    }
                }
                row("Grabs", a["grabs"])
                row("Files", a["files"])
                row("Comments", a["comments"])
                row("Group", a["group"])
                row("Poster", a["poster"])
                if let password = a["password"] {
                    LabeledContent("Password", value: Self.passwordLabel(password))
                }
            }

            if Self.hasMedia(a) {
                Section("Media") {
                    row("Title", a["imdbtitle"] ?? a["tvtitle"])
                    row("Year", a["imdbyear"] ?? a["year"])
                    row("Genre", a["genre"])
                    row("Rating", a["imdbscore"] ?? a["rating"])
                    if let season = a["season"] {
                        LabeledContent("Episode", value: [season, a["episode"]].compactMap { $0 }.joined(separator: " "))
                    }
                    if let imdb = Self.imdbURL(a["imdb"]) {
                        Link(destination: imdb) { Label("IMDb", systemImage: "film") }
                    }
                    if let id = a["tvdbid"], id != "0", let url = URL(string: "https://thetvdb.com/dereferrer/series/\(id)") {
                        Link(destination: url) { Label("TheTVDB", systemImage: "tv") }
                    }
                    if let id = a["tvmazeid"], id != "0", let url = URL(string: "https://www.tvmaze.com/shows/\(id)") {
                        Link(destination: url) { Label("TVmaze", systemImage: "tv") }
                    }
                }
            }

            if let description = release.description, description != release.title {
                Section("Description") {
                    Text(description).font(.callout).textSelection(.enabled)
                }
            }

            if let details = release.detailsURL {
                Section {
                    Link(destination: details) {
                        Label("Open on \(store.activeIndexer?.name ?? "Indexer")", systemImage: "safari")
                    }
                }
            }

            let extra = a.filter { !Self.featuredKeys.contains($0.key) }.sorted { $0.key < $1.key }
            if !extra.isEmpty {
                Section {
                    DisclosureGroup("All Attributes") {
                        ForEach(extra, id: \.key) { key, value in
                            LabeledContent(key, value: value)
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .navigationTitle("Release")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isLoadingDetails {
                ToolbarItem(placement: .topBarTrailing) { ProgressView() }
            }
        }
        .task(id: release.id) { await loadDetails() }
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(title, value: value)
        }
    }

    /// Search results already carry extended attributes on most indexers; `t=details` fills any gaps.
    /// Best effort: on failure the search result's data stays.
    private func loadDetails() async {
        guard let client = store.newznabClient(for: store.activeIndexer) else { return }
        isLoadingDetails = true
        defer { isLoadingDetails = false }
        guard let details = try? await client.details(id: release.newznabID) else { return }
        release.attributes.merge(details.attributes) { _, new in new }
        if release.size == 0 { release.size = details.size }
        release.published = release.published ?? details.published
        release.description = details.description ?? release.description
        release.detailsURL = release.detailsURL ?? details.detailsURL
        if release.category.isEmpty { release.category = details.category }
    }

    private static func hasMedia(_ a: [String: String]) -> Bool {
        ["imdb", "imdbtitle", "tvdbid", "tvmazeid", "tvtitle", "season", "genre", "year", "rating", "imdbscore"]
            .contains { a[$0]?.isEmpty == false && a[$0] != "0" }
    }

    /// Newznab `password`: 0 none, 1 passworded, 2 possibly passworded.
    private static func passwordLabel(_ value: String) -> String {
        switch value {
        case "0": "None"
        case "1": "Passworded"
        case "2": "Possibly passworded"
        default: value
        }
    }

    /// Indexers send IMDb IDs with or without the "tt" prefix.
    private static func imdbURL(_ value: String?) -> URL? {
        guard let value, !value.isEmpty, value != "0" else { return nil }
        let id = value.hasPrefix("tt") ? value : "tt" + value
        return URL(string: "https://www.imdb.com/title/\(id)/")
    }
}
