import Foundation

/// Connection settings. Everything except the API key, which lives in the Keychain.
nonisolated struct ServerConfig: Codable, Equatable, Sendable {
    var host: String = "172.21.1.2"
    var port: Int = 8085
    var useHTTPS: Bool = false
    /// SABnzbd's `url_base`; "/sabnzbd" by default, empty behind some reverse proxies.
    var urlBase: String = "/sabnzbd"

    var isComplete: Bool { !normalizedHost.isEmpty }

    /// Accepts hosts pasted with a scheme or trailing slash, e.g. "http://nas.local/".
    var normalizedHost: String {
        var h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://"] where h.lowercased().hasPrefix(prefix) {
            h.removeFirst(prefix.count)
        }
        while h.hasSuffix("/") { h.removeLast() }
        return h
    }

    var apiURL: URL? {
        guard isComplete else { return nil }
        var components = URLComponents()
        components.scheme = useHTTPS ? "https" : "http"
        components.host = normalizedHost
        components.port = port
        var base = urlBase.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        if !base.isEmpty, !base.hasPrefix("/") { base = "/" + base }
        components.path = base + "/api"
        return components.url
    }
}

extension ServerConfig {
    private static let defaultsKey = "serverConfig"

    static func load(from defaults: UserDefaults = .standard) -> ServerConfig {
        guard let data = defaults.data(forKey: defaultsKey),
              let config = try? JSONDecoder().decode(ServerConfig.self, from: data)
        else { return ServerConfig() }
        return config
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
