import Foundation

nonisolated enum SABnzbdError: LocalizedError, Equatable {
    case notConfigured
    case insecureHost(String)
    case http(Int)
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Server isn't set up yet."
        case .insecureHost(let host): "iOS blocked plain HTTP to \(host). Turn on HTTPS."
        case .http(let code): "Server returned HTTP \(code)."
        case .server(let message): message
        case .invalidResponse: "Unexpected response from SABnzbd."
        }
    }
}

nonisolated enum HistoryClearScope: String, Sendable {
    case all
    case failed
    case completed
}

/// Thin wrapper over SABnzbd's `api` endpoint. Runs off the main actor.
nonisolated struct SABnzbdClient: Sendable {
    let apiURL: URL
    let apiKey: String
    var session: URLSession = .shared

    // MARK: Reads

    func queue() async throws -> Queue {
        try await decode(QueueResponse.self, ["mode": "queue"]).queue
    }

    func history(limit: Int = 50) async throws -> History {
        try await decode(HistoryResponse.self, ["mode": "history", "limit": String(limit)]).history
    }

    /// What SABnzbd has logged as warnings and errors, newest first.
    func warnings() async throws -> [ServerWarning] {
        let data = try await get(["mode": "warnings"])
        try Self.checkStatus(data)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = object["warnings"] as? [Any]
        else { throw SABnzbdError.invalidResponse }
        return list.compactMap(ServerWarning.init).reversed()
    }

    func clearWarnings() async throws { try await send(["mode": "warnings", "name": "clear"]) }

    // MARK: Global

    func pauseAll() async throws { try await send(["mode": "pause"]) }
    func resumeAll() async throws { try await send(["mode": "resume"]) }

    /// Bytes per second; nil or 0 removes the limit. Always sent with a unit suffix
    /// because SABnzbd treats a bare value of 1–100 as a percentage of `bandwidth_max`.
    func setSpeedLimit(bytesPerSecond: Int?) async throws {
        let value: String
        if let bytes = bytesPerSecond, bytes > 0 {
            value = "\(max(1, bytes / 1024))K"
        } else {
            value = "0"
        }
        try await send(["mode": "config", "name": "speedlimit", "value": value])
    }

    // MARK: Queue jobs

    func pauseJob(_ id: String) async throws { try await send(["mode": "queue", "name": "pause", "value": id]) }
    func resumeJob(_ id: String) async throws { try await send(["mode": "queue", "name": "resume", "value": id]) }

    func deleteJob(_ id: String, deleteFiles: Bool = true) async throws {
        try await send(["mode": "queue", "name": "delete", "value": id, "del_files": deleteFiles ? "1" : "0"])
    }

    /// `value=all` empties the queue.
    func deleteAllJobs(deleteFiles: Bool = true) async throws {
        try await send(["mode": "queue", "name": "delete", "value": "all", "del_files": deleteFiles ? "1" : "0"])
    }

    func setPriority(_ id: String, _ priority: Priority) async throws {
        try await send(["mode": "queue", "name": "priority", "value": id, "value2": String(priority.rawValue)])
    }

    /// `mode=switch` accepts a queue index as `value2`.
    func moveJob(_ id: String, to index: Int) async throws {
        try await send(["mode": "switch", "value": id, "value2": String(index)])
    }

    // MARK: History

    func retry(_ id: String) async throws { try await send(["mode": "retry", "value": id]) }

    /// SABnzbd accepts "all", "failed" or "completed" in place of a job ID.
    func clearHistory(_ scope: HistoryClearScope) async throws {
        try await send(["mode": "history", "name": "delete", "value": scope.rawValue])
    }

    func deleteHistory(_ id: String, deleteFiles: Bool = false) async throws {
        try await send(["mode": "history", "name": "delete", "value": id, "del_files": deleteFiles ? "1" : "0"])
    }

    // MARK: Add

    /// SABnzbd downloads the NZB itself, so the server needs to reach the indexer.
    func addURL(_ url: URL, name: String, priority: Priority? = nil) async throws {
        var params = ["mode": "addurl", "name": url.absoluteString, "nzbname": name]
        if let priority { params["priority"] = String(priority.rawValue) }
        try await send(params)
    }

    func addFile(_ data: Data, filename: String) async throws {
        let boundary = "SABduo-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"name\"; filename=\"\(filename.replacingOccurrences(of: "\"", with: ""))\"\r\n")
        body.append("Content-Type: application/x-nzb\r\n\r\n")
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: try url(["mode": "addfile"]))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        try Self.checkStatus(try await perform(request))
    }

    // MARK: Plumbing

    private func url(_ params: [String: String]) throws -> URL {
        guard var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false) else {
            throw SABnzbdError.notConfigured
        }
        components.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            + [URLQueryItem(name: "output", value: "json"), URLQueryItem(name: "apikey", value: apiKey)]
        guard let url = components.url else { throw SABnzbdError.notConfigured }
        return url
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        var request = request
        request.timeoutInterval = 15
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .appTransportSecurityRequiresSecureConnection {
            throw SABnzbdError.insecureHost(request.url?.host() ?? "this host")
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SABnzbdError.http(http.statusCode)
        }
        return data
    }

    private func get(_ params: [String: String]) async throws -> Data {
        try await perform(URLRequest(url: url(params)))
    }

    private func send(_ params: [String: String]) async throws {
        try Self.checkStatus(try await get(params))
    }

    private func decode<T: Decodable>(_ type: T.Type, _ params: [String: String]) async throws -> T {
        let data = try await get(params)
        try Self.checkStatus(data)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SABnzbdError.invalidResponse
        }
    }

    /// Errors come back as HTTP 200 with `{"status": false, "error": "..."}`,
    /// or as plain text for some auth failures.
    private static func checkStatus(_ data: Data) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.lowercased().hasPrefix("error") || text.lowercased().contains("api key") {
                throw SABnzbdError.server(text)
            }
            throw SABnzbdError.invalidResponse
        }
        guard let dict = object as? [String: Any] else { return }
        if let error = dict["error"] as? String, !error.isEmpty {
            throw SABnzbdError.server(error)
        }
        if let status = dict["status"] as? Bool, status == false {
            throw SABnzbdError.server("SABnzbd rejected the request.")
        }
    }
}

private nonisolated extension Data {
    mutating func append(_ string: String) { append(Data(string.utf8)) }
}

/// A warning or error from SABnzbd's log. Newer versions send objects; older ones a string of
/// "date\ntype\nmessage".
nonisolated struct ServerWarning: Identifiable, Hashable, Sendable {
    let id = UUID()
    let text: String
    let isError: Bool
    let date: Date?

    init?(_ value: Any) {
        if let object = value as? [String: Any], let text = object["text"] as? String {
            self.text = text
            isError = (object["type"] as? String)?.uppercased() == "ERROR"
            date = (object["time"] as? Double).map { Date(timeIntervalSince1970: $0) }
        } else if let string = value as? String {
            let lines = string.split(separator: "\n", maxSplits: 2).map(String.init)
            text = lines.last ?? string
            isError = lines.count == 3 && lines[1].uppercased() == "ERROR"
            date = nil
        } else {
            return nil
        }
    }
}
