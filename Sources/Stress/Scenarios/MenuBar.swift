//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MenuBar.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// MARK: - Menu Bar

/// Menus and styled controls at scale — the shape the rest of this catalogue
/// did not have.
///
/// Before this, `grep` found no `Menu` and exactly one `Button` across all
/// twenty scenarios, so `ab_bench` was blind to every control that draws through
/// a `ButtonStyle`. That is not a small gap: a `ButtonStyle`'s body is handed no
/// render context, so it is the one place a view must read `@Environment` to be
/// drawn at all — and it was where a change worth **-14%** on the Mode A `menu`
/// tree read "indistinguishable" across the entire sweep.
///
/// Each column is an inline `Menu` whose rows are `Button`s carrying key
/// equivalents, so the rows draw a hint column that BOTH passes must see (a
/// measure that missed it sizes the menu too narrow for the render to fit).
/// Beside them, the built-in button styles, whose bodies are procedural where a
/// menu row's is structural — the two halves of `_ButtonCore`'s measure gate.
enum MenuBarScenario {
    @MainActor
    static let descriptor = Scenario(
        id: "menus",
        title: "Menu Bar",
        blurb: "Inline menus of shortcut-bearing rows, beside every built-in button style.",
        stresses:
            "ButtonStyle body measure · menu hug-width pass · shortcut hint column · per-row @Environment resolution",
        make: { config in AnyView(MenuBarView(config: config)) }
    )
}

private struct MenuBarView: View {
    let config: StressConfig

    var body: some View {
        let columns = config.sized(3)
        let rows = config.sized(6)
        VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.menus.heading", columns, rows)).bold()
            HStack(alignment: .top) {
                ForEach(0..<columns, id: \.self) { column in
                    MenuColumn(seed: mix(config.seed, column), rows: rows)
                }
            }
            StyledButtonRow(seed: mix(config.seed, 900))
        }
        .padding()
    }
}

/// One inline menu. A separate view so its `Menu` keeps its concrete content
/// type: a `ForEach` reaching a `Menu` through an `AnyView` renders nothing,
/// because `AnyView` is not a `ChildViewProvider` and the rows never resolve.
private struct MenuColumn: View {
    let seed: UInt64
    let rows: Int

    var body: some View {
        Menu(Synth.name(seed)) {
            ForEach(0..<rows, id: \.self) { row in
                Button(Synth.name(mix(seed, row))) {}
                    .keyboardShortcut(
                        MenuBarKeys.key(row), modifiers: [])
            }
        }
        .menuStyle(.inline)
    }
}

/// The key equivalents the rows advertise.
///
/// Bare, not `.command`: a terminal never reports the command key, so `[]` is
/// the form that both resolves to a printable hint and actually fires.
private enum MenuBarKeys {
    static let all: [KeyEquivalent] = ["a", "b", "c", "d", "e", "f", "g", "h"]

    static func key(_ index: Int) -> KeyEquivalent { all[index % all.count] }
}

/// Every built-in `ButtonStyle`, whose bodies are procedural — the other half of
/// the measure gate from the menu rows above, whose bodies are structural.
private struct StyledButtonRow: View {
    let seed: UInt64

    var body: some View {
        HStack {
            Button(Synth.name(mix(seed, 1))) {}.buttonStyle(.default)
            Button(Synth.name(mix(seed, 2))) {}.buttonStyle(.primary)
            Button(Synth.name(mix(seed, 3))) {}.buttonStyle(.success)
            Button(Synth.name(mix(seed, 4))) {}.buttonStyle(.destructive)
            Button(Synth.name(mix(seed, 5))) {}.buttonStyle(.plain)
        }
        .padding()
    }
}
