// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

/// A Liquid Glass segmented control: one glass capsule holding the segments,
/// with a selection pill that slides between them.
///
/// Hand-rolled because the stock `.segmented` picker keeps its pre-Tahoe
/// chrome in content areas, won't stretch to fill its width, and drops
/// `Label` icons.
struct GlassSegmentedControl<Value: Hashable, SegmentLabel: View>: View {
    enum Indicator {
        /// A solid accent pill. Labels should switch to white when selected.
        case accent
        /// A raised glass pill inside the track, as in Xcode's inspector tabs.
        case glass
    }

    @Binding var selection: Value
    let values: [Value]
    var indicator: Indicator = .accent
    /// Stretch the segments equally across the available width.
    var fillsWidth = false
    let accessibilityLabel: (Value) -> String
    @ViewBuilder let label: (_ value: Value, _ isSelected: Bool) -> SegmentLabel

    @Namespace private var pill

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 0) {
                ForEach(values, id: \.self) { value in
                    segment(value)
                }
            }
            .padding(indicator == .glass ? 2 : 0)
            .glassEffect(indicator == .glass ? .regular : .regular.interactive(), in: .capsule)
        }
        .accessibilityElement(children: .contain)
    }

    private func segment(_ value: Value) -> some View {
        let isSelected = selection == value
        return Button {
            withAnimation(.smooth(duration: 0.3)) { selection = value }
        } label: {
            label(value, isSelected)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .background {
                    // One pill moving between segments, so it slides instead
                    // of fading out and back in.
                    if isSelected {
                        selectionPill.matchedGeometryEffect(id: "selection", in: pill)
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(value))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var selectionPill: some View {
        switch indicator {
        case .accent:
            Capsule().fill(Color.accentColor)
        case .glass:
            Capsule().fill(.clear).glassEffect(.regular.interactive(), in: .capsule)
        }
    }
}
