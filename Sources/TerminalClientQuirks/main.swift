//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT
//
//  A combined diagnostic and demonstration of terminal-client determination and
//  the workarounds for the clients that need them.

import TUIkit

/// Terminal Client Quirks — what TUIkit thinks your terminal is, why, and what
/// it is doing differently as a result.
///
/// Five screens, in the order the questions arise:
///
/// 1. **Identity** — which terminal, and which signal named it. Over ssh this
///    is usually the whole story: `TERM_PROGRAM` does not survive the hop, so a
///    terminal that is perfectly well known locally arrives anonymous, and an
///    anonymous terminal is (correctly) left alone.
/// 2. **Render as** — pick a known client and see the app as it would be
///    drawn for that terminal, whatever this one is.
/// 3. **Quirks** — the measured advance model for that terminal, cluster class
///    by cluster class, and the workaround applied to each divergence.
/// 4. **Alignment** — the check that does not take any of the above on trust.
/// 5. **Custom** — a quirks record edited by hand, with the Swift literal that
///    would ship it.
struct TerminalClientQuirksApp: App {
    var body: some Scene {
        WindowGroup {
            QuirksContentView()
        }
    }
}

/// The tab host. `TerminalClient.current` is read once here rather than in each
/// screen: it cannot change while the app runs (the identification happens
/// before the first frame), and reading it once means the five screens cannot
/// disagree about what they are describing.
struct QuirksContentView: View {
    @State private var tab = 0

    /// The client being simulated, or `nil` to use the one detected. Mirrors
    /// ``TUIkit/TerminalClient/simulated``, which is what the renderer reads —
    /// this is the control's copy of it.
    @State private var simulated: TerminalClient.Program?

    var body: some View {
        // Read per frame, not once: the "Render as" screen changes it, and every
        // other screen has to describe what is actually being applied.
        let client = TerminalClient.effective
        let detected = TerminalClient.current.program
        TabView(selection: $tab) {
            Tab("Identity", value: 0) {
                ScrollView {
                    IdentificationView(client: client)
                }
            }
            Tab("Render as", value: 1) {
                ScrollView {
                    ClientPickerView(selection: $simulated, detected: detected)
                }
            }
            Tab("Quirks", value: 2) {
                ScrollView {
                    QuirkTableView(client: client)
                }
            }
            Tab("Alignment", value: 3) {
                ScrollView {
                    AlignmentCheckView(client: client)
                }
            }
            Tab("Custom", value: 4) {
                ScrollView {
                    CustomClientView(client: client)
                }
            }
        }
        .padding(.horizontal, 1)
        .appHeader {
            VStack(alignment: .leading, spacing: 0) {
                Text("Terminal Client Quirks").bold()
                Text("what TUIkit thinks your terminal is, why, and what it does about it")
                    .foregroundStyle(.palette.foregroundSecondary)
            }
        }
        .statusBarItems {
            StatusBarItem(shortcut: "q", label: "quit")
        }
    }
}

await TerminalClientQuirksApp.main()
