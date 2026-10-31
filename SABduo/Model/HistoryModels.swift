import Foundation

nonisolated struct HistoryResponse: Decodable, Sendable {
    let history: History
}

nonisolated struct History: Decodable, Equatable, Sendable {
    var slots: [HistorySlot]

    private enum CodingKeys: String, CodingKey { case slots }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slots = (try? c.decode([HistorySlot].self, forKey: .slots)) ?? []
    }
}

nonisolated struct HistorySlot: Decodable, Identifiable, Equatable, Hashable, Sendable {
    var id: String
    var name: String
    var status: String
    var size: String
    var category: String
    var failMessage: String
    /// Post-processing progress text while a job is verifying/unpacking.
    var actionLine: String
    var completed: Date?
    var downloadTime: Int
    /// SABnzbd only offers retry for failed jobs whose files still exist.
    var canRetry: Bool
    var bytes: Int64
    /// Seconds spent verifying, repairing and unpacking.
    var postprocTime: Int
    var nzbName: String
    /// Where the files ended up.
    var storage: String
    var script: String
    /// What each step did: the servers it came from, the repair, the unpack.
    var stages: [Stage]

    var isFailed: Bool { status.lowercased() == "failed" }
    var isCompleted: Bool { status.lowercased() == "completed" }

    private enum CodingKeys: String, CodingKey {
        case nzoID = "nzo_id"
        case name, status, size, category, completed, retry
        case failMessage = "fail_message"
        case actionLine = "action_line"
        case downloadTime = "download_time"
        case bytes, storage, script
        case postprocTime = "postproc_time"
        case nzbName = "nzb_name"
        case stages = "stage_log"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .nzoID)
        name = c.lossyString(.name)
        status = c.lossyString(.status)
        size = c.lossyString(.size)
        category = c.lossyString(.category)
        failMessage = c.lossyString(.failMessage)
        actionLine = c.lossyString(.actionLine)
        let timestamp = c.lossyInt(.completed)
        completed = timestamp > 0 ? Date(timeIntervalSince1970: TimeInterval(timestamp)) : nil
        downloadTime = c.lossyInt(.downloadTime)
        canRetry = c.lossyBool(.retry)
        bytes = Int64(c.lossyDouble(.bytes))
        postprocTime = c.lossyInt(.postprocTime)
        nzbName = c.lossyString(.nzbName)
        storage = c.lossyString(.storage)
        script = c.lossyString(.script)
        stages = (try? c.decode([Stage].self, forKey: .stages)) ?? []
    }

    /// A step of the job, as SABnzbd logs it: "Servers" lists "host=1.2 GB"; others say what
    /// they did, in lines that can carry HTML.
    struct Stage: Decodable, Equatable, Hashable, Sendable {
        var name: String
        var actions: [String]

        private enum CodingKeys: String, CodingKey { case name, actions }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = c.lossyString(.name)
            let raw = (try? c.decode([String].self, forKey: .actions)) ?? []
            actions = raw.flatMap(Self.plainLines)
        }

        /// Breaks become lines; other tags go, and entities are decoded.
        private static func plainLines(_ html: String) -> [String] {
            html.replacing(/<br\s*\/?>/.ignoresCase(), with: "\n")
                .replacing(/<[^>]+>/, with: "")
                .replacing("&amp;", with: "&").replacing("&lt;", with: "<").replacing("&gt;", with: ">")
                .replacing("&quot;", with: "\"").replacing("&#39;", with: "'").replacing("&nbsp;", with: " ")
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    }
}
