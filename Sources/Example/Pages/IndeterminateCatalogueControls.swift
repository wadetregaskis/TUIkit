//  🖥️ TUIkit — Terminal UI Kit for Swift
//  IndeterminateCatalogueControls.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// The ProgressView page's controls for its indeterminate catalogue: the speed
/// every bar in it runs at, and the width they are all drawn at.
///
/// They exist so the bars' speeds can be judged by watching them rather than by
/// arithmetic, and at more than one width: a sweep takes the same time to cross
/// a bar of any width, so its head moves across 8 cells at under a quarter of
/// the pace it moves across 36, while a barberPole shifts one cell a frame
/// whatever the width. Both controls are pickers, so both are reachable from
/// the keyboard.
struct IndeterminateCatalogueControls: View {
    /// The speed, as an `IndeterminateSpeedChoice` name.
    @Binding var speed: String
    /// The bars' width in cells.
    @Binding var width: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("page.progressView.indeterminateSpeed", selection: speedBinding) {
                Text("page.progressView.speedAutomatic").tag(IndeterminateSpeedChoice.automatic)
                Text("page.progressView.speedHalf").tag(IndeterminateSpeedChoice.half)
                Text("page.progressView.speedStandard").tag(IndeterminateSpeedChoice.standard)
                Text("page.progressView.speedDouble").tag(IndeterminateSpeedChoice.double)
            }
            Picker("page.progressView.indeterminateWidth", selection: widthBinding) {
                ForEach(IndeterminateCatalogueWidth.choices, id: \.self) { cells in
                    Text(verbatim: "\(cells)").tag(cells)
                }
            }
        }
    }

    /// The picker's selection, over the stored name.
    private var speedBinding: Binding<IndeterminateSpeedChoice> {
        Binding(
            get: { IndeterminateSpeedChoice(stored: speed) },
            set: { speed = $0.rawValue })
    }

    /// The stored width, as one of the picker's choices.
    private var widthBinding: Binding<Int> {
        Binding(
            get: { IndeterminateCatalogueWidth.valid(width) },
            set: { width = IndeterminateCatalogueWidth.valid($0) })
    }
}

/// The speeds the indeterminate catalogue offers: the recommended presets.
///
/// Not the Spinners page's `SpinnerSpeedChoice`, which also has a custom rate
/// and tolerance, and whose labels are that page's strings. A tolerance moves
/// only a sequence's frames, and of the bars only a barberPole is one, so the
/// presets are what there is to compare here.
enum IndeterminateSpeedChoice: String, CaseIterable, Hashable {
    case automatic, half, standard, double

    /// The choice stored as `name`; a name nothing matches reads as Automatic,
    /// the speed an app has when it sets none.
    init(stored name: String) {
        self = Self(rawValue: name) ?? .automatic
    }

    /// The speed the catalogue's bars run at.
    var speed: IndicatorAnimationSpeed {
        switch self {
        case .automatic: .automatic
        case .half: .halfSpeed
        case .standard: .standard
        case .double: .doubleSpeed
        }
    }
}

/// The widths the indeterminate catalogue offers, in cells.
///
/// No wider than 36. The page's two columns begin at 106 terminal columns, a
/// column is then about 52 cells, and a row is a 13-cell label, a one-cell gap
/// and the bar, so 80 cells could never be drawn whole beside the other column.
enum IndeterminateCatalogueWidth {
    static let choices = [8, 20, 36]
    /// The width the catalogue has always drawn at.
    static let standard = 36

    /// `width` if the picker offers it, otherwise the standard width.
    static func valid(_ width: Int) -> Int {
        choices.contains(width) ? width : standard
    }
}
