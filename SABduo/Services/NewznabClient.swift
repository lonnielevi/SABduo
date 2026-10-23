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

/// Talks to a Newznab indexer. Always parses the RSS/XML output: it's the one format every
/// implementation supports, and errors come back as XML even when `o=json` is requested.
nonisolated struct NewznabClient: Sendable {
    let apiURL: URL
    let apiKey: String
    var session: URLSession = .shared

    static let pageSize = 100

    /// An empty query browses the latest releases. Parent category IDs include their subcategories.
    func search(_ query: String, categoryIDs: [Int] = [], offset: Int = 0) async throws -> SearchPage {
        var params = [
            "t": "search",
            "limit": String(Self.pageSize),
            "offset": String(offset),
            "extended": "1",
        ]
        if !query.isEmpty { params["q"] = query }
        if !categoryIDs.isEmpty { params["cat"] = categoryIDs.map(String.init).joined(separator: ",") }
        return try ResultsParser.parse(try await fetch(params))
    }

    /// Full attributes for one release.
    func details(id: String) async throws -> SearchResult? {
        try ResultsParser.parse(try await fetch(["t": "details", "id": id, "extended": "1"])).results.first
    }

    func caps() async throws -> IndexerCaps {
        try CapsParser.parse(try await fetch(["t": "caps"]))
    }

    /// Cheap authenticated call used to validate settings (caps usually doesn't check the key).
    func test() async throws {
        _ = try ResultsParser.parse(try await fetch(["t": "search", "limit": "1"]))
    }

    private func fetch(_ params: [String: String]) async throws -> Data {
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
        return data
    }
}

/// Parses Newznab RSS into results, or throws the `<error>` it contains.
nonisolated final class ResultsParser: NSObject, XMLParserDelegate {
    private var results: [SearchResult] = []
    private var offset = 0
    private var total: Int?
    private var apiLimits: APILimits?
    private var error: NewznabError?
    private var sawRoot = false

    private var item: [String: String]?
    private var attrs: [String: String] = [:]
    private var text = ""

    static func parse(_ data: Data) throws -> SearchPage {
        let delegate = ResultsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        let ok = parser.parse()
        if let error = delegate.error { throw error }
        guard ok, delegate.sawRoot else { throw NewznabError.invalidResponse }
        return SearchPage(results: delegate.results, offset: delegate.offset, total: delegate.total, apiLimits: delegate.apiLimits)
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
        case "newznab:apilimits":
            apiLimits = APILimits(attributes)
        case "item":
            item = [:]
            attrs = [:]
        case "enclosure" where item != nil:
            item?["enclosure"] = attributes["url"]
            item?["enclosureLength"] = attributes["length"]
        case "newznab:attr" where item != nil:
            if let key = attributes["name"], let value = attributes["value"] {
                // Some attrs (category, genre) repeat; keep them all, comma-separated.
                attrs[key] = attrs[key].map { "\($0), \(value)" } ?? value
            }
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
        case "title", "guid", "link", "pubDate", "category", "comments", "description":
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
            description: item["description"]?.nonEmpty,
            attributes: attrs
        )
    }
}

/// Parses `t=caps`. Groups and genres can run to thousands of entries, so only their counts are kept.
nonisolated final class CapsParser: NSObject, XMLParserDelegate {
    private var caps = IndexerCaps()
    private var error: NewznabError?
    private var sawRoot = false
    private var inSearching = false
    private var currentCategory: IndexerCategory?

    static func parse(_ data: Data) throws -> IndexerCaps {
        let delegate = CapsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        let ok = parser.parse()
        if let error = delegate.error { throw error }
        guard ok, delegate.sawRoot else { throw NewznabError.invalidResponse }
        return delegate.caps
    }

    /// Indexers pad names ("Audio ", "PSP "); trim them.
    private static func clean(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    }

    private static func bool(_ value: String?) -> Bool? {
        value.map { ["yes", "true", "1"].contains($0.lowercased()) }
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        switch name {
        case "caps":
            sawRoot = true
        case "error":
            error = .server(code: Int(a["code"] ?? "") ?? 0, description: a["description"] ?? "Indexer error.")
            parser.abortParsing()
        case "server":
            caps.title = Self.clean(a["title"]) ?? ""
            caps.version = Self.clean(a["version"]) ?? ""
            caps.appVersion = Self.clean(a["appversion"]) ?? ""
            caps.email = Self.clean(a["email"]) ?? ""
            caps.siteURL = Self.clean(a["url"]).flatMap(URL.init(string:))
            caps.imageURL = Self.clean(a["image"]).flatMap(URL.init(string:))
        case "limits":
            caps.maxResults = a["max"].flatMap(Int.init)
            caps.defaultResults = a["default"].flatMap(Int.init)
        case "registration":
            caps.registrationAvailable = Self.bool(a["available"])
            caps.registrationOpen = Self.bool(a["open"])
        case "apilimits":
            caps.apiLimits = APILimits(a)
        case "searching":
            inSearching = true
        case _ where inSearching:
            caps.searchModes.append(SearchCapability(
                name: name,
                available: Self.bool(a["available"]) ?? false,
                parameters: (a["supportedParams"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            ))
        case "category":
            guard let id = a["id"].flatMap(Int.init) else { return }
            currentCategory = IndexerCategory(id: id, name: Self.clean(a["name"]) ?? "Category \(id)", detail: Self.clean(a["description"]))
        case "subcat":
            guard let id = a["id"].flatMap(Int.init), let parent = currentCategory?.name else { return }
            currentCategory?.subcategories.append(IndexerCategory(
                id: id,
                name: Self.clean(a["name"]) ?? "Category \(id)",
                detail: Self.clean(a["description"]),
                parentName: parent
            ))
        case "group":
            caps.groupCount += 1
        case "genre":
            caps.genreCount += 1
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "searching":
            inSearching = false
        case "category":
            if var category = currentCategory {
                category.subcategories.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                caps.categories.append(category)
            }
            currentCategory = nil
        default:
            break
        }
    }
}
