import SwiftUI

/// What an indexer reports about itself through `t=caps`, plus the usage it last reported.
struct IndexerInfoView: View {
    @Environment(AppStore.self) private var store
    let indexerID: Indexer.ID

    var body: some View {
        let indexer = store.indexers.first { $0.id == indexerID }

        List {
            if let indexer {
                header(indexer)
                content(indexer)
            }
        }
        .overlay {
            if indexer == nil {
                ContentUnavailableView("Indexer Removed", systemImage: "server.rack")
            }
        }
        .refreshable { await reload(force: true) }
        .task { await reload(force: false) }
        .navigationTitle(indexer?.name ?? "Indexer")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(_ indexer: Indexer) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                if let image = store.search.loadedCaps(for: indexerID)?.imageURL {
                    AsyncImage(url: image) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit()
                        }
                    }
                    .frame(maxHeight: 72)
                }
                Text(indexer.name).font(.title2.weight(.semibold))
                Text(indexer.apiURL?.absoluteString ?? indexer.address)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func content(_ indexer: Indexer) -> some View {
        if let limits = store.search.apiLimits[indexerID] {
            Section {
                usage("API Requests", current: limits.apiCurrent, max: limits.apiMax)
                usage("NZB Downloads", current: limits.grabCurrent, max: limits.grabMax)
            } header: {
                Text("Your Usage")
            } footer: {
                Text("As last reported by \(indexer.name).")
            }
        }

        switch store.search.caps[indexerID] {
        case .loaded(let caps):
            Section("Server") {
                if !caps.title.isEmpty { LabeledContent("Reports As", value: caps.title) }
                if !caps.appVersion.isEmpty { LabeledContent("Software", value: caps.appVersion) }
                if !caps.version.isEmpty { LabeledContent("API Version", value: caps.version) }
                if let site = caps.siteURL {
                    Link(destination: site) { Label(site.host() ?? site.absoluteString, systemImage: "safari") }
                }
                if !caps.email.isEmpty, let mail = URL(string: "mailto:\(caps.email)") {
                    Link(destination: mail) { Label(caps.email, systemImage: "envelope") }
                }
            }

            Section("Limits") {
                if let max = caps.maxResults { LabeledContent("Max Results per Request", value: "\(max)") }
                if let def = caps.defaultResults { LabeledContent("Default Results", value: "\(def)") }
                if let open = caps.registrationOpen {
                    LabeledContent("Registration", value: caps.registrationAvailable == false ? "Unavailable" : open ? "Open" : "Closed")
                }
            }

            if !caps.searchModes.isEmpty {
                Section("Search Modes") {
                    ForEach(caps.searchModes) { mode in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(mode.label)
                                Spacer()
                                Image(systemName: mode.available ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundStyle(mode.available ? .green : .secondary)
                            }
                            if !mode.parameters.isEmpty {
                                Text(mode.parameters.joined(separator: ", "))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Catalog") {
                LabeledContent("Categories", value: "\(caps.categories.count)")
                LabeledContent("Subcategories", value: "\(caps.categories.reduce(0) { $0 + $1.subcategories.count })")
                if caps.groupCount > 0 { LabeledContent("Newsgroups", value: caps.groupCount.formatted()) }
                if caps.genreCount > 0 { LabeledContent("Genres", value: caps.genreCount.formatted()) }
            }

        case .failed(let message):
            Section {
                ContentUnavailableView("Couldn't Load Info", systemImage: "exclamationmark.triangle", description: Text(message))
            }

        case .loading, nil:
            Section {
                HStack {
                    Text("Loading…").foregroundStyle(.secondary)
                    Spacer()
                    ProgressView()
                }
            }
        }

        Section {
            NavigationLink {
                IndexerEditView(indexer: indexer)
            } label: {
                Label("Edit Indexer", systemImage: "pencil")
            }
        }
    }

    @ViewBuilder
    private func usage(_ title: String, current: Int?, max: Int?) -> some View {
        if let current, let max, max > 0 {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent(title, value: "\(current) of \(max)")
                Gauge(value: Double(min(current, max)), in: 0...Double(max)) {}
                    .tint(Double(current) / Double(max) > 0.8 ? .orange : .accentColor)
            }
        } else if let current {
            LabeledContent(title, value: "\(current)")
        }
    }

    private func reload(force: Bool) async {
        guard let indexer = store.indexers.first(where: { $0.id == indexerID }) else { return }
        await store.search.loadCaps(for: indexer, client: store.newznabClient(for: indexer), force: force)
    }
}
