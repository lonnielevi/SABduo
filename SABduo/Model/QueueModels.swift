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

    var bytesPerSecond: Double { kbPerSec * 1024 }

    private enum CodingKeys: String, CodingKey {
        case paused, status, kbpersec, timeleft, sizeleft, slots
        case speedlimitAbs = "speedlimit_abs"
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
