import SwiftUI

struct AboutView: View {
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            Text("TransmissionSwift")
                .font(.title2)
                .fontWeight(.medium)

            Text("Version \(appVersion) (\(buildNumber))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Link(
                "github.com/jvacek/TransmissionSwift",
                destination: URL(string: "https://github.com/jvacek/TransmissionSwift")!
            )
            .font(.subheadline)

            Divider()
                .frame(width: 240)

            Text(
                "A native macOS remote control for the Transmission BitTorrent daemon."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 260)
        }
        .padding(20)
        .frame(width: 300)
    }
}
