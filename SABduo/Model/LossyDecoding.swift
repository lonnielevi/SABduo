import Foundation

/// SABnzbd encodes most numbers as strings ("12.34") and a few as real numbers.
/// These helpers accept either form so a server-side change doesn't break decoding.
nonisolated extension KeyedDecodingContainer {
    func lossyDouble(_ key: Key) -> Double {
        if let d = try? decode(Double.self, forKey: key) { return d }
        if let s = try? decode(String.self, forKey: key), let d = Double(s.trimmingCharacters(in: .whitespaces)) { return d }
        return 0
    }

    func lossyInt(_ key: Key) -> Int {
        if let i = try? decode(Int.self, forKey: key) { return i }
        return Int(lossyDouble(key))
    }

    func lossyString(_ key: Key) -> String {
        if let s = try? decode(String.self, forKey: key) { return s }
        if let i = try? decode(Int.self, forKey: key) { return String(i) }
        if let d = try? decode(Double.self, forKey: key) { return String(d) }
        return ""
    }

    func lossyBool(_ key: Key) -> Bool {
        if let b = try? decode(Bool.self, forKey: key) { return b }
        if let i = try? decode(Int.self, forKey: key) { return i != 0 }
        if let s = try? decode(String.self, forKey: key) { return ["1", "true", "yes"].contains(s.lowercased()) }
        return false
    }
}
