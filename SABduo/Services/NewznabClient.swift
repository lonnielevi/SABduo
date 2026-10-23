import Foundation

nonisolated enum NewznabError: LocalizedError, Equatable {
    case insecureHost(String)
    case http(Int)
    /// Newznab reports failures as `<error code="100" description="Incorrect user credentials"/>`.
    case server(code: Int, description: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .insecureHost(let host): "iOS blocked plain HTTP to \(host). Use an https:// address."
        case .http(let code): "Indexer returned HTTP \(code)."
        case .server(_, let description): description
        case .invalidResponse: "Unexpected response from the indexer."
        }
    }
}

/// Searches a Newznab indexer. Always parses the RSS/XML output: it's the one format every
/// implementation supports, and errors come back as XML even when `o=json` is requested.
nonisolated struct NewznabClient: Sendable {
    let apiURL: URL
    let apiKey: String
    var session: URLSession = .shared

    static let pageSize = 100

    func search(_ query: String, category: SearchCategory, offset: Int = 0) async throws -> SearchPage {
        var params = [
            "t": "search",
            "q": query,
            "limit": String(Self.pageSize),
            "offset": String(offset),
            "extended": "1",
        ]
        if category != .all { params["cat"] = String(category.rawValue) }
        return try await fetch(params)
    }

    /// Cheap authenticated call used to validate settings.
    func test() async throws {
        _ = try await fetch(["t": "search", "limit": "1"])
    }

    private func fetch(_ params: [String: String]) async throws -> SearchPage {
        guard var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false) else {
            throw NewznabError.invalidResponse
        }
        components.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            + [URLQueryItem(name: "apikey", value: apiKey)]
        guard let url = components.url else { throw NewznabError.invalidResponse }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .appTransportSecurityRequiresSecureConnection {
            throw NewznabError.insecureHost(url.host() ?? "this host")
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NewznabError.http(http.statusCode)
        }
        return try NewznabParser.parse(data)
    }
}

/// Parses Newznab RSS into results, or throws the `<error>` it contains.
nonisolated final class NewznabParser: NSObject, XMLParserDelegate {
    private var results: [SearchResult] = []
    private var offset = 0
    private var total: Int?
    private var error: NewznabError?
    private var sawRoot = false

    private var item: [String: String]?
    private var attrs: [String: String] = [:]
    private var text = ""

    static func parse(_ data: Data) throws -> SearchPage {
        let delegate = NewznabParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        let ok = parser.parse()
        if let error = delegate.error { throw error }
        guard ok, delegate.sawRoot else { throw NewznabError.invalidResponse }
        return SearchPage(results: delegate.results, offset: delegate.offset, total: delegate.total)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        text = ""
        switch name {
        case "rss":
            sawRoot = true
        case "error":
            error = .server(code: Int(attributes["code"] ?? "") ?? 0, description: attributes["description"] ?? "Indexer error.")
            parser.abortParsing()
        case "newznab:response":
            offset = Int(attributes["offset"] ?? "") ?? 0
            total = Int(attributes["total"] ?? "")
        case "item":
            item = [:]
            attrs = [:]
        case "enclosure" where item != nil:
            item?["enclosure"] = attributes["url"]
            item?["enclosureLength"] = attributes["length"]
        case "newznab:attr" where item != nil:
            if let key = attributes["name"], let value = attributes["value"] { attrs[key] = value }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA block: Data) {
        text += String(decoding: block, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard item != nil else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "title", "guid", "link", "pubDate", "category", "comments":
            item?[name] = value
        case "item":
            if let result = makeResult() { results.append(result) }
            item = nil
        default:
            break
        }
    }

    private func makeResult() -> SearchResult? {
        guard let item,
              let link = (item["link"]?.nonEmpty ?? item["enclosure"]).flatMap(URL.init(string:))
        else { return nil }
        let size = Int64(attrs["size"] ?? item["enclosureLength"] ?? "") ?? 0
        let date = (attrs["usenetdate"] ?? item["pubDate"]).flatMap(Self.dateFormatter.date(from:))
        let guid = attrs["guid"] ?? item["guid"] ?? link.absoluteString
        return SearchResult(
            id: guid,
            title: item["title"] ?? "Untitled",
            nzbURL: link,
            detailsURL: (item["comments"] ?? item["guid"]).flatMap(URL.init(string:)).flatMap { $0.scheme?.hasPrefix("http") == true ? $0 : nil },
            published: date,
            size: size,
            category: item["category"] ?? "",
            grabs: attrs["grabs"].flatMap(Int.init)
        )
    }
}
