//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalClient.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore

/// Which terminal is painting this app's output, how that was determined, and
/// what has to be done differently because of it.
///
/// Terminals disagree about how far the cursor moves over a grapheme cluster.
/// The disagreements are measured and catalogued in
/// `Documentation/Terminal-compatibility.md`, and TUIkit compensates for them
/// automatically — this type is the public view of that machinery, for apps
/// that want to show the user what was decided, or to compensate a string they
/// are writing to the terminal themselves.
///
/// ## The governing rule
///
/// **Absent explicit evidence otherwise, a terminal is assumed to render
/// correctly.** Every compensation here works around a measured *defect*, so
/// applying one to a terminal that has no such defect would break output that
/// was fine. An unidentified client therefore gets ``Program/unidentified`` and
/// nothing is done to its output — which is a deliberate answer, not a
/// failure.
///
/// ```swift
/// let client = TerminalClient.current
/// if client.program == .unidentified {
///     print("Set TUIKIT_TERM_PROGRAM if emoji look misaligned.")
/// }
/// ```
public struct TerminalClient: Sendable, Equatable {

    /// A terminal TUIkit has measured and can compensate for.
    public enum Program: String, Sendable, Equatable, CaseIterable {
        /// macOS Terminal.app.
        case appleTerminal
        /// iTerm2.
        case iTerm2
        /// Ghostty.
        case ghostty
        /// Warp.
        case warp
        /// A tmux pane. tmux is a compositor, not a passthrough — it parses our
        /// output into its own grid with its own width tables — so it, and not
        /// the terminal attached to it, is the host whose model applies.
        case tmux
        /// Nothing identified the terminal, so it is assumed to render
        /// correctly and its output is left alone.
        case unidentified

        /// The `TERM_PROGRAM`-style name this program is spelled with, or `nil`
        /// for ``unidentified``.
        public var termProgramName: String? {
            switch self {
            case .appleTerminal: "Apple_Terminal"
            case .iTerm2: "iTerm.app"
            case .ghostty: "ghostty"
            case .warp: "WarpTerminal"
            case .tmux: "tmux"
            case .unidentified: nil
            }
        }
    }

    /// What named the terminal — the diagnostic half of this type, because the
    /// signals differ sharply in how far they reach.
    public enum Signal: String, Sendable, Equatable {
        /// `TUIKIT_TERM_PROGRAM`, set by the user. The only signal that can
        /// name a host none of the others reach.
        case explicitOverride
        /// `TERM_PROGRAM`, set by the terminal. Authoritative, but **does not
        /// survive an ssh hop**: it is not an `LC_*` variable, and OpenSSH
        /// forwards only `LANG` and `LC_*`.
        case termProgram
        /// `LC_TERMINAL`, set by iTerm2's shell integration. Does survive an
        /// ssh hop, because `LC_*` is forwarded.
        case forwardedLocale
        /// `TERM` named the terminal. Survives ssh — the termtype travels in
        /// the `pty-req` (RFC 4254 §6.2) — but only a few terminals set a
        /// value that names exactly one of them; most report a generic
        /// `xterm-256color` that names nothing.
        case termType
        /// The terminal answered a Device Attributes query saying so. Survives
        /// any number of hops — the question goes to the terminal itself.
        case deviceAttributes
        /// `$TMUX`, or tmux naming itself in `TERM_PROGRAM`.
        case tmuxSession
        /// Nothing named it.
        case none
    }

    /// The terminal painting this app's output — or the one being simulated,
    /// when read through ``effective``.
    public internal(set) var program: Program

    /// What named it.
    public let namedBy: Signal

    /// The raw `TERM_PROGRAM`-style name found, whether or not it is one TUIkit
    /// recognises. A name here with ``program`` still ``Program/unidentified``
    /// means the terminal said who it was and TUIkit has no measurements for
    /// it — the one case where a diagnostic is genuinely worth showing a user.
    public let name: String?

    /// The terminal's Primary Device Attributes reply (`ESC[?…c`), if it was
    /// asked and answered. Only asked when nothing in the environment named the
    /// host.
    public let primaryDeviceAttributes: String?

    /// The terminal's Secondary Device Attributes reply (`ESC[>…c`), if asked
    /// and answered.
    public let secondaryDeviceAttributes: String?

    /// Whether the terminal answered XTVERSION when asked. Apple Terminal
    /// answers none, which is one of the three clauses that identifies it.
    public let answeredVersionQuery: Bool

    /// Whether the terminal was asked at all. `false` when the environment had
    /// already named it, when running under tmux, or when there is no terminal.
    public let wasAsked: Bool

    /// The terminal hosting this process.
    @MainActor
    public static var current: Self {
        let environment = ProcessInfo.processInfo.environment
        let identity = TerminalHost.startupIdentity
        let program: Program =
            if TerminalHost.isTmux { .tmux } else if TerminalHost.isAppleTerminal {
                .appleTerminal
            } else if TerminalHost.isITerm2 {
                .iTerm2
            } else if TerminalHost.isGhostty {
                .ghostty
            } else if TerminalHost.isWarp { .warp } else { .unidentified }

        // Order matters, and differs from the resolver's: the Device Attributes
        // answer is SEEDED into `TUIKIT_TERM_PROGRAM`, so asking the
        // environment first would report every discovered host as a user
        // override and hide the mechanism this type exists to explain.
        let named = identity.flatMap(TerminalHost.nameFromDeviceAttributes) != nil
        let signal: Signal =
            if TerminalHost.isTmux {
                .tmuxSession
            } else if named {
                .deviceAttributes
            } else if environment["TUIKIT_TERM_PROGRAM"]?.isEmpty == false {
                .explicitOverride
            } else if environment["TERM_PROGRAM"]?.isEmpty == false {
                .termProgram
            } else if let forwarded = environment["LC_TERMINAL"], !forwarded.isEmpty,
                TerminalHost.hostProgram(environment: ["LC_TERMINAL": forwarded]) != nil
            {
                // Recognised only: an LC_TERMINAL naming a terminal with no
                // model here did not name THIS host, and the resolver falls
                // through past it to TERM, so this must too.
                .forwardedLocale
            } else if program != .unidentified, environment["TERM"]?.isEmpty == false {
                .termType
            } else {
                .none
            }

        return Self(
            program: program,
            namedBy: signal,
            name: program.termProgramName ?? environment["TERM_PROGRAM"]
                ?? environment["TUIKIT_TERM_PROGRAM"],
            primaryDeviceAttributes: identity?.primaryAttributes,
            secondaryDeviceAttributes: identity?.secondaryAttributes,
            answeredVersionQuery: identity?.answeredVersion ?? false,
            wasAsked: identity?.sawFence ?? false)
    }

    // MARK: - Rendering as another client

    /// Render as though the host were this program, whatever was detected.
    ///
    /// For diagnostics and demonstration — `TerminalClientQuirks` is built
    /// around it — not for production use: setting it makes TUIkit compensate
    /// for defects the terminal in front of you may not have, which is exactly
    /// what the detection exists to avoid. `nil` (the default) means "use what
    /// was detected", and is the only setting an app should ship with.
    ///
    /// It applies process-wide and takes effect on the next frame:
    /// `FrameDiffWriter` notices the change and repaints in full, because a row
    /// whose bytes happen not to change would otherwise keep the compensation
    /// of the model it was built under.
    ///
    /// ```swift
    /// TerminalClient.simulated = .appleTerminal   // see Apple Terminal's workarounds
    /// TerminalClient.simulated = nil              // back to what was detected
    /// ```
    @MainActor public static var simulated: Program? {
        didSet {
            // The claim follows the host, so simulating a different one changes
            // how wide clusters measure — and every memoized measurement taken
            // under the old claim is now wrong. Republishing the traits and
            // dropping those memos is what makes the picker honest rather than
            // half-applied.
            guard simulated != oldValue else { return }
            applyWidthTraits()
            // Hyperlinks follow the host too — simulating a terminal that does
            // not honour them has to stop them being emitted, or the picker is
            // half-applied in the other direction.
            applyHyperlinkSupport()
        }
    }

    /// Render with this hand-built set of workarounds, whatever was detected.
    ///
    /// Outranks ``simulated``, and exists for the case that type cannot serve:
    /// a terminal TUIkit has no model for. Toggling the switches in
    /// ``TUIkitCore/TerminalQuirks`` and watching the screen is how a new
    /// terminal's model gets discovered in the first place — see the Custom
    /// screen of the `TerminalClientQuirks` app, which does exactly that and
    /// exports the result.
    ///
    /// Like ``simulated``, this is a diagnostic. `nil` is the only value a
    /// shipping app should have.
    @MainActor public static var simulatedQuirks: TerminalQuirks? {
        didSet {
            // Two of the switches change what a cluster CLAIMS, not just how
            // it is emitted (software ZWJ decomposition, skin-tone
            // separation), so the traits must follow the switches exactly as
            // they follow a simulated program.
            guard simulatedQuirks != oldValue else { return }
            applyWidthTraits()
        }
    }

    /// The program whose model is actually being applied: ``simulated`` when
    /// one is set, and the detected client otherwise.
    @MainActor public static var effective: Self {
        guard let simulated else { return current }
        var client = current
        client.program = simulated
        return client
    }

    // MARK: - Width traits

    /// How wide this program draws the clusters TUIkit used to substitute away.
    ///
    /// The claim follows the host so that the layout can allocate what a
    /// cluster really occupies, instead of the cluster being cut down to fit a
    /// claim — see ``TUIkitCore/TerminalWidthTraits`` for why that trade was
    /// worth reversing.
    ///
    /// Measured on the alternate screen, 2026-08-26. Every entry is a
    /// self-consistent host behaviour, meaning paint equals advance, so a
    /// matching claim needs no compensation at all: the CUF machinery simply
    /// stops firing for these classes.
    public static func widthTraits(of program: Program) -> TerminalWidthTraits {
        switch program {
        case .appleTerminal:
            // The claims for the two classes whose emission the walk REWRITES,
            // because for them the claim must match the rewritten form, not
            // the composed cluster:
            //
            // - Skin tones are emitted as base + ZWNJ + modifier (the ZWNJ
            //   occupying its own column), so 🤙🏽 claims 5. A
            //   text-presentation base (☝🏻 ⛹🏾) is promoted with VS-16 first
            //   and claims 5 too — the bare rewrite measured misaligned, and
            //   the pull-back it shipped with re-rendered the cluster as the
            //   bare narrow glyph with a blank cell beside it (2026-08-28).
            // - Emoji ZWJ sequences are emitted as their segments with the
            //   joiners removed, so 👨‍👩‍👧‍👦 claims 8 and ❤️‍🔥 claims 4.
            //
            // Both reverse the earlier "not widened" decision, which kept the
            // composed cluster and repaired the cursor with CUB: measured on
            // the treatment cards (2026-08-27), every cursor-move repair
            // either re-rendered the cluster stripped (CUB, DCH), displaced
            // later absolute positioning on the row by the cluster's
            // stored-width surplus, or wrapped a full-width row. The rewrites
            // are the treatments with nothing measurably wrong — at the cost
            // of component glyphs instead of composed ones, and one blank
            // column inside a separated skin tone.
            TerminalWidthTraits(
                zwjSequences: .decomposedDroppingJoiners,
                skinTone: .separated)
        case .iTerm2:
            TerminalWidthTraits(zwjSequences: .composed, skinTone: .detachedOnBMPBases)
        case .ghostty:
            // The one host that composes everything.
            .composing
        case .warp:
            // Dropping rather than keeping the joiners (changed 2026-08-28):
            // Warp never composes a ZWJ sequence — it draws the components
            // with each kept joiner occupying a blank column between them —
            // so removing the joiners removes the gaps and nothing else.
            // Card-measured: every dropped form renders the same components
            // adjacent, nets exactly the segment sum (👨‍👩‍👧‍👦 8, 👩🏽‍🚀 6,
            // ❤️‍🔥 4, 🏳️‍🌈 4), and lands sequential AND absolute followers
            // true. The user judged the dropped forms strictly superior.
            TerminalWidthTraits(zwjSequences: .decomposedDroppingJoiners, skinTone: .detached)
        case .tmux:
            // NOT widened, deliberately. Measured 2026-08-26, tmux 3.7b does
            // not split by base plane the way iTerm2 does: 👍🏽 🙏🏽 👋🏽 merge
            // to 2 while 🤙🏽 🤚🏽 — also SMP — detach to 4, and ☝🏽 is 4 where
            // a base-plus-two rule predicts 3. The whole modifier-base set
            // was then swept on 2026-08-28 (`Character.tmuxMergedToneBases`:
            // 70 of 134 merge, 64 detach — per codepoint, with no clean rule;
            // the "where tmux's Unicode data has a modifier base" hypothesis
            // recorded here at the time was ALSO wrong, since Unicode-6.0
            // Santa detaches while the Unicode-10.0 🧍…🧝 run merges). The
            // strip now follows that measured set (`.keepingTmuxMerged` when
            // every attached client renders kept tones), and this enum stays
            // narrow: a widened claim would have to be wrong in one direction
            // or the other for half the set, and stripping aligns rows.
            .composing
        case .unidentified:
            // A terminal with no measurements is assumed to compose, for the
            // same reason it is assumed to render correctly.
            .composing
        }
    }

    /// Publishes the effective width traits process-wide: the hand-built
    /// quirk set's implied claims when one is being explored, the identified
    /// (or simulated) host's otherwise.
    ///
    /// Called once at startup, before the render loop is built, because
    /// `FrameDiffWriter` and every layout pass read the claim — and again by
    /// the diagnostic setters, whose whole point is changing it.
    @MainActor
    public static func applyWidthTraits() {
        TerminalWidthTraits.current =
            simulatedQuirks?.widthTraits ?? widthTraits(of: effective.program)
    }

    // MARK: - The models

    /// How many cells `cluster` actually moves the cursor on `program`, which
    /// is not always the ``TUIkitCore/Swift/Character/terminalWidth`` it is
    /// laid out as.
    ///
    /// The gap between the two is the whole subject of
    /// `Documentation/Terminal-compatibility.md`: a glyph painted two cells
    /// wide that advances the cursor one drags everything after it on the row a
    /// cell to the left.
    ///
    /// ``Program/unidentified`` answers ``TUIkitCore/Swift/Character/terminalWidth``,
    /// because a terminal we have no measurements for is assumed to advance the
    /// way it paints.
    public static func cursorAdvance(of cluster: Character, on program: Program) -> Int {
        switch program {
        case .appleTerminal: cluster.terminalAppCursorAdvance
        case .iTerm2: cluster.iTerm2CursorAdvance
        case .ghostty: cluster.ghosttyCursorAdvance
        case .warp: cluster.warpCursorAdvance
        case .tmux: cluster.tmuxCursorAdvance
        case .unidentified: cluster.terminalWidth
        }
    }

    /// Strips Fitzpatrick modifiers only when the layout's claim cannot hold
    /// them.
    ///
    /// The strip exists because a detached modifier over-advances past a 2-cell
    /// claim and drags the rest of the row left. Once
    /// ``TUIkitCore/TerminalWidthTraits`` gives the cluster the cells it really
    /// occupies, there is nothing to over-advance past and the modifier can
    /// stay — which matters, because stripping it is not a rendering compromise
    /// but a change to what the user wrote.
    ///
    /// So the question is about the CLAIM in force, not about the program: a
    /// caller who reaches ``compensating(_:for:tmuxSkinTones:)``
    /// without startup having published the host's traits still gets the old,
    /// safe behaviour.
    private static func strippingSkinTonesIfUnclaimed(
        _ text: String, scope: String.SkinToneFallbackScope = .all
    ) -> String {
        TerminalWidthTraits.current.skinTone == .merged
            ? text.withSkinToneFallback(scope: scope) : text
    }

    /// `text` with `program`'s cursor-advance divergences compensated for.
    ///
    /// The single place the per-host model is chosen — `FrameDiffWriter` builds
    /// every row through this, and the public entry point is the same function
    /// rather than a copy of it, because two copies of this table would drift
    /// and the symptom of the drift is a row that looks right until something
    /// on it changes.
    ///
    /// - Parameters:
    ///   - text: a whole row, or a fragment of one.
    ///   - program: the terminal that will paint it.
    ///   - tmuxSkinTones: which skin-tone bases to strip under tmux. tmux
    ///     merges 70 of the 134 modifier bases into exactly the two cells we
    ///     claim and detaches the rest (a per-codepoint fact — see
    ///     ``TUIkitCore/Swift/Character/tmuxMergedToneBases``), so whether the
    ///     merged ones can be KEPT depends on which clients are attached.
    public static func compensating(
        _ text: String,
        for program: Program,
        tmuxSkinTones: String.SkinToneFallbackScope = .all
    ) -> String {
        switch program {
        case .tmux:
            // FIRST, because tmux is a compositor: ITS grid is what our output
            // lands in, so the outer terminal's quirks apply to tmux's output,
            // not ours.
            return strippingSkinTonesIfUnclaimed(text, scope: tmuxSkinTones)
                .withTmuxCursorCompensation()
        case .appleTerminal:
            return text.withTerminalAppCursorCompensation()
        case .iTerm2:
            return strippingSkinTonesIfUnclaimed(text).withITerm2CursorCompensation()
        case .ghostty:
            // Ghostty needs no skin-tone strip — it is the only measured
            // terminal that merges Fitzpatrick clusters into the two cells the
            // layout claims — but under-advances its VS-15 chrome glyphs and SF
            // Symbols.
            return text.withGhosttyCursorCompensation()
        case .warp:
            // Warp draws skin tones as base + swatch exactly like iTerm2, then
            // needs a CUF for its lone-regional-indicator under-advance.
            return strippingSkinTonesIfUnclaimed(text).withWarpCursorCompensation()
        case .unidentified:
            return text
        }
    }
}
