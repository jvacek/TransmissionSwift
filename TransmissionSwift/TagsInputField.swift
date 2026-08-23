import AppKit
import SwiftUI
import TransmissionCore

/// Tag chip input: a wrapping row of removable chips plus an inline text field
/// that commits on Return. Validation mirrors the daemon's `makeLabels` rules
/// (whitespace-stripped, non-empty, no commas) and dedupes case-sensitively —
/// the daemon stores labels as a deduped set.
///
/// Typing shows an inline suggestion list of existing tags whose prefix matches
/// the draft (each with its colour dot); ↑/↓ move the highlight, Return or a
/// click applies the highlighted tag, and Return with no match creates a new
/// tag. Chips are colour-aware, matching the table pills.
struct TagsInputField: View {
    @Binding var tags: [String]
    var suggestions: [String] = []

    @Environment(TagColorStore.self) private var tagColors
    @State private var draft = ""
    @State private var highlightedIndex = 0
    @FocusState private var fieldFocused: Bool

    private var availableSuggestions: [String] {
        suggestions.filter { !tags.contains($0) }.sorted()
    }

    private var matches: [String] {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let needle = trimmed.lowercased()
        return availableSuggestions.filter { $0.lowercased().hasPrefix(needle) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            chipRow
            if fieldFocused && !matches.isEmpty {
                suggestionCard
            }
        }
        .onChange(of: draft) { _, _ in highlightedIndex = 0 }
        .accessibilityElement(children: .contain)
    }

    private var chipRow: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                TagChip(tag: tag, color: tagColors.color(for: tag)) { remove(tag) }
            }

            TextField("Add tag…", text: $draft)
                .textFieldStyle(.plain)
                .frame(width: 120)
                .focused($fieldFocused)
                .onSubmit(commit)
                .onKeyPress(.upArrow) { moveHighlight(by: -1) }
                .onKeyPress(.downArrow) { moveHighlight(by: 1) }
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
    }

    /// Inline popover-style list of tags matching the draft. Each row shows the
    /// tag's colour dot; the highlighted row (↑/↓) is tinted and shows a Return
    /// hint.
    private var suggestionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(matches.enumerated()), id: \.element) { index, name in
                Button {
                    applySuggestion(name)
                } label: {
                    HStack(spacing: 6) {
                        TagColorDot(color: tagColors.color(for: name))
                        Text(name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        if index == highlightedIndex {
                            Image(systemName: "return")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .background(
                        index == highlightedIndex
                            ? Color.accentColor.opacity(0.15)
                            : Color.clear
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.25))
        )
        .shadow(color: Color.black.opacity(0.12), radius: 6, y: 3)
        .padding(.trailing, 24)
    }

    // MARK: - Editing

    private func applySuggestion(_ name: String) {
        guard !tags.contains(name) else { return }
        tags.append(name)
        draft = ""
        highlightedIndex = 0
    }

    private func moveHighlight(by delta: Int) -> KeyPress.Result {
        guard !matches.isEmpty else { return .ignored }
        highlightedIndex = (highlightedIndex + delta + matches.count) % matches.count
        return .handled
    }

    private func commit() {
        if !matches.isEmpty {
            applySuggestion(matches[highlightedIndex])
            return
        }
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
    let color: TagColor?
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 3) {
            Text(tag)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(color?.pillForeground ?? .secondary)
            .accessibilityLabel("Remove tag \(tag)")
        }
        .font(.callout)
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 2)
        .foregroundStyle(color?.pillForeground ?? .primary)
        .modifier(TagCapsuleBackground(color: color))
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
