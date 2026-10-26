import Foundation

/// What a scene-style release name says about itself: "Movie.2024.2160p.WEB-DL.DV.HDR10.DDP5.1.Atmos.H.265-GROUP".
/// Works on any release, whatever attributes its indexer sends.
nonisolated struct ReleaseName: Sendable {
    var resolution: String?
    var source: String?
    var codec: String?
    var hdr: [String] = []
    var audio: [String] = []
    var group: String?

    /// Everything found, in reading order, for showing as tags.
    var tags: [String] {
        [resolution, source, codec].compactMap { $0 } + hdr + audio
    }

    init(_ title: String) {
        resolution = Self.first(in: title, [
            ("2160p", "2160p|4k|uhd"), ("1080p", "1080[pi]"), ("720p", "720p"), ("576p", "576[pi]"), ("480p", "480[pi]"),
        ])
        source = Self.first(in: title, [
            ("Remux", "remux"), ("BluRay", "blu-?ray|bdrip|brrip"), ("WEB-DL", "web-?dl"), ("WEBRip", "web-?rip"),
            ("WEB", "web"), ("HDTV", "hdtv"), ("DVD", "dvd(?:rip|r|9|5)?"),
        ])
        codec = Self.first(in: title, [
            ("AV1", "av1"), ("HEVC", "[xh]\\.?265|hevc"), ("AVC", "[xh]\\.?264|avc"), ("VC-1", "vc-?1"), ("XviD", "xvid"),
        ])
        if Self.matches(title, "dv|dovi|dolby[ .]?vision") { hdr.append("Dolby Vision") }
        if Self.matches(title, "hdr10\\+|hdr10plus") {
            hdr.append("HDR10+")
        } else if Self.matches(title, "hdr10") {
            hdr.append("HDR10")
        } else if Self.matches(title, "hdr") {
            hdr.append("HDR")
        }
        if Self.matches(title, "hlg") { hdr.append("HLG") }
        // Audio formats run straight into their channels ("DDP5.1"), so a digit may follow them.
        if let format = Self.first(in: title, digitsAfter: true, [
            ("DTS-HD MA", "dts-?hd[ .]?ma"), ("DTS:X", "dts[ .:-]?x"), ("TrueHD", "truehd"), ("DTS", "dts"),
            ("DD+", "ddp|dd\\+|e-?ac-?3"), ("DD", "dd|ac-?3"), ("AAC", "aac"), ("FLAC", "flac"), ("Opus", "opus"), ("MP3", "mp3"),
        ]) {
            // The channel count follows the format: "DDP5.1", "TrueHD.7.1".
            let channels = Self.capture(in: title, "(?:ddp|dd\\+?|truehd|dts(?:-?hd[ .]?ma)?|aac|e-?ac-?3|ac-?3|flac|opus)[ .]?([1-7][ .][01])")
            audio.append([format, channels?.replacingOccurrences(of: " ", with: ".")].compactMap { $0 }.joined(separator: " "))
        }
        if Self.matches(title, "atmos") { audio.append("Atmos") }
        // The group follows the last hyphen, after the last dot: "…H.265-GROUP".
        if let group = Self.capture(in: title, "-([A-Za-z0-9]+)(?:\\.[a-z0-9]{2,4})?$"), group.count <= 20 {
            self.group = group
        }
    }

    /// A pattern standing as its own word: between dots, spaces, hyphens, brackets or the ends.
    private static func word(_ pattern: String, digitsAfter: Bool) -> String {
        "(?<![a-z0-9])(?:\(pattern))(?![a-z\(digitsAfter ? "" : "0-9")])"
    }

    private static func matches(_ title: String, _ pattern: String, digitsAfter: Bool = false) -> Bool {
        title.range(of: word(pattern, digitsAfter: digitsAfter), options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func first(in title: String, digitsAfter: Bool = false, _ candidates: [(name: String, pattern: String)]) -> String? {
        candidates.first { matches(title, $0.pattern, digitsAfter: digitsAfter) }?.name
    }

    private static func capture(in title: String, _ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: title)
        else { return nil }
        return String(title[range])
    }
}
