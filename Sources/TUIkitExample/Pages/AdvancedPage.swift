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
    static var defaultValue: String { L("page.advanced.noneYet") }

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

            DemoSection(L("page.advanced.appStorageSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.advanced.appStorageDescription"))
                    .foregroundStyle(.palette.foregroundSecondary)

                    Button(L("page.advanced.tapToIncrement")) {
                        launchTaps += 1
                    }
                    Toggle(L("page.advanced.rememberMe"), isOn: $remembered)

                    HStack(spacing: 2) {
                        ValueDisplayRow(L("page.advanced.storedTaps"), "\(launchTaps)")
                        ValueDisplayRow(L("page.advanced.remembered"), remembered ? L("page.advanced.yes") : L("page.advanced.no"))
                    }
                }
            }

            DemoSection(L("page.advanced.lifecycleSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.advanced.lifecycleDescription"))
                    .foregroundStyle(.palette.foregroundSecondary)

                    VStack(alignment: .leading, spacing: 0) {
                        if lifecycleLog.isEmpty {
                            Text(L("page.advanced.waiting")).dim()
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
                    lifecycleLog = [L("page.advanced.logOnAppear")]
                }
                .onDisappear {
                    appendLog(L("page.advanced.logOnDisappear"))
                }
                .task {
                    await runStartupTask()
                }
            }

            DemoSection(L("page.advanced.keyLoggerSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.advanced.keyLoggerDescription"))
                    .foregroundStyle(.palette.foregroundSecondary)
                    ValueDisplayRow(L("page.advanced.lastKey"), lastKey)
                }
            }

            DemoSection(L("page.advanced.explicitFocusSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.advanced.explicitFocusDescription"))
                    .foregroundStyle(.palette.foregroundSecondary)

                    HStack(spacing: 3) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(L("page.advanced.sectionA")).dim()
                            Button("A · One") {}.focusID("advanced-a-one")
                            Button("A · Two") {}.focusID("advanced-a-two")
                        }
                        .focusSection("advanced-section-a")

                        VStack(alignment: .leading, spacing: 0) {
                            Text(L("page.advanced.sectionB")).dim()
                            Button("B · One") {}.focusID("advanced-b-one")
                            Button("B · Two") {}.focusID("advanced-b-two")
                        }
                        .focusSection("advanced-section-b")
                    }
                }
            }

            DemoSection(L("page.advanced.shiftSteppingSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.advanced.shiftSteppingDescription"))
                    .foregroundStyle(.palette.foregroundSecondary)

                    Stepper(L("page.advanced.value"), value: $stepValue, in: 0...1000, step: 1)
                        .shiftStepMultiplier(10)
                    ValueDisplayRow(L("page.advanced.valueLabel"), "\(stepValue)")
                }
            }

            DemoSection(L("page.advanced.preferencesSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.advanced.preferencesDescription"))
                    .foregroundStyle(.palette.foregroundSecondary)

                    // The child sets a preference value; an ancestor observes it.
                    Text(L("page.advanced.childView"))
                        .dim()
                        .preference(
                            key: DemoMessageKey.self,
                            value: L("page.advanced.helloFromChild")
                        )

                    ValueDisplayRow(L("page.advanced.parentReceived"), childMessage)
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
            DemoAppHeader(L("page.advanced.title"))
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
        appendLog(L("page.advanced.logTaskFinished"))
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
