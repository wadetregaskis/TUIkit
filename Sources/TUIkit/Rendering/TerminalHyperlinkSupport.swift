//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalHyperlinkSupport.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore

// MARK: - Which terminals honour OSC 8

extension TerminalClient {

    /// Whether `program` was measured to **honour** OSC 8 hyperlinks — hover
    /// shows the destination, ⌘-click opens it, right-click offers to copy it.
    ///
    /// ## This is a capability, not a quirk — and the difference decides the default
    ///
    /// Everything in ``TUIkitCore/TerminalQuirks`` is a measured *defect*, so
    /// the governing rule there is "absent evidence otherwise, a terminal
    /// renders correctly": applying a workaround to a host that does not need
    /// it breaks output that was fine. A capability inverts that. Emitting a
    /// sequence a host does not implement is not a workaround applied wrongly —
    /// it is a feature that does nothing — so the question is not "is this host
    /// known to be broken" but "is this host known to be able".
    ///
    /// Hence a default of `false` for ``Program/unidentified``, which is the
    /// opposite of what the quirks table does with the same input, for the same
    /// reason: an unmeasured terminal gets the answer that cannot hurt.
    ///
    /// ## Emitting it is safe everywhere measured, which is what makes this cheap
    ///
    /// A terminal with an OSC parser consumes the whole sequence whether or not
    /// it implements the command. One WITHOUT an OSC parser prints the payload:
    /// the URI sprayed across the row, the cursor left wherever that ended, and
    /// every later write on the row in the wrong column. `hyperlink_probe.py`
    /// measures exactly that difference — DSR after a known-width label wrapped
    /// in OSC 8, against the same label bare — and all four hosts swallow every
    /// spelling on both screen buffers, an OSC command number nothing
    /// implements included (2026-09-02; see
    /// `Documentation/Terminal-compatibility.md`).
    ///
    /// So the cost of being wrong here is a link that does nothing, not a
    /// corrupted row. That is why the table can be generous and why nothing
    /// upstream has to ask before rendering.
    ///
    /// ## The table
    ///
    /// | Host | Honours | Evidence |
    /// |---|---|---|
    /// | iTerm2 | yes | its own "Drawing: Underline OSC 8 hyperlinks" setting; tmux gives it the `hyperlinks` feature |
    /// | Ghostty | yes | per-page hyperlink storage in its cell model; `link-previews` has an `osc8` mode |
    /// | tmux | yes | stores links in its grid — `capture-pane -H` reads them back |
    /// | Apple Terminal | no | swallows the sequence and keeps nothing; no hyperlink support anywhere in the app |
    /// | Warp | no | see below |
    /// | unidentified | no | an unmeasured host gets the answer that cannot hurt |
    ///
    /// **Warp is a deliberate `false` rather than an unknown.** It swallows the
    /// sequence like the others, so emitting would be safe — but the only
    /// hyperlink handling its binary names is bounded by
    /// `"HighlightedLink is not within the alt screen"`, and the alternate
    /// screen is the only buffer a TUIkit app ever draws into. Claiming support
    /// TUIkit's own users could not reach is worse than claiming none: it is
    /// the difference between "this terminal does not do that" and "this
    /// framework is broken here". Flip it with ``hyperlinkSupport`` and say so.
    ///
    /// **tmux honours it and then decides who else may see it.** It forwards a
    /// link only to clients whose `terminal-features` include `hyperlinks`,
    /// which at 3.7c means iTerm2 alone of these four — Ghostty is identified
    /// by XTVERSION and still gets nothing. So a link inside tmux inside
    /// Ghostty is stored and never shown, until the user says
    /// `set -ga terminal-features "*:hyperlinks"`. That is tmux's decision to
    /// make and not one an application can override, which is why TUIkit emits
    /// regardless: the link costs nothing where it is dropped and works
    /// wherever the user has told tmux it can.
    public static func honoursHyperlinks(_ program: Program) -> Bool {
        switch program {
        case .iTerm2, .ghostty, .tmux: true
        case .appleTerminal, .warp, .unidentified: false
        }
    }

    /// Force the answer for the terminal in front of you, whatever was
    /// detected.
    ///
    /// The counterpart of ``simulatedQuirks`` for the capability half: TUIkit
    /// has models for five terminals and there are a great many more, most of
    /// which do support OSC 8. `true` turns links on for a host with no
    /// measurement; `false` turns them off — which an app may genuinely want
    /// even on a host that honours them, because a terminal-owned ⌘-click
    /// bypasses ``OpenURLAction``, so an app that intercepts its own URL scheme
    /// would find the system opener handling links it meant to keep.
    ///
    /// `nil` (the default) means "use the measured table", unless
    /// `TUIKIT_HYPERLINKS` is set in the environment — `1` for on, `0` for off
    /// — which is how a user turns links on for their own terminal without the
    /// application knowing anything about it.
    @MainActor public static var hyperlinkSupport: Bool? {
        didSet {
            guard hyperlinkSupport != oldValue else { return }
            applyHyperlinkSupport()
        }
    }

    /// Publishes ``hyperlinksSupported`` to
    /// ``TUIkitCore/TerminalHyperlink/isSupported``, which is what the render
    /// path actually reads.
    ///
    /// The twin of ``applyWidthTraits()``, and for the same reason: the
    /// question is answered here, where the host is identified and the process
    /// environment is readable, and the answer is read from a render path that
    /// is not main-actor isolated and could not ask. Called once at startup —
    /// before anything renders — and again from the diagnostic setters, whose
    /// whole point is changing it.
    @MainActor
    public static func applyHyperlinkSupport() {
        TerminalHyperlink.isSupported = hyperlinksSupported
    }

    /// Whether the terminal painting this app's output honours OSC 8 — the
    /// override, then the environment, then the measured table.
    ///
    /// Reads through ``effective``, so ``simulated`` changes this too: a
    /// diagnostic that renders as Apple Terminal gets Apple Terminal's answer,
    /// which is the point of the setting.
    @MainActor public static var hyperlinksSupported: Bool {
        if let hyperlinkSupport { return hyperlinkSupport }
        switch ProcessInfo.processInfo.environment["TUIKIT_HYPERLINKS"] {
        case "1": return true
        case "0": return false
        default: return honoursHyperlinks(effective.program)
        }
    }
}
