//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SpinnerStyleChoice.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// The built-in ``SpinnerStyle`` catalogue as a pickable, persistable list.
///
/// Its own type because two pages need the same list and neither should own it:
/// the Spinners page's editor, and the Lifecycle page's `.refreshable`
/// indicator. The raw values are the API case names — an API surface, so
/// deliberately untranslated, exactly as the style catalogue's labels are.
enum SpinnerStyleChoice: String, CaseIterable {
    // In the catalogue's own order, which groups each style with the ones it is
    // easy to mistake it for — the two line rotations together, the four circular
    // ones together, `column` beside its sideways twin `bar`.
    case dots, line, dancingLine, bouncing, pie, beachball, box, curve
    case column, bar, shade, blockWedge, spinningTriangle, moon, earth, clock

    /// The style itself.
    var style: SpinnerStyle {
        switch self {
        case .dots: .dots
        case .line: .line
        case .dancingLine: .dancingLine
        case .bouncing: .bouncing
        case .pie: .pie
        case .beachball: .beachball
        case .box: .box
        case .curve: .curve
        case .column: .column
        case .bar: .bar
        case .shade: .shade
        case .blockWedge: .blockWedge
        case .spinningTriangle: .spinningTriangle
        case .moon: .moon
        case .earth: .earth
        case .clock: .clock
        }
    }
}

/// A picker over the built-in spinner styles, showing each one *running* beside
/// its name — the only way to choose a spinner that answers the question you
/// are actually asking.
struct SpinnerStylePicker: View {
    let titleKey: LocalizedStringKey
    @Binding var selection: String

    var body: some View {
        Picker(titleKey, selection: $selection) {
            ForEach(SpinnerStyleChoice.allCases, id: \.rawValue) { choice in
                Text(verbatim: choice.rawValue).tag(choice.rawValue)
            }
        }
    }
}
