import SwiftUI

struct ServerSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.listRowFill) private var rowFill
    @Environment(\.isUnfolded) private var isUnfolded

    @State private var config = ServerConfig()
    @State private var apiKey = ""
    @State private var portText = ""
    @State private var testState: TestState = .idle
    /// The server fields are locked until the lock is tapped, so a stray tap can't change them.
    /// Saving locks them again.
    @State private var isUnlocked = false
    @AppStorage(SpeedUnit.storageKey) private var speedUnit: SpeedUnit = .megabytes
    @AppStorage(TimeLeftStyle.storageKey) private var timeStyle: TimeLeftStyle = .countdown
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system

    private enum TestState: Equatable {
        case idle, testing, success, failure(String)
    }

    /// A page: of the leading pane unfolded, beside Queue and History; a tab folded.
    var body: some View {
        form
            // A form this narrow gets narrower margins than the lists beside it, and ignores
            // content and section margins; widen its safe area to match them.
            .safeAreaPadding(.horizontal, 3)
            // Folded, in the side rail with the other pages' buttons. Unfolded in portrait, above
            // the tab bar with them; in landscape, in the rail below search's.
            .toolbar {
                // Unfolded, the accessory and rail are outside this page (see `ListsAccessory`
                // and `ListsRailItems`).
                if !isUnfolded {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        SettingsButtons(controls: controls)
                    }
                }
            }
            // The first edit, typed rather than tapped, turns the open lock into undo.
            .animation(.snappy, value: isUnlocked && hasChanges)
            .navigationTitle("Settings")
            .onAppear {
                load()
                // Nothing to guard before there's a server.
                isUnlocked = !store.isConfigured
                store.settingsOnScreen = true
            }
            .onChange(of: [isUnlocked, hasChanges, canSave], initial: true) {
                store.settingsControls = controls
            }
            .onDisappear {
                store.settingsOnScreen = false
                store.settingsControls = nil
            }
    }

    private var controls: SettingsControls {
        let canUndo = isUnlocked && hasChanges
        return SettingsControls(
            isUnlocked: isUnlocked,
            canUndo: canUndo,
            canSave: canSave && hasChanges,
            toggleLock: {
                // Together, so undo goes straight to the lock rather than through the open lock.
                withAnimation(.snappy) {
                    if canUndo { load() }
                    isUnlocked.toggle()
                }
            },
            save: {
                withAnimation(.snappy) {
                    save()
                    isUnlocked = false
                }
            }
        )
    }

    private var isLocked: Bool { !isUnlocked }

    /// Disabled fields keep their colour; dim them so the lock reads.
    private var fieldStyle: HierarchicalShapeStyle { isLocked ? .secondary : .primary }

    private var form: some View {
        Form {
            Group {
                status
                server
                indexers
                display
                about
            }
            .listRowBackground(rowFill)
        }
        .onChange(of: draftConfig) { testState = .idle }
        .onChange(of: apiKey) { testState = .idle }
    }

    /// Whether SABnzbd answers, and a test of the fields as typed. The app's error banner would
    /// cover the save controls, so the page shows errors here.
    private var status: some View {
        Section {
            HStack(spacing: 10) {
                ServerConnectionLight()
                Text(statusText)
            }
            if let error = store.connectionError ?? store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            if let queue = store.queue {
                if let load = queue.loadAverages {
                    LabeledContent("System Load", value: load)
                }
                NavigationLink {
                    WarningsView()
                } label: {
                    LabeledContent("Warnings") {
                        Text(queue.warningCount == 0 ? "None" : "\(queue.warningCount)")
                            .foregroundStyle(queue.warningCount == 0 ? Color.secondary : .orange)
                    }
                }
            }
            Button {
                Task { await test() }
            } label: {
                HStack {
                    Text("Test Connection")
                    Spacer()
                    testIndicator
                }
            }
            .disabled(!canSave || testState == .testing)
        } header: {
            Text("Status")
        } footer: {
            if store.queue?.loadAverages != nil {
                Text("System load is averaged over 1, 5 and 15 minutes.")
            }
        }
    }

    private var statusText: String {
        let host = store.config.normalizedHost
        guard store.isConfigured else { return "No server set up" }
        switch store.isConnected {
        case true?: return "Connected to \(host)"
        case false?: return "Can't reach \(host)"
        case nil: return "Connecting to \(host)…"
        }
    }

    /// Where SABnzbd is and its key, locked until the lock is tapped.
    private var server: some View {
        Section {
            field("Host", text: $config.host, prompt: "nas.local")
                .textContentType(.URL)
                .keyboardType(.URL)
            field("Port", text: $portText, prompt: config.useHTTPS ? "443" : "8080")
                .keyboardType(.numberPad)
            Toggle("Use HTTPS", isOn: $config.useHTTPS)
                .foregroundStyle(fieldStyle)
            field("URL Base", text: $config.urlBase, prompt: "/sabnzbd")
            LabeledContent("API Key") {
                SecureField("API Key", text: $apiKey, prompt: Text("Required"))
                    .multilineTextAlignment(.trailing)
                    .fontDesign(.monospaced)
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .foregroundStyle(fieldStyle)
        } header: {
            Text("SABnzbd")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let url = draftConfig.apiURL {
                    Text(url.absoluteString)
                }
                Text("The API key is in SABnzbd → Config → General → Security. It's kept in the Keychain.")
            }
        }
        .disabled(isLocked)
    }

    /// A labelled field, its value on the right like Settings'.
    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        LabeledContent(title) {
            TextField(title, text: text, prompt: Text(prompt))
                .multilineTextAlignment(.trailing)
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .foregroundStyle(fieldStyle)
    }

    private var indexers: some View {
        Section {
            if store.indexers.count > 1 {
                Picker("Search With", selection: Binding(
                    get: { store.activeIndexer?.id },
                    set: { store.search.selectIndexer($0) }
                )) {
                    ForEach(store.indexers) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            ForEach(store.indexers) { indexer in
                NavigationLink {
                    IndexerInfoView(indexerID: indexer.id)
                } label: {
                    LabeledContent(indexer.name, value: indexer.apiURL?.host() ?? "")
                }
                // As everywhere, a swipe only offers it; deleting takes a tap.
                .swipeActions(allowsFullSwipe: false) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        if let index = store.indexers.firstIndex(of: indexer) {
                            store.deleteIndexers(at: IndexSet(integer: index))
                        }
                    }
                }
            }
            NavigationLink {
                IndexerEditView(indexer: Indexer(name: "", address: ""))
            } label: {
                Label("Add Indexer", systemImage: "plus")
            }
            // Search hides itself only while there's nothing to search; adding an indexer shows it.
            if store.indexers.isEmpty {
                Toggle("Show Search", isOn: Binding(
                    get: { !store.hidesSearch },
                    set: { shown in withAnimation { store.hidesSearch = !shown } }
                ))
            }
        } header: {
            Text("Search")
        } footer: {
            Text("Newznab indexers that Search uses. Tap one for its categories, limits and usage. They're saved as you go, apart from the server.")
        }
    }

    private var display: some View {
        Section {
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { option in
                    Text(option.name).tag(option)
                }
            }
            Picker("Speed Units", selection: $speedUnit) {
                ForEach(SpeedUnit.allCases) { unit in
                    Text(unit.symbol).tag(unit)
                }
            }
            Picker("Time Left", selection: $timeStyle) {
                ForEach(TimeLeftStyle.allCases) { style in
                    Text(style.name).tag(style)
                }
            }
        } header: {
            Text("Display")
        } footer: {
            Text("Tapping the speed or time left above the queue also switches them.")
        }
    }

    private var about: some View {
        Section("About") {
            LabeledContent("Version", value: Self.version)
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    private func load() {
        config = store.config
        apiKey = store.apiKey
        portText = String(store.config.port)
    }

    private func save() {
        store.updateServer(draftConfig, apiKey: trimmedKey)
        Task { await store.refresh() }
    }

    /// Saving is only offered once something changed.
    private var hasChanges: Bool { draftConfig != store.config || trimmedKey != store.apiKey }

    private var trimmedKey: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var draftConfig: ServerConfig {
        var draft = config
        draft.port = Int(portText) ?? (config.useHTTPS ? 443 : 8080)
        return draft
    }

    private var canSave: Bool { draftConfig.apiURL != nil && !trimmedKey.isEmpty }

    @ViewBuilder
    private var testIndicator: some View {
        switch testState {
        case .idle: EmptyView()
        case .testing: ProgressView()
        case .success: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failure(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.trailing)
        }
    }

    private func test() async {
        guard let url = draftConfig.apiURL else { return }
        testState = .testing
        do {
            _ = try await SABnzbdClient(apiURL: url, apiKey: trimmedKey).queue()
            testState = .success
        } catch {
            testState = .failure((error as? SABnzbdError)?.briefDescription ?? error.localizedDescription)
        }
    }
}

/// What Settings' buttons show and do, so they can sit outside the page that owns the draft.
struct SettingsControls {
    var isUnlocked: Bool
    var canUndo: Bool
    var canSave: Bool
    var toggleLock: () -> Void
    var save: () -> Void
}

/// A lock for the server fields, which shows open once tapped and becomes undo once something
/// changes; and save, greyed out until there's something to save. Undo and save both lock again.
struct SettingsButtons: View {
    let controls: SettingsControls

    var body: some View {
        Button(controls.canUndo ? "Undo Changes" : controls.isUnlocked ? "Lock" : "Unlock to Edit",
               systemImage: controls.canUndo ? "arrow.uturn.backward" : controls.isUnlocked ? "lock.open.fill" : "lock.fill",
               action: controls.toggleLock)
            .contentTransition(.symbolEffect(.replace))
        Button("Save", systemImage: "checkmark", action: controls.save)
            .fontWeight(.semibold)
            .tint(.accentColor)
            .disabled(!controls.canSave)
    }
}
