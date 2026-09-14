//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KeyRows.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// MARK: - Key Rows

/// Memoized rows that each register into the per-frame key registries: the
/// shape that decides whether a memo can keep a subtree's registrations alive.
///
/// No other scenario puts a registration under a memo. Every row here is keyed
/// on an `Equatable` element, so `ForEach` wraps it in `_MemoizedRow`, and every
/// row registers twice: `.onKeyPress(keys:)` into the key dispatcher and
/// `.statusBarItems` into the status bar. The render loop empties both before
/// every walk, so a row served from the cache has to make them again or they are
/// gone. The `.focusSection` sits ABOVE the rows, so its own registration never
/// holds them out of the cache. Beside them, one `.refreshable` panel binds
/// Ctrl-R.
///
/// It needs the bench's key channels (`HeadlessKeyChannels`): an `onKeyPress`
/// with no dispatcher traps.
enum KeyRowsScenario {
    @MainActor
    static let descriptor = Scenario(
        id: "keyrows",
        title: "Key Rows",
        blurb: "Memoized rows that each register a key handler and status-bar items, beside a refreshable panel.",
        stresses: "per-row registrations under the row memo · per-frame key and status-bar registries · refreshable Ctrl-R",
        make: { config in AnyView(KeyRowsView(config: config)) }
    )
}

private struct KeyRowsView: View {
    let config: StressConfig

    var body: some View {
        let rows = config.sized(30)
        VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.keyrows.heading", rows)).bold()
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<rows, id: \.self) { row in
                        KeyRow(seed: mix(config.seed, row), index: row)
                    }
                }
                .focusSection("keyrows")
                Panel(Synth.name(mix(config.seed, 900))) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<8, id: \.self) { line in
                            Text(Synth.name(mix(config.seed, 1000 + line)))
                        }
                    }
                }
                .refreshable {}
            }
        }
        .padding()
    }
}

/// One row: a name that listens for one key and advertises one item.
///
/// The handler declines every key, so a keypress in the interactive shell passes
/// straight through to it. The shortcuts are digits, which the shell does not
/// use.
private struct KeyRow: View {
    let seed: UInt64
    let index: Int

    var body: some View {
        let digit = KeyRowKeys.digit(index)
        Text(Synth.name(seed))
            .onKeyPress(keys: [.character(digit)]) { _ in false }
            .statusBarItems {
                StatusBarItem(shortcut: String(digit), label: Synth.name(mix(seed, 1)))
            }
    }
}

/// The digits the rows listen for and advertise, cycling.
private enum KeyRowKeys {
    static let all: [Character] = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

    static func digit(_ index: Int) -> Character { all[index % all.count] }
}
