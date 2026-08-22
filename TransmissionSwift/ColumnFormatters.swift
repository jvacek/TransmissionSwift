import Foundation
import TransmissionCore

enum ColumnFormatters {
    static func humanizedSize(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        if unitIndex == 0 {
            return "\(Int(value)) \(units[unitIndex])"
        }
        return String(format: "%.1f %@", value, units[unitIndex])
    }

    static func humanizedSpeed(_ bytesPerSecond: Int64) -> String {
        if bytesPerSecond == 0 { return "\u{2014}" }
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = Double(bytesPerSecond)
        var unitIndex = 0
        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        return String(format: "%.1f %@", value, units[unitIndex])
    }

    /// Splits `humanizedSpeed` into its numeric and unit parts ("2.3", "MB/s")
    /// for the native two-part speed cell. The raw string is still used for the
    /// accessibility label.
    static func speedParts(_ bytesPerSecond: Int64) -> (value: String, unit: String) {
        let text = humanizedSpeed(bytesPerSecond)
        guard let spaceIndex = text.firstIndex(of: " ") else { return (text, "") }
        return (
            String(text[..<spaceIndex]),
            String(text[text.index(after: spaceIndex)...])
        )
    }

    static func humanizedETA(_ eta: TimeInterval?, status: TorrentStatus) -> String {
        guard let eta, eta.isFinite else {
            switch status {
            case .seeding, .completed: return "\u{221E}"
            case .paused, .error, .queued: return "\u{2014}"
            default: return "\u{2014}"
            }
        }
        if eta <= 0 { return "0s" }
        let hours = Int(eta) / 3600
        let minutes = (Int(eta) % 3600) / 60
        let seconds = Int(eta) % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    // Formatter allocation is expensive (locale tables); reuse one instance.
    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func relativeDate(_ date: Date) -> String {
        relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }

    static func queuePosition(_ position: Int?) -> String {
        position.map { "#\($0)" } ?? "\u{2014}"
    }

    static func piecesText(have: Int, total: Int) -> String {
        "\(have)/\(total)"
    }

    static func truncatedPath(_ path: String, relativeTo base: String?) -> String {
        guard let base = base, !base.isEmpty else { return path }
        if path == base { return "./" }
        if path.hasPrefix(base + "/") {
            return String(path.dropFirst(base.count + 1))
        }
        return path
    }
}
