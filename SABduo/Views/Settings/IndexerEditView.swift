import SwiftUI

struct IndexerEditView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var indexer: Indexer
    @State private var apiKey = ""
    @State private var testState: TestState = .idle

    private enum TestState: Equatable {
        case idle, testing, success, failure(String)
    }

    init(indexer: Indexer) {
        _indexer = State(initialValue: indexer)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $indexer.name, prompt: Text("NZB.life"))
                TextField("Address", text: $indexer.address, prompt: Text("https://api.nzb.life/api"))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Indexer")
            } footer: {
                if let url = indexer.apiURL { Text(url.absoluteString) }
            }

            Section {
                SecureField("API Key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .fontDesign(.monospaced)
            } footer: {
                Text("Found in your indexer profile. Stored in the Keychain. Results are sent to SABnzbd as links, so your server needs to reach the indexer.")
            }

            Section {
                Button {
                    Task { await test() }
                } label: {
                    HStack {
                        Text("Test Indexer")
                        Spacer()
                        switch testState {
                        case .idle: EmptyView()
                        case .testing: ProgressView()
                        case .success: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        case .failure(let message):
                            Text(message).font(.caption).foregroundStyle(.red).multilineTextAlignment(.trailing)
                        }
                    }
                }
                .disabled(!canSave || testState == .testing)
            }
        }
        .navigationTitle(indexer.name.isEmpty ? "Indexer" : indexer.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", role: .confirm) {
                    var saved = indexer
                    saved.name = saved.name.trimmingCharacters(in: .whitespaces).nonEmpty ?? saved.apiURL?.host() ?? "Indexer"
                    store.saveIndexer(saved, apiKey: trimmedKey)
                    dismiss()
                }
                .disabled(!canSave)
            }
        }
        .onAppear { apiKey = store.indexerKey(indexer) }
        .onChange(of: indexer) { testState = .idle }
        .onChange(of: apiKey) { testState = .idle }
    }

    private var trimmedKey: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { indexer.apiURL != nil && !trimmedKey.isEmpty }

    private func test() async {
        guard let url = indexer.apiURL else { return }
        testState = .testing
        do {
            try await NewznabClient(apiURL: url, apiKey: trimmedKey).test()
            testState = .success
        } catch {
            testState = .failure(error.localizedDescription)
        }
    }
}
