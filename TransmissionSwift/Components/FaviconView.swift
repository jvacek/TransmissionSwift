import SwiftUI

/// Renders a tracker's favicon inside a neat squircle, falling back to the
/// globe glyph when no icon is available or fetching is disabled.
struct FaviconView: View {
    let host: String
    @Environment(FaviconStore.self) private var favicons

    var body: some View {
        if let image = favicons.image(for: host) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(2)
                .background(.fill.tertiary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                .transition(.scale.combined(with: .opacity))
        } else {
            Image(systemName: "globe")
                .transition(.scale.combined(with: .opacity))
        }
    }
}
