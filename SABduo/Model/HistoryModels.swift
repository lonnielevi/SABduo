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

    var isFailed: Bool { status.lowercased() == "failed" }
    var isCompleted: Bool { status.lowercased() == "completed" }

    private enum CodingKeys: String, CodingKey {
        case nzoID = "nzo_id"
        case name, status, size, category, completed, retry
        case failMessage = "fail_message"
        case actionLine = "action_line"
        case downloadTime = "download_time"
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
    }
}
