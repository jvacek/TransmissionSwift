import Foundation

extension Int64 {
    /// "5.9 GB" / "820 KB". Returns "—" for zero — speed columns lean on this
    /// so the table doesn't render "0 B/s" everywhere.
    var formattedBytes: String {
        guard self > 0 else { return "—" }
        return self.formatted(.byteCount(style: .binary))
    }

    /// "5.9 GB" but never elides zero. Use this for sizes (always present),
    /// not speeds (which want a "—" when idle).
    var formattedSize: String {
        self.formatted(.byteCount(style: .binary))
    }

    /// "11.4 MB/s" or "—" when zero.
    var formattedSpeed: String {
        guard self > 0 else { return "—" }
        return self.formatted(.byteCount(style: .binary)) + "/s"
    }
}

extension TimeInterval {
    /// "5m", "1h 30m", "Done", "∞", "—".
    var formattedETA: String {
        if isInfinite { return "∞" }
        if self <= 0 { return "Done" }
        let total = Int(self)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(seconds)s"
    }
}

extension Optional where Wrapped == TimeInterval {
    var formattedETA: String { self?.formattedETA ?? "—" }
}

extension Date {
    /// Compact date label for list columns: "Jun 10, 2026".
    var formattedDate: String {
        self.formatted(date: .abbreviated, time: .omitted)
    }
}
