//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FollowMarginPicker.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// The scroll-follow-margin choices the demo pages offer, mapped to the
/// framework's `ScrollFollowMargin` values.
enum FollowMarginChoice: Int, CaseIterable {
    case none
    case twoLines
    case centered

    /// The framework value this choice selects.
    var margin: ScrollFollowMargin {
        switch self {
        case .none: .none
        case .twoLines: .lines(2)
        case .centered: .centered
        }
    }

    /// The localized option label.
    var label: String {
        switch self {
        case .none: L("demo.followMargin.none")
        case .twoLines: L("demo.followMargin.lines2")
        case .centered: L("demo.followMargin.centered")
        }
    }
}

/// A compact picker for the scroll-follow margin, shared by the List, Table,
/// and ScrollView demo pages: as the selection (or focused control) nears a
/// viewport edge, the margin decides how early the view starts scrolling —
/// none (classic edge-triggered, the default), two lines early, or keeping
/// the selection centred. Apply the chosen value with
/// `.scrollFollowMargin(choice.margin)`.
struct FollowMarginPicker: View {
    @Binding var selection: Int

    var body: some View {
        Picker(L("demo.followMargin"), selection: $selection) {
            ForEach(FollowMarginChoice.allCases, id: \.rawValue) { choice in
                Text(choice.label).tag(choice.rawValue)
            }
        }
    }
}
