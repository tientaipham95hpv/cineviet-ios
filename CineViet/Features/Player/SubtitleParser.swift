import Foundation

struct SubtitleCue: Equatable, Sendable {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}

enum SubtitleParser {
    static func parse(_ source: String, format: String) -> [SubtitleCue] {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{feff}", with: "")
        return format.lowercased().contains("srt") ? parseSRT(normalized) : parseWebVTT(normalized)
    }

    private static func parseSRT(_ source: String) -> [SubtitleCue] {
        blocks(source).compactMap { block in
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }),
                  let range = timeRange(lines[timingIndex]) else { return nil }
            return cue(range: range, lines: Array(lines.dropFirst(timingIndex + 1)))
        }
    }

    private static func parseWebVTT(_ source: String) -> [SubtitleCue] {
        blocks(source).compactMap { block in
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard !lines.first.map({ $0.hasPrefix("WEBVTT") || $0.hasPrefix("NOTE") })!,
                  let timingIndex = lines.firstIndex(where: { $0.contains("-->") }),
                  let range = timeRange(lines[timingIndex]) else { return nil }
            return cue(range: range, lines: Array(lines.dropFirst(timingIndex + 1)))
        }
    }

    private static func blocks(_ source: String) -> [String] {
        source.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func timeRange(_ line: String) -> (TimeInterval, TimeInterval)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2,
              let start = timestamp(parts[0]),
              let end = timestamp(parts[1].split(separator: " ").first.map(String.init) ?? parts[1]) else { return nil }
        return (start, end)
    }

    private static func timestamp(_ raw: String) -> TimeInterval? {
        let fields = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
            .split(separator: ":")
        guard fields.count == 2 || fields.count == 3,
              let seconds = Double(fields.last ?? "") else { return nil }
        let minutes = Double(fields[fields.count - 2]) ?? 0
        let hours = fields.count == 3 ? (Double(fields[0]) ?? 0) : 0
        return hours * 3600 + minutes * 60 + seconds
    }

    private static func cue(range: (TimeInterval, TimeInterval), lines: [String]) -> SubtitleCue? {
        let text = lines.joined(separator: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, range.1 > range.0 else { return nil }
        return SubtitleCue(start: range.0, end: range.1, text: text)
    }
}
