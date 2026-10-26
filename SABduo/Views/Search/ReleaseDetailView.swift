import SwiftUI

/// Everything the indexer knows about one release, with send controls.
struct ReleaseDetailView: View {
    @Environment(AppStore.self) private var store
    @State private var release: SearchResult
    @State private var showingNFO = false

    init(result: SearchResult) {
        _release = State(initialValue: result)
    }

    /// Attributes shown in their own rows; the rest go under "All Attributes".
    private static let featuredKeys: Set<String> = [
        "size", "grabs", "files", "comments", "group", "poster", "password", "usenetdate", "guid", "category",
        "imdb", "imdbtitle", "imdbyear", "imdbscore", "tvdbid", "tvmazeid", "rageid", "tvtitle", "season", "episode",
        "genre", "year", "rating", "imdbtagline", "imdbplot", "imdbdirector", "imdbactors", "tvairdate", "backdropcoverurl",
        "video", "audio", "resolution", "framerate", "language", "subs", "nuked", "thumbsup", "thumbsdown", "nfo",
        "artist", "album", "label", "publisher", "tracks", "review", "author", "booktitle", "publishdate", "pages",
    ]

    var body: some View {
        let sent = store.search.sentIDs.contains(release.id)
        let a = release.attributes

        Form {
            Section {
                if let backdrop = a["backdropcoverurl"].flatMap(URL.init(string:)), backdrop.scheme?.hasPrefix("http") == true {
                    Backdrop(url: backdrop)
                }
                HStack(alignment: .top, spacing: 14) {
                    PosterView(urls: release.posterURLs(siteURL: store.search.siteURL(for: store.activeIndexer)))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(release.wrappingTitle)
                            .font(.headline)
                            .contextMenu {
                                Button("Copy Name", systemImage: "doc.on.doc") { UIPasteboard.general.string = release.title }
                            }
                        if let title = a["imdbtitle"] {
                            Text([title, a["imdbyear"]].compactMap { $0 }.joined(separator: " · "))
                                .font(.subheadline.weight(.medium))
                        }
                        if !release.category.isEmpty {
                            Text(release.category).font(.subheadline).foregroundStyle(.secondary)
                        }
                        let tags = release.releaseName.tags
                        if !tags.isEmpty {
                            FlowLayout(spacing: 6) {
                                ForEach(tags, id: \.self) { Tag(text: $0) }
                            }
                            .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
            }

            Section {
                if sent {
                    Label("Sent to SABnzbd", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Button(sent ? "Send Again" : "Send to SABnzbd", systemImage: sent ? "arrow.clockwise.circle" : "arrow.down.circle") {
                    Task { await store.send(release) }
                }
                .disabled(!store.isConfigured)
                Menu {
                    SendMenu(result: release)
                } label: {
                    Label("Send with Priority…", systemImage: "flag")
                }
                .disabled(!store.isConfigured)
            }

            Section("Release") {
                if let nuked = a["nuked"], nuked != "0" {
                    Label(nuked == "1" ? "Nuked" : "Nuked: \(nuked)", systemImage: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red)
                }
                if release.size > 0 {
                    row("Size", ByteCountFormatter.string(fromByteCount: release.size, countStyle: .file))
                }
                row("Posted", release.published?.formatted(date: .abbreviated, time: .omitted))
                // When the indexer picked it up, if that's notably later than the post.
                if let indexed = release.indexed, abs(indexed.timeIntervalSince(release.published ?? indexed)) > 3600 {
                    row("Indexed", indexed.formatted(date: .abbreviated, time: .omitted))
                }
                row("Release Group", release.releaseName.group)
                row("Grabs", a["grabs"])
                row("Files", a["files"])
                row("Comments", a["comments"])
                row("Newsgroup", a["group"])
                row("Poster", a["poster"])
                if let password = a["password"] {
                    row("Password", Self.passwordLabel(password))
                }
                if a["thumbsup"] != nil || a["thumbsdown"] != nil {
                    LabeledContent("Votes") {
                        HStack(spacing: 12) {
                            Label(a["thumbsup"] ?? "0", systemImage: "hand.thumbsup")
                            Label(a["thumbsdown"] ?? "0", systemImage: "hand.thumbsdown")
                        }
                        .labelStyle(.titleAndIcon)
                    }
                }
                // Fetched only when asked for: each is an API call against the indexer's limit.
                if a["nfo"] != "0" {
                    Button("View NFO", systemImage: "doc.plaintext") { showingNFO = true }
                }
            }

            // HDR comes from the release name: Newznab has no attribute for it.
            let hdr = release.releaseName.hdr
            let audio = audioFormat(a)
            if !hdr.isEmpty || audio != nil || ["video", "audio", "resolution", "framerate", "language", "subs"].contains(where: { a[$0]?.isEmpty == false }) {
                Section("Video & Audio") {
                    row("Resolution", a["resolution"])
                    row("Video", a["video"])
                    row(hdr.count > 1 ? "HDR Formats" : "HDR", hdr.isEmpty ? nil : hdr.joined(separator: ", "))
                    row("Frame Rate", a["framerate"])
                    row("Audio", audio)
                    row("Language", a["language"])
                    row("Subtitles", a["subs"])
                }
            }

            if Self.hasMedia(a) {
                Section("Media") {
                    row("Title", a["imdbtitle"] ?? a["tvtitle"])
                    row("Year", a["imdbyear"] ?? a["year"])
                    row("Genre", a["genre"])
                    row("Rating", a["imdbscore"] ?? a["rating"])
                    if let season = a["season"] {
                        row("Episode", [season, a["episode"]].compactMap { $0 }.joined(separator: " "))
                    }
                    row("Aired", a["tvairdate"])
                    row("Director", a["imdbdirector"])
                    row("Cast", a["imdbactors"])
                    if let tagline = a["imdbtagline"], !tagline.isEmpty {
                        Text(tagline).italic()
                    }
                    if let plot = a["imdbplot"], !plot.isEmpty {
                        Text(plot).font(.callout)
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

            if ["artist", "album", "label", "publisher", "tracks", "review"].contains(where: { a[$0]?.isEmpty == false }) {
                Section("Music") {
                    row("Artist", a["artist"])
                    row("Album", a["album"])
                    row("Label", a["label"])
                    row("Publisher", a["publisher"])
                    row("Tracks", a["tracks"])
                    if let review = a["review"], !review.isEmpty {
                        Text(review).font(.callout)
                    }
                }
            }

            if ["author", "booktitle", "publishdate", "pages"].contains(where: { a[$0]?.isEmpty == false }) {
                Section("Book") {
                    row("Title", a["booktitle"])
                    row("Author", a["author"])
                    row("Published", a["publishdate"])
                    row("Pages", a["pages"])
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
                            row(key, value)
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        // No title: the poster and release name lead the page, right under the buttons.
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.top, 8, for: .scrollContent)
        .task(id: release.id) { await loadDetails() }
        .sheet(isPresented: $showingNFO) {
            NFOSheet(release: release)
        }
    }

    /// The audio format, from the release name ("DD+ 5.1, Atmos"). Some indexers fill the
    /// `audio` attribute with the audio's languages instead, so it's used only when the name has
    /// nothing and it says something other than the language.
    private func audioFormat(_ a: [String: String]) -> String? {
        let fromName = release.releaseName.audio
        if !fromName.isEmpty { return fromName.joined(separator: ", ") }
        guard let audio = a["audio"], !audio.isEmpty, audio != a["language"] else { return nil }
        return audio
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            // Always side by side, a long value wrapping under itself, rather than a form row that
            // drops a long value below its label.
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(title)
                    .fixedSize()
                Spacer(minLength: 0)
                Text(value)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Search results already carry extended attributes on most indexers; `t=details` fills any gaps.
    /// Best effort: on failure the search result's data stays.
    private func loadDetails() async {
        guard let client = store.newznabClient(for: store.activeIndexer) else { return }
        guard let details = try? await client.details(id: release.newznabID) else { return }
        release.attributes.merge(details.attributes) { _, new in new }
        if release.size == 0 { release.size = details.size }
        // Details may know the Usenet date where the search only had the indexer's.
        if details.attributes["usenetdate"] != nil, let posted = details.published {
            release.published = posted
            release.indexed = release.indexed ?? details.indexed
        } else {
            release.published = release.published ?? details.published
        }
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

/// A wide image behind a film or show, above its poster.
private struct Backdrop: View {
    let url: URL

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Color.clear
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 8))
        .accessibilityHidden(true)
    }
}

/// Something the release name says about it: "2160p", "Dolby Vision".
private struct Tag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.fill.secondary, in: .capsule)
    }
}

/// Lays its views out in rows, wrapping to the next when one is full.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if let last = rows.last, last.width + spacing + size.width <= width {
                rows[rows.count - 1].indices.append(index)
                rows[rows.count - 1].width += spacing + size.width
                rows[rows.count - 1].height = max(last.height, size.height)
            } else {
                rows.append(([index], size.width, size.height))
            }
        }
        return rows
    }
}

/// The release's NFO, fetched when opened, in a fixed-width font so its art lines up.
private struct NFOSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let release: SearchResult
    @State private var state: LoadState = .loading

    private enum LoadState {
        case loading, loaded(String), missing, failed(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .loading:
                    ProgressView()
                case .loaded(let text):
                    ScrollView([.vertical, .horizontal]) {
                        Text(text)
                            .font(.system(size: 9, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize()
                            .padding()
                    }
                case .missing:
                    ContentUnavailableView("No NFO", systemImage: "doc.plaintext", description: Text("The indexer has no NFO for this release."))
                case .failed(let message):
                    ContentUnavailableView("Couldn't Load the NFO", systemImage: "exclamationmark.triangle", description: Text(message))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("NFO")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .task {
            guard let client = store.newznabClient(for: store.activeIndexer) else {
                state = .failed("No indexer is set up.")
                return
            }
            do {
                state = try await client.nfo(id: release.newznabID).map(LoadState.loaded) ?? .missing
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}
