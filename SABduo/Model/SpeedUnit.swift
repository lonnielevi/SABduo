import SwiftUI

/// The unit download speeds show in, picked in Settings or by tapping the speed. Bits count in
/// thousands, as networks quote them; bytes in 1024s, as SABnzbd does.
enum SpeedUnit: String, CaseIterable, Identifiable {
    case kilobits, megabits, gigabits, kilobytes, megabytes, gigabytes

    static let storageKey = "speedUnit"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .kilobits: "Kb/s"
        case .megabits: "Mb/s"
        case .gigabits: "Gb/s"
        case .kilobytes: "KB/s"
        case .megabytes: "MB/s"
        case .gigabytes: "GB/s"
        }
    }

    var name: String {
        switch self {
        case .kilobits: "Kilobits per second"
        case .megabits: "Megabits per second"
        case .gigabits: "Gigabits per second"
        case .kilobytes: "Kilobytes per second"
        case .megabytes: "Megabytes per second"
        case .gigabytes: "Gigabytes per second"
        }
    }

    private var bytesPerUnit: Double {
        switch self {
        case .kilobits: 125
        case .megabits: 125_000
        case .gigabits: 125_000_000
        case .kilobytes: 1024
        case .megabytes: 1_048_576
        case .gigabytes: 1_073_741_824
        }
    }

    /// The unit after this one, back to the first after the last.
    var next: SpeedUnit {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    /// "12.6 MB/s": three significant figures or so, whatever the size.
    func format(_ bytesPerSecond: Double) -> String {
        let value = bytesPerSecond / bytesPerUnit
        let decimals = value == 0 || value >= 100 ? 0 : value >= 10 ? 1 : 2
        return value.formatted(.number.precision(.fractionLength(decimals))) + " " + symbol
    }
}

/// How the queue's time left shows: counting down, or the time it'll finish.
enum TimeLeftStyle: String, CaseIterable, Identifiable {
    case countdown, finishTime

    static let storageKey = "timeLeftStyle"

    var id: Self { self }

    var name: String {
        switch self {
        case .countdown: "Countdown"
        case .finishTime: "Finish Time"
        }
    }

    var other: TimeLeftStyle { self == .countdown ? .finishTime : .countdown }
}

/// Light or dark, or following the system.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearance"

    var id: Self { self }

    var name: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// nil follows the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// A prompt before removing something, each turned off on its own by its "Don't Ask Again".
enum RemovalPrompt: String, CaseIterable {
    case clearQueue, deleteJob, clearAllHistory, clearCompletedHistory, clearFailedHistory

    static let storageKey = "skippedRemovalPrompts"
}

/// The prompts turned off, saved as their names; Settings' Reset Prompts empties it.
struct SkippedPrompts: RawRepresentable {
    private var prompts: Set<RemovalPrompt>

    init() { prompts = [] }

    init(rawValue: String) {
        prompts = Set(rawValue.split(separator: ",").compactMap { RemovalPrompt(rawValue: String($0)) })
    }

    var rawValue: String { prompts.map(\.rawValue).sorted().joined(separator: ",") }

    var isEmpty: Bool { prompts.isEmpty }

    func asks(_ prompt: RemovalPrompt) -> Bool { !prompts.contains(prompt) }

    mutating func skip(_ prompt: RemovalPrompt) { prompts.insert(prompt) }
}
