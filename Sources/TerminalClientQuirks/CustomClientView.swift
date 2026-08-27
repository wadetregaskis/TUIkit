//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CustomClientView.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkit

/// Build a workaround set for a terminal TUIkit has never measured, by trying
/// the switches and watching the strip at the bottom.
///
/// This is the screen for the case the rest of the app cannot serve: a terminal
/// that is not one of the five with a written-down model. Rather than guessing
/// at its behaviour or waiting for someone to run a probe script, flip a switch
/// and look — the alignment strip is rendered through whatever is selected, so
/// a switch that fixes a row is a defect that terminal has, and a switch that
/// breaks a row is one it does not.
///
/// The export at the bottom is the point of the exercise: it names the terminal,
/// records what it answered when asked, and lists the switches that turned out
/// to be needed — which is everything required to add it to TUIkit properly.
struct CustomClientView: View {
    let client: TerminalClient

    /// Whether the hand-built set is driving the renderer. Off by default: this
    /// screen should be inert until somebody deliberately starts experimenting.
    @State private var enabled = false
    @State private var quirks = TerminalQuirks()
    @State private var terminalName = ""
    @State private var savedTo: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            heading
            switches
            skinTones
            strip
            export
        }
    }

    // MARK: - Heading

    private var heading: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle("Apply these workarounds instead of the detected client's", isOn: activation)
            Text(
                enabled
                    ? "Live. Every row this app draws is going through the switches below."
                    : "Inert. Turn this on to try the switches against your terminal."
            )
            .foregroundStyle(enabled ? .palette.warning : .palette.foregroundTertiary)
        }
    }

    /// Turning the screen on and off has to reach the renderer, not just this
    /// view — hence a hand-made binding rather than `$enabled`.
    private var activation: Binding<Bool> {
        Binding(
            get: { enabled },
            set: { isOn in
                enabled = isOn
                TerminalClient.simulatedQuirks = isOn ? quirks : nil
            })
    }

    // MARK: - The switches

    private var switches: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Paints two cells, advances one").bold()
            Text("Turn one on if that class of glyph drags the rest of its row leftward.")
                .foregroundStyle(.palette.foregroundSecondary)
            toggle("VS-16 pictographs  🖥️ ❤️ ✏️", \.vs16Pictographs)
            toggle("Bare pictographs  🛡 🖥", \.barePictographs)
            toggle("VS-15 chrome glyphs  ⬛\u{FE0E} ⬜\u{FE0E}", \.vs15ChromeGlyphs)
            toggle("Lone regional indicators  🇦", \.loneRegionalIndicators)
            toggle("Flag pairs  🇺🇸", \.flagPairs)
            toggle("Keycap sequences  1\u{FE0F}\u{20E3}", \.keycapSequences)
            toggle("SF Symbols (Plane-16 PUA)", \.planeSixteenPUA)
            Text("Internal column runs past the composed glyph").bold()
            Text("Turn one on if rows carrying that class wrap early — blank default-background cells at the row's right edge.")
                .foregroundStyle(.palette.foregroundSecondary)
            toggle("ZWJ sequences  👩\u{200D}🚀 👨\u{200D}👩\u{200D}👧\u{200D}👦", \.zwjSequences)
            toggle("Tag-sequence flags  🏴\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}", \.tagFlags)
            Text("Next character paints inside the glyph").bold()
            Text("Turn this on if the character after a flag, keycap or ❤️\u{200D}🔥-style sequence overlaps its last cell.")
                .foregroundStyle(.palette.foregroundSecondary)
            toggle("Nudge paint-short composites  🇺🇸 1\u{FE0F}\u{20E3} ❤️\u{200D}🔥", \.paintShortComposites)
            Text("Background under a compensated glyph").bold()
            Text("Turn this on if compensated glyphs sit on the terminal's own background instead of the app's — a coloured row that reads as a comb.")
                .foregroundStyle(.palette.foregroundSecondary)
            toggle("Erase the cells before drawing the glyph", \.erasesUnderGlyphs)
        }
    }

    private func toggle(_ title: String, _ path: WritableKeyPath<TerminalQuirks, Bool>)
        -> some View
    {
        Toggle(
            title,
            isOn: Binding(
                get: { quirks[keyPath: path] },
                set: { newValue in
                    var updated = quirks
                    updated[keyPath: path] = newValue
                    apply(updated)
                }))
    }

    // MARK: - Skin tones

    /// Separate from the switches above because the treatments differ in kind,
    /// not just degree: strips change what the user wrote, the pull-back keeps
    /// it and squares the internal column with `CUB`.
    private var skinTones: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Skin-tone clusters  🤙🏽 ✊🏻").bold()
            Text("These over-advance the internal column; pick how this terminal needs them handled.")
                .foregroundStyle(.palette.foregroundSecondary)
            ForEach(TerminalQuirks.SkinTones.allCases, id: \.self) { option in
                Button {
                    var updated = quirks
                    updated.skinTones = option
                    apply(updated)
                } label: {
                    HStack(spacing: 1) {
                        Text(quirks.skinTones == option ? "●" : "○")
                            .foregroundStyle(
                                quirks.skinTones == option
                                    ? .palette.accent : .palette.foregroundTertiary)
                        Text(describe(option))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func describe(_ option: TerminalQuirks.SkinTones) -> String {
        switch option {
        case .keep: "Keep them — the terminal joins the cluster correctly (Ghostty)"
        case .stripAll: "Strip every one (a claim that cannot hold the detached pair)"
        case .stripBMPBases: "Strip only BMP-based ones — ✊🏻 but not 👍🏽 (tmux)"
        case .pullBack: "Keep them, pull the internal column back with CUB (Apple Terminal)"
        }
    }

    private func apply(_ updated: TerminalQuirks) {
        quirks = updated
        if enabled { TerminalClient.simulatedQuirks = updated }
    }

    // MARK: - The evidence

    /// The same check as the Alignment screen, inline, because a switch is only
    /// meaningful next to what it does. Both bars in every row should line up.
    private var strip: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Does it line up?").bold()
            Text("│" + String(repeating: "─", count: 2) + "│  (target)")
                .foregroundStyle(.palette.foregroundTertiary)
            ForEach(Clusters.all.filter(isContentious)) { cluster in
                Text(
                    "│\(cluster.text)"
                        + String(repeating: " ", count: max(0, 2 - cluster.character.terminalWidth))
                        + "│  \(cluster.name)")
            }
        }
    }

    private func isContentious(_ cluster: Cluster) -> Bool {
        TerminalClient.Program.allCases.contains { program in
            TerminalClient.cursorAdvance(of: cluster.character, on: program)
                != cluster.character.terminalWidth
        }
    }

    // MARK: - Export

    private var export: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Export").bold()
            HStack(spacing: 1) {
                Text("Terminal name and version:")
                TextField("e.g. Kitty 0.42.1", text: $terminalName).frame(width: 28)
            }
            Button("Write report to a file") { savedTo = writeReport() }
                .buttonStyle(.plain)
            if let savedTo {
                Text("Written to \(savedTo) — send that file, or paste the text below.")
                    .foregroundStyle(.palette.success)
            }
            // One Text per line: a single multi-line string is at the mercy of
            // whatever width the surrounding stack settles on, and a report
            // that re-wraps is a report somebody has to re-type.
            ForEach(reportLines, id: \.self) { line in
                Text(line).foregroundStyle(.palette.foregroundSecondary)
            }
        }
    }

    /// Everything needed to add this terminal to TUIkit: what it is, what it
    /// said when asked, and which workarounds turned out to be needed. The
    /// `TerminalQuirks(...)` line is valid Swift, so it can go straight into a
    /// test as the expected model.
    private var report: String { reportLines.joined(separator: "\n") }

    /// The report, line by line.
    private var reportLines: [String] {
        let identity = client
        var lines = [
            "# TUIkit terminal quirks report",
            "terminal:      \(terminalName.isEmpty ? "(unnamed — please fill in)" : terminalName)",
            "TERM:          \(ProcessInfo.processInfo.environment["TERM"] ?? "unset")",
            "TERM_PROGRAM:  \(ProcessInfo.processInfo.environment["TERM_PROGRAM"] ?? "unset")",
            "DA1:           \(identity.primaryDeviceAttributes.map(escaped) ?? "not asked / silent")",
            "DA2:           \(identity.secondaryDeviceAttributes.map(escaped) ?? "not asked / silent")",
            "XTVERSION:     \(identity.answeredVersionQuery ? "answered" : "silent")",
            "",
            "# Workarounds found to be needed, by experiment:",
        ]
        lines.append(swiftLiteral)
        return lines
    }

    /// The quirks as the Swift value that produced them.
    private var swiftLiteral: String {
        var parts: [String] = []
        if quirks.vs16Pictographs { parts.append("vs16Pictographs: true") }
        if quirks.barePictographs { parts.append("barePictographs: true") }
        if quirks.vs15ChromeGlyphs { parts.append("vs15ChromeGlyphs: true") }
        if quirks.loneRegionalIndicators { parts.append("loneRegionalIndicators: true") }
        if quirks.flagPairs { parts.append("flagPairs: true") }
        if quirks.keycapSequences { parts.append("keycapSequences: true") }
        if quirks.planeSixteenPUA { parts.append("planeSixteenPUA: true") }
        if quirks.skinTones != .keep { parts.append("skinTones: .\(quirks.skinTones.rawValue)") }
        if quirks.erasesUnderGlyphs { parts.append("erasesUnderGlyphs: true") }
        return parts.isEmpty
            ? "TerminalQuirks()  # nothing needed — this terminal renders correctly"
            : "TerminalQuirks(\(parts.joined(separator: ", ")))"
    }

    /// An escape sequence with ESC spelled out, so the report is readable and
    /// cannot re-execute when it is pasted somewhere.
    private func escaped(_ text: String) -> String {
        text.unicodeScalars.map { $0.value == 0x1B ? "ESC" : String(Character($0)) }.joined()
    }

    private func writeReport() -> String {
        let name = "tuikit-terminal-quirks.txt"
        let path = FileManager.default.currentDirectoryPath + "/" + name
        do {
            try report.write(toFile: path, atomically: true, encoding: .utf8)
            return path
        } catch {
            return "could not write \(path): \(error.localizedDescription)"
        }
    }
}
