import Foundation

/// Bounds for the polling preferences, shared by the preferences pane and the
/// RPC service so a field can't promise a value the service silently overrides.
public enum PollingIntervals {
    /// Full-list cadence. One second is the service floor, and past five minutes
    /// an idle library reads as frozen.
    public static let refresh: ClosedRange<Double> = 1...300

    /// Incremental cadence. It has to stay inside the daemon's 60-second
    /// `recently-active` window, with headroom for sleep jitter.
    public static let active: ClosedRange<Double> = 1...45

    /// Free-space poll. A disk-space readout gains nothing from sub-5s polling,
    /// and an hour is indistinguishable from off.
    public static let freeSpace: ClosedRange<Double> = 5...3600

    /// Whole seconds inside `range`.
    public static func normalized(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value.rounded()))
    }

    /// The incremental interval the service actually uses: its own bounds, and
    /// never slower than the full poll it runs between.
    public static func incremental(active: Double, refresh: Double) -> Double {
        min(normalized(active, to: Self.active), max(1, refresh))
    }
}
