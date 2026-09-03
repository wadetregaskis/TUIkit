//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalGraphicsSupport.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore

// MARK: - Whether this terminal draws pictures

extension TerminalClient {

    /// What the startup handshake was told, or `nil` if it never ran — no
    /// terminal, an answer already forced, or a host measured to print APC.
    ///
    /// The counterpart of `TerminalHost.startupIdentity` for graphics, and
    /// deliberately not a host table. See `TerminalGraphicsQuery`.
    ///
    /// Public because "never asked" and "asked, and told no" are different
    /// facts about a terminal and a diagnostic has to be able to tell them
    /// apart — ``graphicsSupported`` collapses both to `false`, which is right
    /// for rendering and useless for reporting. Read-only: the way to change
    /// the answer is ``graphicsSupport``.
    @MainActor public private(set) static var detectedGraphics: Bool?

    /// Force the answer for the terminal in front of you, whatever was
    /// detected.
    ///
    /// `true` is for a terminal that supports placements but could not be
    /// asked — the handshake is skipped inside a host known to print APC, and
    /// under a multiplexer that swallows it. `false` turns pictures off for a
    /// terminal that has them, which an app may genuinely want: the glyph
    /// renderer is a look, not only a fallback, and an app built around
    /// `.braille` or a custom ramp does not want a photograph appearing on
    /// Ghostty and nowhere else.
    ///
    /// `nil` (the default) means "use the handshake", unless `TUIKIT_GRAPHICS`
    /// is set — `1` for on, `0` for off — which is how a user answers for
    /// their own terminal without the application knowing anything about it,
    /// and how the round trip is skipped entirely.
    @MainActor public static var graphicsSupport: Bool? {
        didSet {
            guard graphicsSupport != oldValue else { return }
            applyGraphicsSupport()
        }
    }

    /// Publishes ``graphicsSupported`` to
    /// ``KittyGraphics/isSupported``, which is what the render path
    /// actually reads.
    ///
    /// The twin of ``applyHyperlinkSupport()``, for the same reason: the
    /// question is answered here, on the main actor, where the terminal can be
    /// asked; the answer is read from a render path that cannot ask anything.
    @MainActor
    public static func applyGraphicsSupport() {
        KittyGraphics.isSupported = graphicsSupported
    }

    /// Whether the terminal painting this app's output will place an image in
    /// its cell grid — the override, then the environment, then the handshake.
    ///
    /// Unlike ``hyperlinksSupported`` this does **not** read through
    /// ``effective``, so ``simulated`` does not change it. Simulating Apple
    /// Terminal is a statement about which compensations to emit; it is not a
    /// claim that the terminal actually in front of the user has stopped being
    /// able to draw. The override is how a diagnostic turns pictures off.
    @MainActor public static var graphicsSupported: Bool {
        if let graphicsSupport { return graphicsSupport }
        switch ProcessInfo.processInfo.environment["TUIKIT_GRAPHICS"] {
        case "1": return true
        case "0": return false
        default: return (detectedGraphics ?? false) && !drawsNothingDespiteSayingOK(current.program)
        }
    }

    /// Hosts measured to answer the handshake `OK` and then draw **nothing**.
    ///
    /// This is a host table, and `8c22e630` argued against having one here on
    /// the grounds that the Kitty protocol is the one capability that answers
    /// for itself. That argument was right about Warp and wrong in general,
    /// and iTerm2 is why: the handshake asks *"will you accept a virtual
    /// placement?"*, iTerm2 answers `OK` and **means it** — delete the image
    /// and a later placement comes back
    /// `ENOENT: Put command refers to non-existent image with id: 31`, so it
    /// really is tracking images and really is processing the command — and
    /// then it never composites one. The question TUIkit actually needs
    /// answered is *"will you DRAW it?"*, and no query in the protocol asks
    /// that.
    ///
    /// Measured 2026-09-03 with `Tools/TerminalProbes/placement_probe.py`,
    /// iTerm2 3.6.11: `Kitty answered True`, `virtual placement True`, every
    /// transmit and placement `OK`, and no picture. The placeholder cells come
    /// back **blank** — not the image, and not the U+10EEEE glyphs either,
    /// which Apple Terminal and Warp both print. So iTerm2 consumes the
    /// placeholder codepoint and stops there; the cells are spent and nothing
    /// is drawn in them, which is worse for a user than a refusal because the
    /// glyph fallback is never reached.
    ///
    /// Deliberately narrow: a host is in this list only when somebody has
    /// watched it say yes and draw nothing. Everything else still gets
    /// pictures by answering the handshake, which is the property worth
    /// keeping. ``graphicsSupport`` and `TUIKIT_GRAPHICS=1` both override it,
    /// so a future iTerm2 that implements placements needs no release here.
    ///
    /// Read from ``current`` rather than ``effective``: this is a fact about
    /// the terminal actually painting the screen, and simulating a host is a
    /// statement about which compensations to emit rather than a claim about
    /// what can be drawn.
    static func drawsNothingDespiteSayingOK(_ program: Program) -> Bool {
        program == .iTerm2
    }

    /// Runs the startup handshake, if its answer is not already known, and
    /// publishes the result.
    ///
    /// Skips the round trip whenever something has already decided — an
    /// override, or `TUIKIT_GRAPHICS` — because the exchange costs a terminal
    /// round trip at startup and there is no reason to pay it for an answer
    /// nobody will read.
    ///
    /// - Parameter terminal: the terminal to ask. It owns stdin and the raw
    ///   mode the reply depends on.
    @MainActor
    static func detectGraphics(using terminal: Terminal) {
        defer { applyGraphicsSupport() }
        guard graphicsSupport == nil else { return }
        let forced = ProcessInfo.processInfo.environment["TUIKIT_GRAPHICS"]
        guard forced != "1", forced != "0" else { return }
        detectedGraphics = terminal.queryGraphicsSupport()
    }
}
