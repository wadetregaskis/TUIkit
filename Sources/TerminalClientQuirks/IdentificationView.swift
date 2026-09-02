//  🖥️ TUIkit — Terminal UI Kit for Swift
//  IdentificationView.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkit

/// How TUIkit decided which terminal is painting this app, and what each signal
/// had to say.
///
/// The reason this is worth a whole screen: the signals differ enormously in
/// reach, and the one that carries almost everything locally — `TERM_PROGRAM` —
/// carries nothing across ssh. A user whose emoji are misaligned over an ssh
/// session is looking at an *identification* failure, not a rendering one, and
/// nothing else in a terminal app will tell them that.
struct IdentificationView: View {
    let client: TerminalClient

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            verdict
            signals
            deviceAttributes
            HyperlinkCheckView(client: client)
            if client.program == .unidentified { advice }
        }
    }

    // MARK: - Verdict

    private var verdict: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                Text("Terminal:").foregroundStyle(.palette.foregroundSecondary)
                Text(describe(client.program)).bold()
                    .foregroundStyle(
                        client.program == .unidentified
                            ? .palette.warning : .palette.success)
            }
            HStack(spacing: 1) {
                Text("Named by:").foregroundStyle(.palette.foregroundSecondary)
                Text(describe(client.namedBy))
            }
            if let name = client.name, client.program == .unidentified {
                HStack(spacing: 1) {
                    Text("It calls itself:").foregroundStyle(.palette.foregroundSecondary)
                    Text(name)
                }
            }
            Text(
                client.program == .unidentified
                    ? "Nothing is being compensated. A terminal TUIkit cannot name is assumed to render correctly."
                    : "This terminal's measured quirks are being compensated for."
            )
            .foregroundStyle(.palette.foregroundSecondary)
        }
        .padding(1)
        .border(.palette.border)
    }

    // MARK: - Signals

    /// Every signal that can name a host, what it holds here, and how far it
    /// reaches — the "how far" column being the point.
    private var signals: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Signals").bold()
            ForEach(Self.environmentSignals, id: \.variable) { signal in
                let value = ProcessInfo.processInfo.environment[signal.variable]
                HStack(spacing: 1) {
                    Text(pad(signal.variable, 22))
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text(pad(value.map { $0.isEmpty ? "(empty)" : $0 } ?? "unset", 22))
                        .foregroundStyle(value == nil ? .palette.foregroundTertiary : .palette.foreground)
                    Text(signal.reach).foregroundStyle(.palette.foregroundTertiary)
                }
            }
            HStack(spacing: 1) {
                Text(pad("Device Attributes", 22)).foregroundStyle(.palette.foregroundSecondary)
                Text(pad(client.wasAsked ? "asked" : "not asked", 22))
                    .foregroundStyle(client.wasAsked ? .palette.foreground : .palette.foregroundTertiary)
                Text("survives any number of ssh hops").foregroundStyle(.palette.foregroundTertiary)
            }
        }
    }

    private struct EnvironmentSignal {
        let variable: String
        let reach: String
    }

    private static let environmentSignals = [
        EnvironmentSignal(variable: "TUIKIT_TERM_PROGRAM", reach: "explicit; always wins"),
        EnvironmentSignal(variable: "TERM_PROGRAM", reach: "local only — ssh drops it"),
        EnvironmentSignal(variable: "LC_TERMINAL", reach: "iTerm2 only; ssh forwards LC_*"),
        EnvironmentSignal(variable: "TMUX", reach: "a tmux pane"),
        EnvironmentSignal(variable: "SSH_TTY", reach: "(not an identity — context)"),
        EnvironmentSignal(variable: "TERM", reach: "names a few terminals; survives ssh"),
    ]

    // MARK: - Device Attributes

    private var deviceAttributes: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What the terminal answered").bold()
            if client.wasAsked {
                reply("DA1  (ESC[c)", client.primaryDeviceAttributes)
                reply("DA2  (ESC[>c)", client.secondaryDeviceAttributes)
                reply(
                    "XTVERSION (ESC[>0q)",
                    client.answeredVersionQuery ? "answered" : nil)
                Text(
                    "Apple Terminal is the one measured host that answers no XTVERSION, so its "
                        + "Device Attributes are what identify it remotely."
                )
                .foregroundStyle(.palette.foregroundTertiary)
            } else {
                Text("Not asked — the environment had already named the host, or this is a tmux pane.")
                    .foregroundStyle(.palette.foregroundTertiary)
            }
        }
    }

    private func reply(_ label: String, _ value: String?) -> some View {
        HStack(spacing: 1) {
            Text(pad(label, 22)).foregroundStyle(.palette.foregroundSecondary)
            Text(value.map(Self.printable) ?? "silent")
                .foregroundStyle(value == nil ? .palette.foregroundTertiary : .palette.foreground)
        }
    }

    // MARK: - Advice

    private var advice: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("If glyphs look misaligned").bold()
            Text("Name the terminal yourself and restart:")
                .foregroundStyle(.palette.foregroundSecondary)
            Text("    export TUIKIT_TERM_PROGRAM=Apple_Terminal")
            Text("Accepted: Apple_Terminal, iTerm.app, ghostty, WarpTerminal, tmux.")
                .foregroundStyle(.palette.foregroundTertiary)
            Text("If your terminal is not one of those, the Alignment tab shows what to report.")
                .foregroundStyle(.palette.foregroundTertiary)
        }
        .padding(1)
        .border(.palette.warning)
    }

    // MARK: - Formatting

    /// An escape sequence with its ESC spelled out, so it can be read (and
    /// copied into a bug report) rather than executed.
    private static func printable(_ text: String) -> String {
        text.unicodeScalars.map { scalar in
            switch scalar.value {
            case 0x1B: "ESC"
            case 0..<0x20: "^\(scalar.value)"
            default: String(Character(scalar))
            }
        }.joined()
    }

    /// Pads to a column width in CELLS, which for ASCII labels is characters —
    /// but `terminalWidth` is the honest unit and costs nothing to use.
    private func pad(_ text: String, _ width: Int) -> String {
        text + String(repeating: " ", count: max(0, width - text.strippedLength))
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

    private func describe(_ signal: TerminalClient.Signal) -> String {
        switch signal {
        case .explicitOverride: "TUIKIT_TERM_PROGRAM (explicit override)"
        case .termProgram: "TERM_PROGRAM (set locally by the terminal)"
        case .forwardedLocale: "LC_TERMINAL (forwarded across ssh)"
        case .termType: "TERM (the termtype, which ssh carries in its pty-req)"
        case .deviceAttributes: "its answer to a Device Attributes query"
        case .tmuxSession: "$TMUX — a tmux pane composites our output"
        case .none: "nothing"
        }
    }
}
