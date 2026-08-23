import AppKit
import SwiftUI

/// Tag chip input: a wrapping row of removable chips plus an inline text field
/// that commits on Return. Validation mirrors the daemon's `makeLabels` rules
/// (whitespace-stripped, non-empty, no commas) and dedupes case-sensitively —
/// the daemon stores labels as a deduped set.
///
/// When `suggestions` is non-empty, a `+` menu lists existing labels not yet
/// added so the user can re-apply tags already in use on the server.
struct TagsInputField: View {
    @Binding var tags: [String]
    var suggestions: [String] = []

    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    private var availableSuggestions: [String] {
        suggestions.filter { !tags.contains($0) }.sorted()
    }

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                TagChip(tag: tag) { remove(tag) }
            }

            TextField("Add tag…", text: $draft)
                .textFieldStyle(.plain)
                .frame(width: 120)
                .focused($fieldFocused)
                .onSubmit(commit)

            if !availableSuggestions.isEmpty {
                Menu {
                    ForEach(availableSuggestions, id: \.self) { suggestion in
                        Button(suggestion) { add(suggestion) }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Add an existing tag")
                .accessibilityLabel("Add existing tag")
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(fieldFocused ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.2))
        )
        .onTapGesture { fieldFocused = true }
        .accessibilityElement(children: .contain)
    }

    private func add(_ raw: String) {
        let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty, !tag.contains(","), !tags.contains(tag) else { return }
        tags.append(tag)
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !tags.contains(trimmed) {
            if trimmed.contains(",") {
                NSSound.beep()
            } else {
                tags.append(trimmed)
            }
        }
        draft = ""
    }

    private func remove(_ tag: String) {
        tags.removeAll { $0 == tag }
    }
}

private struct TagChip: View {
    let tag: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Remove tag \(tag)")
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }
}

/// Minimal wrapping layout for the chip + field row.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
