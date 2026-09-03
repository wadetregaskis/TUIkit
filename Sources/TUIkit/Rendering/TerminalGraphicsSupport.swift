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
    /// for itself. That argument is right about Warp, which refuses a virtual
    /// placement by name and is excluded by its own answer. It does not reach
    /// iTerm2, and the reason is worth stating exactly, because it is what
    /// distinguishes this from giving up on a symptom:
    ///
    /// **iTerm2 accepts `a=p,U=1` and does not implement Unicode
    /// placeholders.** Measured 2026-09-03 with
    /// `Tools/TerminalProbes/pixel_format_probe.py`, five cases in both hosts:
    /// four virtual placements — `{f=24, f=32}` × `{single escape, chunked}` —
    /// are blank in iTerm2 and draw in Ghostty, while the SAME BYTES placed
    /// directly at the cursor draw in both. So the pixels, the transmission,
    /// the chunking and the pixel format are all fine; iTerm2 acknowledges the
    /// placement and never honours it.
    ///
    /// The handshake cannot catch that. It asks *"will you accept a virtual
    /// placement?"* and gets a truthful yes — iTerm2 really does track images
    /// by id, and a placement after a delete comes back `ENOENT`. The question
    /// TUIkit needs answered is *"will you DRAW it?"*, and nothing in the
    /// protocol asks it.
    ///
    /// There is no fallback within the protocol, which is why this ends in a
    /// table rather than in a different code path. TUIkit uses virtual
    /// placements and nothing else, on purpose: an image drawn at the cursor
    /// does not scroll with its row, is not clipped by the container that
    /// clips its cells, is not covered by a modal composited over it, and
    /// cannot be diffed. Drawing iTerm2's one working case would not be
    /// "graphics on iTerm2", it would be a picture that ignores the layout.
    ///
    /// Deliberately narrow: a host is here only once somebody has watched it
    /// say yes and draw nothing, and has established WHY. Everything else
    /// still earns pictures by answering the handshake, which is the property
    /// worth keeping, and ``graphicsSupport`` / `TUIKIT_GRAPHICS=1` override
    /// it — so an iTerm2 that implements placeholders needs no release here.
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
