import Foundation
import Observation
import SwiftUI

@Observable
final class AppStore {
    private static let apiKeyAccount = "apiKey"

    private(set) var config: ServerConfig
    private(set) var apiKey: String
    private(set) var queue: Queue?
    private(set) var history: [HistorySlot] = []
    private(set) var lastUpdated: Date?
    var errorMessage: String?
    /// Brief confirmation shown after adding an NZB.
    var notice: String?
    /// Job shown in the detail pane (unfolded) or pushed (folded).
    var selectedJobID: QueueSlot.ID?
    /// What sits beside the queue: the trailing pane when unfolded, the selected tab when folded.
    var secondaryPane: SecondaryPane = .history

    private(set) var indexers: [Indexer]
    private var indexerKeys: [Indexer.ID: String]
    let search = SearchModel()

    /// Bumped on every mutation so an in-flight poll can't overwrite an optimistic update with stale data.
    private var generation = 0

    init() {
        config = .load()
        apiKey = Keychain.string(for: Self.apiKeyAccount) ?? ""
        let savedIndexers = Indexer.loadAll()
        indexers = savedIndexers
        indexerKeys = Dictionary(uniqueKeysWithValues: savedIndexers.map { ($0.id, Keychain.string(for: $0.keychainAccount) ?? "") })
        search.indexerID = savedIndexers.first?.id
        #if DEBUG
        // Point a simulator run at a server without typing it in:
        // SIMCTL_CHILD_SABDUO_HOST=127.0.0.1 SIMCTL_CHILD_SABDUO_API_KEY=… xcrun simctl launch …
        let env = ProcessInfo.processInfo.environment
        if let host = env["SABDUO_HOST"], let key = env["SABDUO_API_KEY"] {
            var seeded = ServerConfig()
            seeded.host = host
            seeded.port = env["SABDUO_PORT"].flatMap(Int.init) ?? seeded.port
            updateServer(seeded, apiKey: key)
        }
        if let address = env["SABDUO_INDEXER_URL"], let key = env["SABDUO_INDEXER_KEY"] {
            var indexer = indexers.first { $0.address == address } ?? Indexer(name: "Debug Indexer", address: address)
            indexer.name = env["SABDUO_INDEXER_NAME"] ?? indexer.name
            saveIndexer(indexer, apiKey: key)
        }
        #endif
    }

    var isConfigured: Bool { client != nil }

    var client: SABnzbdClient? {
        guard !apiKey.isEmpty, let url = config.apiURL else { return nil }
        return SABnzbdClient(apiURL: url, apiKey: apiKey)
    }

    var slots: [QueueSlot] { queue?.slots ?? [] }

    func job(_ id: QueueSlot.ID?) -> QueueSlot? {
        guard let id else { return nil }
        return slots.first { $0.id == id }
    }

    // MARK: Server

    func updateServer(_ newConfig: ServerConfig, apiKey newKey: String) {
        newConfig.save()
        Keychain.set(newKey, for: Self.apiKeyAccount)
        config = newConfig
        apiKey = newKey
        queue = nil
        history = []
        selectedJobID = nil
        errorMessage = nil
        generation += 1
    }

    // MARK: Indexers

    func indexerKey(_ indexer: Indexer) -> String { indexerKeys[indexer.id] ?? "" }

    func saveIndexer(_ indexer: Indexer, apiKey key: String) {
        if let i = indexers.firstIndex(where: { $0.id == indexer.id }) {
            indexers[i] = indexer
        } else {
            indexers.append(indexer)
        }
        indexerKeys[indexer.id] = key
        Keychain.set(key, for: indexer.keychainAccount)
        Indexer.saveAll(indexers)
        if search.indexerID == nil || search.indexerID == indexer.id {
            search.indexerID = indexer.id
            search.reset()
        }
    }

    func deleteIndexers(at offsets: IndexSet) {
        for indexer in offsets.map({ indexers[$0] }) {
            Keychain.set(nil, for: indexer.keychainAccount)
            indexerKeys[indexer.id] = nil
        }
        indexers.remove(atOffsets: offsets)
        Indexer.saveAll(indexers)
        if !indexers.contains(where: { $0.id == search.indexerID }) {
            search.indexerID = indexers.first?.id
            search.reset()
        }
    }

    var activeIndexer: Indexer? {
        indexers.first { $0.id == search.indexerID } ?? indexers.first
    }

    func newznabClient(for indexer: Indexer?) -> NewznabClient? {
        guard let indexer, let url = indexer.apiURL, let key = indexerKeys[indexer.id], !key.isEmpty else { return nil }
        return NewznabClient(apiURL: url, apiKey: key)
    }

    /// Hands the indexer's NZB link to SABnzbd (`mode=addurl`).
    func send(_ result: SearchResult, priority: Priority? = nil) async {
        guard let client else {
            errorMessage = SABnzbdError.notConfigured.localizedDescription
            return
        }
        do {
            try await client.addURL(result.nzbURL, name: result.title, priority: priority)
            search.markSent(result.id)
            notice = "Sent \(result.title)"
            generation += 1
            await refresh()
        } catch {
            errorMessage = "Couldn't send \(result.title): \(error.localizedDescription)"
        }
    }

    // MARK: Refresh

    func refresh() async {
        guard let client else { return }
        let started = generation
        do {
            async let q = client.queue()
            async let h = client.history()
            let (newQueue, newHistory) = try await (q, h)
            guard started == generation else { return }
            queue = newQueue
            history = newHistory.slots
            lastUpdated = .now
            errorMessage = nil
            if let selectedJobID, job(selectedJobID) == nil { self.selectedJobID = nil }
        } catch {
            guard !Self.isCancellation(error), started == generation else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Refreshes until the calling task is cancelled (e.g. the view disappears or the app backgrounds).
    func poll(every interval: Duration = .seconds(3)) async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: interval)
        }
    }

    // MARK: Global

    func togglePauseAll() async {
        let pause = !(queue?.paused ?? false)
        await mutate({ $0.queue?.paused = pause }) { client in
            pause ? try await client.pauseAll() : try await client.resumeAll()
        }
    }

    func setSpeedLimit(bytesPerSecond: Int?) async {
        await mutate({ $0.queue?.speedLimitBytes = bytesPerSecond ?? 0 }) { client in
            try await client.setSpeedLimit(bytesPerSecond: bytesPerSecond)
        }
    }

    // MARK: Queue jobs

    func togglePause(_ job: QueueSlot) async {
        let pause = !job.isPaused
        await mutate({ store in
            store.updateSlot(job.id) { $0.status = pause ? "Paused" : "Queued" }
        }) { client in
            pause ? try await client.pauseJob(job.id) : try await client.resumeJob(job.id)
        }
    }

    func setPriority(_ priority: Priority, for job: QueueSlot) async {
        await mutate({ store in
            store.updateSlot(job.id) { $0.priority = priority }
        }) { client in
            try await client.setPriority(job.id, priority)
        }
    }

    func delete(_ job: QueueSlot) async {
        await mutate({ store in
            store.queue?.slots.removeAll { $0.id == job.id }
            if store.selectedJobID == job.id { store.selectedJobID = nil }
        }) { client in
            try await client.deleteJob(job.id)
        }
    }

    /// Bridges `List.onMove` to SABnzbd's `mode=switch`, which moves one job to a target index.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) async {
        guard source.count == 1, let from = source.first, slots.indices.contains(from) else { return }
        let target = destination > from ? destination - 1 : destination
        guard target != from else { return }
        let id = slots[from].id
        await mutate({ $0.queue?.slots.move(fromOffsets: source, toOffset: destination) }) { client in
            try await client.moveJob(id, to: target)
        }
    }

    // MARK: History

    func retry(_ item: HistorySlot) async {
        await mutate(nil) { client in try await client.retry(item.id) }
    }

    func remove(_ item: HistorySlot) async {
        await mutate({ store in store.history.removeAll { $0.id == item.id } }) { client in
            try await client.deleteHistory(item.id)
        }
    }

    // MARK: Add NZB

    func addNZB(from url: URL) async {
        guard let client else {
            errorMessage = SABnzbdError.notConfigured.localizedDescription
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            try await client.addFile(data, filename: url.lastPathComponent)
            notice = "Added \(url.deletingPathExtension().lastPathComponent)"
            generation += 1
            await refresh()
        } catch {
            errorMessage = "Couldn't add \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    // MARK: Helpers

    private func mutate(_ optimistic: ((AppStore) -> Void)?, _ operation: (SABnzbdClient) async throws -> Void) async {
        guard let client else { return }
        generation += 1
        withAnimation { optimistic?(self) }
        do {
            try await operation(client)
        } catch {
            errorMessage = error.localizedDescription
        }
        await refresh()
    }

    private func updateSlot(_ id: QueueSlot.ID, _ change: (inout QueueSlot) -> Void) {
        guard let i = queue?.slots.firstIndex(where: { $0.id == id }) else { return }
        change(&queue!.slots[i])
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}

enum SecondaryPane: Hashable {
    case history
    case search
}
