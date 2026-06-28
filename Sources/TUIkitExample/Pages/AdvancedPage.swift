//  🖥️ TUIKit — Terminal UI Kit for Swift
//  AdvancedPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

// MARK: - Preference Key

/// A small preference that a child sets and a parent reads, demonstrating
/// bottom-up value propagation (the mirror image of `@Environment`, which
/// flows top-down). The last value set wins (the default `reduce`).
private struct DemoMessageKey: PreferenceKey {
    static let defaultValue: String = "(none yet)"

    static func reduce(value: inout String, nextValue: () -> String) {
        value = nextValue()
    }
}

// MARK: - Advanced Page

/// Advanced / behavioural features demo page.
///
/// Shows framework behaviour that isn't tied to a single visible control:
/// - `@AppStorage` — values persisted across launches
/// - `.onAppear` / `.onDisappear` / `.task` — view lifecycle hooks
/// - `.onKeyPress` — the raw key handler
/// - `.focusID` / `.focusSection` — explicit focus identity and grouping
/// - `.shiftStepMultiplier` — the Shift-accelerated step size
/// - `PreferenceKey` / `.preference` / `.onPreferenceChange` — bottom-up values
struct AdvancedPage: View {
    // @AppStorage persists to ~/.config/<app>/settings.json, so these values
    // survive quitting and relaunching the app.
    @AppStorage("advanced.launchTaps") private var launchTaps: Int = 0
    @AppStorage("advanced.remembered") private var remembered: Bool = false

    @State private var lifecycleLog: [String] = []
    @State private var lastKey: String = "—"
    @State private var stepValue: Int = 0
    @State private var childMessage: String = DemoMessageKey.defaultValue

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection("@AppStorage — persisted across launches") {
                VStack(alignment: .leading, spacing: 1) {
                    Text(
                        "These values are written to disk immediately. Bump the "
                            + "counter or flip the toggle, quit, relaunch — they "
                            + "come back exactly as you left them."
                    )
                    .foregroundStyle(.palette.foregroundSecondary)

                    Button("Tap to increment (persisted)") {
                        launchTaps += 1
                    }
                    Toggle("Remember me (persisted)", isOn: $remembered)

                    HStack(spacing: 2) {
                        ValueDisplayRow("Stored taps:", "\(launchTaps)")
                        ValueDisplayRow("Remembered:", remembered ? "yes" : "no")
                    }
                }
            }

            DemoSection("Lifecycle — .onAppear / .onDisappear / .task") {
                VStack(alignment: .leading, spacing: 1) {
                    Text(
                        ".onAppear logs a line when the page is shown; .task logs "
                            + "one shortly after from an async task. .onDisappear "
                            + "logs on the way out (you'll see it next time you open "
                            + "the page, since the log itself is reset on appear)."
                    )
                    .foregroundStyle(.palette.foregroundSecondary)

                    VStack(alignment: .leading, spacing: 0) {
                        if lifecycleLog.isEmpty {
                            Text("(waiting…)").dim()
                        } else {
                            ForEach(lifecycleLog, id: \.self) { line in
                                Text(line)
                            }
                        }
                    }
                    .border(color: .brightBlack)
                }
                .onAppear {
                    // Reset and seed the log each time the page appears so the
                    // demo reads clearly on every visit.
                    lifecycleLog = ["onAppear — page shown"]
                }
                .onDisappear {
                    appendLog("onDisappear — page hidden")
                }
                .task {
                    await runStartupTask()
                }
            }

            DemoSection("Key logger — .onKeyPress") {
                VStack(alignment: .leading, spacing: 1) {
                    Text(
                        "Press any key — the raw .onKeyPress handler reports the "
                            + "last one. It returns false (doesn't consume the "
                            + "event), so Esc still navigates back."
                    )
                    .foregroundStyle(.palette.foregroundSecondary)
                    ValueDisplayRow("Last key:", lastKey)
                }
            }

            DemoSection("Explicit focus — .focusID / .focusSection") {
                VStack(alignment: .leading, spacing: 1) {
                    Text(
                        "Two focus sections, each with two buttons that carry an "
                            + "explicit .focusID. Tab moves through them in order; "
                            + "the IDs are stable identities you can target."
                    )
                    .foregroundStyle(.palette.foregroundSecondary)

                    HStack(spacing: 3) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Section A").dim()
                            Button("A · One") {}.focusID("advanced-a-one")
                            Button("A · Two") {}.focusID("advanced-a-two")
                        }
                        .focusSection("advanced-section-a")

                        VStack(alignment: .leading, spacing: 0) {
                            Text("Section B").dim()
                            Button("B · One") {}.focusID("advanced-b-one")
                            Button("B · Two") {}.focusID("advanced-b-two")
                        }
                        .focusSection("advanced-section-b")
                    }
                }
            }

            DemoSection("Shift-accelerated stepping — .shiftStepMultiplier(10)") {
                VStack(alignment: .leading, spacing: 1) {
                    Text(
                        "Focus the stepper (Tab) and use ←/→ or the ± controls. A "
                            + "plain press steps by 1; holding Shift jumps by 10× "
                            + "(terminals that forward Shift+arrow)."
                    )
                    .foregroundStyle(.palette.foregroundSecondary)

                    Stepper("Value", value: $stepValue, in: 0...1000, step: 1)
                        .shiftStepMultiplier(10)
                    ValueDisplayRow("Value:", "\(stepValue)")
                }
            }

            DemoSection("Preferences — child sets, parent reads") {
                VStack(alignment: .leading, spacing: 1) {
                    Text(
                        "Preferences flow up the tree. The child below sets "
                            + "DemoMessageKey; this section reads it via "
                            + ".onPreferenceChange into @State."
                    )
                    .foregroundStyle(.palette.foregroundSecondary)

                    // The child sets a preference value; an ancestor observes it.
                    Text("Child view (sets the preference)")
                        .dim()
                        .preference(
                            key: DemoMessageKey.self,
                            value: "Hello from the child view"
                        )

                    ValueDisplayRow("Parent received:", childMessage)
                }
            }

            Spacer()
        }
        .onPreferenceChange(DemoMessageKey.self) { message in
            childMessage = message
        }
        .onKeyPress { event in
            lastKey = describeKey(event)
            // Don't consume — let Esc (back) and everything else through.
            return false
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader("Advanced")
        }
    }

    // MARK: - Helpers

    /// Appends a line to the lifecycle log, capping its length so the box
    /// stays a sensible size.
    private func appendLog(_ line: String) {
        lifecycleLog.append(line)
        if lifecycleLog.count > 6 {
            lifecycleLog.removeFirst(lifecycleLog.count - 6)
        }
    }

    /// The body of the `.task`: a short delay, then a log line — mirroring an
    /// async load that finishes after the first frame.
    private func runStartupTask() async {
        try? await Task.sleep(for: .milliseconds(200))
        appendLog("task — async work finished")
    }

    /// A readable description of a key event for the logger.
    private func describeKey(_ event: KeyEvent) -> String {
        var parts: [String] = []
        if event.ctrl { parts.append("Ctrl") }
        if event.alt { parts.append("Alt") }
        if event.shift { parts.append("Shift") }
        parts.append(keyName(event.key))
        return parts.joined(separator: "+")
    }

    // The complexity is the one-line-per-key switch itself; splitting it
    // into helpers would fragment the table without simplifying it. Block
    // form keeps the suppression adjacent to the function.
    // swiftlint:disable cyclomatic_complexity
    private func keyName(_ key: Key) -> String {
        switch key {
        case .escape: return "Esc"
        case .enter: return "Enter"
        case .tab: return "Tab"
        case .backspace: return "Backspace"
        case .delete: return "Delete"
        case .space: return "Space"
        case .up: return "Up"
        case .down: return "Down"
        case .left: return "Left"
        case .right: return "Right"
        case .home: return "Home"
        case .end: return "End"
        case .pageUp: return "PageUp"
        case .pageDown: return "PageDown"
        case .character(let ch): return "'\(ch)'"
        case .paste: return "(paste)"
        default: return "(other)"
        }
    }
    // swiftlint:enable cyclomatic_complexity
}
