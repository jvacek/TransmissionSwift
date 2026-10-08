import Foundation

/// One remote peer currently connected to a torrent.
public struct Peer: Identifiable, Hashable, Sendable {
    /// IP is unique within the current peer snapshot but not stable across polls.
    public var id: String { ipAddress }
    public var ipAddress: String
    public var client: String
    /// Two-letter ISO country code, e.g. "NL". nil when GeoIP is unavailable.
    public var countryCode: String?
    /// One-letter flags string per the Transmission peer flag glossary
    /// (`U`/`D`/`E`/`H`/`X`, lowercase = peer-side). Rendered monospaced.
    public var flags: String
    public var progress: Double
    public var downloadSpeed: Int64
    public var uploadSpeed: Int64

    public init(
        ipAddress: String,
        client: String,
        countryCode: String? = nil,
        flags: String,
        progress: Double,
        downloadSpeed: Int64,
        uploadSpeed: Int64
    ) {
        self.ipAddress = ipAddress
        self.client = client
        self.countryCode = countryCode
        self.flags = flags
        self.progress = progress
        self.downloadSpeed = downloadSpeed
        self.uploadSpeed = uploadSpeed
    }
}
