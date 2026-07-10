import Foundation
import SwiftUI
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

    static func etaColor(for status: TorrentStatus) -> Color {
        switch status {
        case .downloading, .checking: return .primary
        case .seeding, .completed: return .secondary
        case .paused, .queued, .error: return .secondary
        }
    }

    static func ratioTextAndColor(_ ratio: Double) -> (String, Color?) {
        if ratio == 0 { return ("\u{2014}", nil) }
        let text = String(format: "%.2f", ratio)
        let color: Color?
        if ratio >= 1.0 { color = .green } else if ratio >= 0.5 { color = .orange } else { color = .red }
        return (text, color)
    }

    static func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// Render speed with the numeric value in `color` and the unit in a
    /// smaller muted font.
    @ViewBuilder
    static func speedView(_ bytesPerSecond: Int64, color: Color) -> some View {
        let text = humanizedSpeed(bytesPerSecond)
        if text == "\u{2014}" {
            Text(text).monospacedDigit().foregroundStyle(.tertiary)
        } else if let spaceIndex = text.firstIndex(of: " ") {
            HStack(spacing: 0) {
                Text(text[..<spaceIndex]).monospacedDigit().foregroundStyle(color)
                Text(text[spaceIndex...]).font(.caption2).foregroundStyle(color.mix(with: .gray, by: 0.4))
            }
        } else {
            Text(text).monospacedDigit().foregroundStyle(color)
        }
    }

    static func statusContent(_ status: TorrentStatus) -> (Color, String) {
        switch status {
        case .downloading: return (.blue, "Downloading")
        case .seeding: return (.green, "Seeding")
        case .completed: return (.green, "Completed")
        case .paused: return (.gray, "Paused")
        case .checking: return (.orange, "Checking")
        case .queued: return (.orange, "Queued")
        case .error: return (.red, "Error")
        }
    }

    static func priorityView(_ priority: TorrentPriority) -> some View {
        let (image, color, label): (String, Color, String) = {
            switch priority {
            case .high: return ("chevron.up", .orange, "High")
            case .low: return ("chevron.down", .blue, "Low")
            case .normal: return ("minus", .gray, "Normal")
            }
        }()
        return HStack(spacing: 2) {
            Image(systemName: image)
                .foregroundStyle(color)
                .font(.system(size: 11, weight: .medium))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .help(label)
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
