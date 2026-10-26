import Foundation

nonisolated enum Priority: Int, CaseIterable, Identifiable, Sendable {
    case force = 2
    case high = 1
    case normal = 0
    case low = -1

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .force: "Force"
        case .high: "High"
        case .normal: "Normal"
        case .low: "Low"
        }
    }

    /// The queue reports priority as a name ("High"), but falls back to a bare int for unmapped values.
    init(apiValue: String) {
        switch apiValue.lowercased() {
        case "force", "2": self = .force
        case "high", "repair", "1", "3": self = .high
        case "low", "-1": self = .low
        default: self = .normal
        }
    }
}

nonisolated struct QueueResponse: Decodable, Sendable {
    let queue: Queue
}

nonisolated struct Queue: Decodable, Equatable, Sendable {
    var paused: Bool
    var status: String
    var kbPerSec: Double
    var timeLeft: String
    var sizeLeft: String
    /// Bytes per second; 0 means unlimited. See `limit_speed` in SABnzbd's downloader.
    var speedLimitBytes: Int
    var slots: [QueueSlot]
    /// Jobs in the queue, including any past the page of slots fetched.
    var jobCount: Int
    /// Warnings SABnzbd has logged since they were last cleared.
    var warningCount: Int
    /// The server's load averages, as SABnzbd reports them: "0.52 | 0.48 | 0.45 | V=…".
    var loadAverage: String

    var bytesPerSecond: Double { kbPerSec * 1024 }

    private enum CodingKeys: String, CodingKey {
        case paused, status, kbpersec, timeleft, sizeleft, slots
        case speedlimitAbs = "speedlimit_abs"
        case noofslots
        case noofslotsTotal = "noofslots_total"
        case haveWarnings = "have_warnings"
        case loadavg
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        paused = c.lossyBool(.paused)
        status = c.lossyString(.status)
        kbPerSec = c.lossyDouble(.kbpersec)
        timeLeft = c.lossyString(.timeleft)
        sizeLeft = c.lossyString(.sizeleft)
        speedLimitBytes = c.lossyInt(.speedlimitAbs)
        slots = (try? c.decode([QueueSlot].self, forKey: .slots)) ?? []
        jobCount = max(c.lossyInt(.noofslotsTotal), c.lossyInt(.noofslots), slots.count)
        warningCount = c.lossyInt(.haveWarnings)
        loadAverage = c.lossyString(.loadavg)
    }

    /// `timeLeft` ("1:02:03", or with days "2:01:02:03") in seconds; nil when there's none.
    var secondsLeft: Int? {
        let parts = timeLeft.split(separator: ":").compactMap { Int($0) }
        guard (1...4).contains(parts.count) else { return nil }
        let total = zip(parts, [86_400, 3600, 60, 1].suffix(parts.count)).map(*).reduce(0, +)
        return total > 0 ? total : nil
    }

    /// The 1, 5 and 15 minute load averages, without the extras some versions append.
    var loadAverages: String? {
        let values = loadAverage.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { Double($0) != nil }
        return values.isEmpty ? nil : values.prefix(3).joined(separator: ", ")
    }
}

nonisolated struct QueueSlot: Decodable, Identifiable, Equatable, Hashable, Sendable {
    var id: String
    var index: Int
    var filename: String
    var status: String
    var priority: Priority
    var category: String
    var megabytes: Double
    var megabytesLeft: Double
    var percentage: Int
    var size: String
    var sizeLeft: String
    var timeLeft: String
    var averageAge: String

    var isPaused: Bool { status.lowercased() == "paused" }
    var progress: Double { megabytes > 0 ? min(1, max(0, (megabytes - megabytesLeft) / megabytes)) : 0 }

    private enum CodingKeys: String, CodingKey {
        case nzoID = "nzo_id"
        case index, filename, status, priority, cat, mb, mbleft, percentage, size, sizeleft, timeleft
        case avgAge = "avg_age"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .nzoID)
        index = c.lossyInt(.index)
        filename = c.lossyString(.filename)
        status = c.lossyString(.status)
        priority = Priority(apiValue: c.lossyString(.priority))
        category = c.lossyString(.cat)
        megabytes = c.lossyDouble(.mb)
        megabytesLeft = c.lossyDouble(.mbleft)
        percentage = c.lossyInt(.percentage)
        size = c.lossyString(.size)
        sizeLeft = c.lossyString(.sizeleft)
        timeLeft = c.lossyString(.timeleft)
        averageAge = c.lossyString(.avgAge)
    }
}
