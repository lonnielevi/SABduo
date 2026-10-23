import SwiftUI

struct ServerSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var config = ServerConfig()
    @State private var apiKey = ""
    @State private var portText = ""
    @State private var testState: TestState = .idle

    private enum TestState: Equatable {
        case idle, testing, success, failure(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Host", text: $config.host, prompt: Text("192.168.1.10 or nas.local"))
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Port", text: $portText, prompt: Text("8080"))
                        .keyboardType(.numberPad)
                    Toggle("Use HTTPS", isOn: $config.useHTTPS)
                    TextField("URL Base", text: $config.urlBase, prompt: Text("/sabnzbd"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Server")
                } footer: {
                    if let url = draftConfig.apiURL {
                        Text(url.absoluteString)
                    }
                }

                Section {
                    SecureField("API Key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .fontDesign(.monospaced)
                } header: {
                    Text("Authentication")
                } footer: {
                    Text("SABnzbd → Config → General → Security. Stored in the Keychain.")
                }

                Section {
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
                }

                Section {
                    ForEach(store.indexers) { indexer in
                        NavigationLink {
                            IndexerEditView(indexer: indexer)
                        } label: {
                            LabeledContent(indexer.name, value: indexer.apiURL?.host() ?? "")
                        }
                    }
                    .onDelete { store.deleteIndexers(at: $0) }
                    NavigationLink {
                        IndexerEditView(indexer: store.indexers.contains { $0.address == Indexer.nzbLife.address }
                            ? Indexer(name: "", address: "")
                            : Indexer.nzbLife)
                    } label: {
                        Label("Add Indexer", systemImage: "plus")
                    }
                } header: {
                    Text("Indexers")
                } footer: {
                    Text("Newznab-compatible indexers used by Search. Saved separately from the server.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .disabled(!store.isConfigured)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", role: .confirm) {
                        store.updateServer(draftConfig, apiKey: trimmedKey)
                        dismiss()
                        Task { await store.refresh() }
                    }
                    .disabled(!canSave)
                }
            }
            .onChange(of: draftConfig) { testState = .idle }
            .onChange(of: apiKey) { testState = .idle }
        }
        .interactiveDismissDisabled(!store.isConfigured)
        .onAppear {
            config = store.config
            apiKey = store.apiKey
            portText = String(store.config.port)
        }
    }

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
            testState = .failure(error.localizedDescription)
        }
    }
}
