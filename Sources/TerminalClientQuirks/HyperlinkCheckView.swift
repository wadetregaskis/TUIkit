//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HyperlinkCheckView.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkit

/// Whether this terminal honours OSC 8 hyperlinks — the answer TUIkit is
/// using, how it reached it, and the two links that let you check it.
///
/// It is here rather than on the Quirks screen because it is not a quirk. A
/// quirk is a measured DEFECT and the safe default is "this terminal is fine";
/// a capability is something a terminal can do and the safe default is "assume
/// not". The two tables would look alike and default opposite ways, which is
/// exactly the confusion worth keeping apart on screen.
///
/// **The check needs your eyes, and that is not a shortcoming of this screen.**
/// No escape sequence asks a terminal whether it implements OSC 8: DA1, DA2 and
/// XTVERSION say nothing about it, and no reply distinguishes a host that
/// stored the URI from one that discarded it. The affordance is the terminal's
/// own chrome — a hover preview, a right-click menu — which is exactly why it
/// is worth having and exactly why the application cannot observe it.
struct HyperlinkCheckView: View {
    let client: TerminalClient

    private let destination = URL(string: "https://swift.org")!

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Terminal hyperlinks (OSC 8)").bold()
            verdict
            comparison
            note
        }
        .padding(1)
        .border(.palette.border)
    }

    // MARK: - What TUIkit decided

    private var verdict: some View {
        let honoured = TerminalClient.hyperlinksSupported
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                Text("Emitting links:").foregroundStyle(.palette.foregroundSecondary)
                Text(honoured ? "yes" : "no").bold()
                    .foregroundStyle(honoured ? .palette.success : .palette.foregroundTertiary)
                Text("— \(reason)").foregroundStyle(.palette.foregroundTertiary)
            }
        }
    }

    /// Which of the three sources gave the answer, in the order they are
    /// consulted. Worth naming: an override that somebody set months ago in a
    /// shell profile is otherwise indistinguishable from a measurement.
    private var reason: String {
        if TerminalClient.hyperlinkSupport != nil { return "set in code this session" }
        switch ProcessInfo.processInfo.environment["TUIKIT_HYPERLINKS"] {
        case "1": return "TUIKIT_HYPERLINKS=1"
        case "0": return "TUIKIT_HYPERLINKS=0"
        default:
            return TerminalClient.honoursHyperlinks(client.program)
                ? "measured: this host honours them"
                : "not measured to honour them on this host"
        }
    }

    // MARK: - The check

    /// Two links that look identical and are not. Hovering tells them apart on
    /// a host that honours the escape, and nothing tells them apart on one that
    /// does not — which is itself the answer.
    private var comparison: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                Link("with the escape", destination: destination)
                Link("without it", destination: destination)
                    .terminalHyperlinks(false)
            }
            Text(
                "Hover each. On a host that honours OSC 8 the first shows "
                    + "https://swift.org and the second does not. Whether a modified click "
                    + "OPENS it is a separate question: this app holds mouse reporting, and "
                    + "iTerm2 is measured to forward ⌘-click here rather than act on it, so "
                    + "shift-click is the gesture to try. Report what works."
            )
            .foregroundStyle(.palette.foregroundTertiary)
        }
    }

    // MARK: - Why being wrong here is cheap

    private var note: some View {
        Text(
            "Emitting the sequence is safe on every terminal measured: one with an OSC parser "
                + "swallows it whether or not it implements the command. So the cost of this "
                + "being wrong is a link that does nothing, not a corrupted row — which is why "
                + "TUIKIT_HYPERLINKS=1 is a reasonable thing to try on a terminal TUIkit has "
                + "never measured. Report what you find."
        )
        .foregroundStyle(.palette.foregroundSecondary)
    }
}
