//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ClientPickerView.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// Renders the whole app as though it were running under a different terminal.
///
/// Not a preview — the selection drives the real
/// ``TUIkit/TerminalClient/simulated``, so every row this app draws (including
/// this one, the tab strip and the status bar) is built through the selected
/// terminal's workarounds. That is the point: on a terminal whose quirks TUIkit
/// has measured, picking that terminal makes the Alignment screen line up, and
/// picking a different one visibly breaks it. What breaks, and how, is the
/// evidence.
struct ClientPickerView: View {
    @Binding var selection: TerminalClient.Program?
    let detected: TerminalClient.Program

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            explanation
            VStack(alignment: .leading, spacing: 0) {
                choice(nil, title: "Detected — \(describe(detected))")
                ForEach(
                    TerminalClient.Program.allCases.filter { $0 != .unidentified }, id: \.self
                ) { program in
                    choice(program, title: describe(program))
                }
                choice(.unidentified, title: "None — compensate nothing")
            }
            warning
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Render as").bold()
            Text("Applies immediately, to the whole app — this screen included.")
                .foregroundStyle(.palette.foregroundSecondary)
        }
    }

    private func choice(_ program: TerminalClient.Program?, title: String) -> some View {
        let isSelected = selection == program
        return Button {
            selection = program
            // The binding above is this view's own state; this is what makes it
            // take effect. Assigning both keeps the control in step with the
            // renderer even if the view is rebuilt.
            TerminalClient.simulated = program
        } label: {
            HStack(spacing: 1) {
                Text(isSelected ? "●" : "○")
                    .foregroundStyle(isSelected ? .palette.accent : .palette.foregroundTertiary)
                Text(title)
                if let program, program != .unidentified {
                    Text(summary(of: program)).foregroundStyle(.palette.foregroundTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// One line on what this terminal needs — the reason to pick it, and a
    /// reminder that the workarounds differ per host rather than being one
    /// "emoji fix".
    private func summary(of program: TerminalClient.Program) -> String {
        switch program {
        case .appleTerminal:
            "ECH+CUF for under-advancers; tones separate as swatches; ZWJ decomposed"
        case .iTerm2:
            "ECH+CUF for VS-16, keycaps, SF Symbols (alternate screen); tones detach on BMP bases"
        case .ghostty:
            "ECH+CUF for VS-15 chrome and SF Symbols; keeps skin tones"
        case .warp:
            "CUF for lone regional indicators; tones detach as swatches"
        case .tmux:
            "compositor: its own grid, its own model; strips BMP-base skin tones"
        case .unidentified:
            ""
        }
    }

    private var warning: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Why this is a diagnostic and not a setting").bold()
            Text(
                "Choosing the wrong terminal here applies workarounds for defects yours does not "
                    + "have, which breaks output that was correct. TUIkit ships with no override "
                    + "for that reason: absent explicit evidence, a terminal is assumed to render "
                    + "correctly."
            )
            .foregroundStyle(.palette.foregroundSecondary)
            Text("To make a choice permanent, set TUIKIT_TERM_PROGRAM in your shell instead.")
                .foregroundStyle(.palette.foregroundTertiary)
        }
        .padding(1)
        .border(.palette.border)
    }

    private func describe(_ program: TerminalClient.Program) -> String {
        switch program {
        case .appleTerminal: "Apple Terminal"
        case .iTerm2: "iTerm2"
        case .ghostty: "Ghostty"
        case .warp: "Warp"
        case .tmux: "tmux"
        case .unidentified: "unidentified"
        }
    }
}
