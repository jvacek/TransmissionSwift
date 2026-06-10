/// Interface to a remote Transmission daemon.
///
/// The app and core layers depend on this protocol rather than a concrete
/// implementation, so tests can substitute a fake client.
public protocol TransmissionClient: Sendable {
    func sessionGet() async throws(TransmissionError) -> SessionInfo
}
