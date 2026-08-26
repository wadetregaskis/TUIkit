//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalWidthTraits.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Terminal Width Traits

/// How many cells the host terminal gives a composed emoji cluster — the
/// **claim**, as opposed to the cursor advance the per-host models describe.
///
/// ## Why the claim is not host-independent any more
///
/// It used to be, on the reasoning that a claim must cover the widest painter
/// so that content is never overwritten, with the narrower painters taking a
/// blank cell instead of a shear. That works when the spread is one cell — an
/// SF Symbol painted 2 by Apple Terminal and 1 by Ghostty — and it breaks down
/// completely when the spread is nine, which is what a four-person family
/// costs on a terminal that does not compose ZWJ sequences.
///
/// The alternative TUIkit used was **substitution**: strip the Fitzpatrick
/// modifier, or drop a sequence to its first component, so the cluster fits the
/// two cells claimed for it. That keeps every row aligned and changes what the
/// user said. 👍🏽 becomes 👍, which is a loss; 🏳️‍🌈 becomes 🏳️, which is a
/// white flag, and that is not a rendering compromise but a different message.
///
/// So the claim follows the host instead, and the layout accommodates whatever
/// the cluster really occupies. A ZWJ sequence that Warp draws across eleven
/// cells is *allocated* eleven cells: the enclosing border lands where it
/// should, text wraps around the true width, and every scalar the user wrote
/// still reaches the screen.
///
/// ## What this does not cover
///
/// Only the two classes where TUIkit was **substituting** — the ones that can
/// change a message. Classes that merely shear (Warp's keycaps and 〰️ at 3
/// cells against a claim of 2, its tag-sequence flags at 3) are unchanged and
/// still documented as limitations: they misalign, which is a visual defect,
/// not a semantic one. Each would need its own measured rule.
///
/// ## Reading and setting
///
/// Detected once at startup from the identified host and read from the render
/// path, exactly as ``TUIkitStyling/ColorDepth`` is. Use
/// ``withTraits(_:operation:)`` for a scoped pin — a test, or a diagnostic
/// rendering as another client — because a plain global mutate-and-restore
/// bleeds across Swift Testing's parallel runner.
public struct TerminalWidthTraits: Sendable, Equatable {

    /// How much room a Fitzpatrick cluster (👍🏽 ✊🏻 ☝🏽) occupies.
    public enum SkinTone: String, Sendable, Equatable, CaseIterable {
        /// The base and the modifier merge into one glyph occupying the base's
        /// own width. Ghostty, and every host for an SMP base under
        /// ``detachedOnBMPBases``.
        case merged
        /// The base is drawn, then the modifier as a separate colour swatch
        /// beside it, so the cluster owns the base's width **plus two**.
        /// Apple Terminal and Warp, for every base.
        case detached
        /// Merged for an SMP base (👍🏽), detached for a BMP one (✊🏻 ☝🏽).
        /// iTerm2 and tmux.
        case detachedOnBMPBases
    }

    /// The host draws each component of a ZWJ sequence separately rather than
    /// composing them, so 👩‍🚀 is a woman beside a rocket rather than an
    /// astronaut, and owns the sum of its parts.
    ///
    /// Measured on Warp: the width is the sum of the ZWJ-separated segments
    /// **plus one cell per joiner** — the joiner itself takes a column. That
    /// rule predicts every measured case exactly, including 👩🏽‍🚀 at 7
    /// (4 for the skin-toned segment, 2 for the rocket, 1 for the joiner),
    /// so it composes with ``skinTone`` rather than duplicating it.
    public var decomposesZWJSequences: Bool

    /// How this host lays out a skin-tone cluster.
    public var skinTone: SkinTone

    public init(decomposesZWJSequences: Bool = false, skinTone: SkinTone = .merged) {
        self.decomposesZWJSequences = decomposesZWJSequences
        self.skinTone = skinTone
    }

    /// A host that composes everything into the two cells the layout would
    /// naturally claim — the correct answer for a terminal TUIkit has not
    /// measured, and the behaviour every terminal got before this existed.
    public static let composing = Self()
}

// MARK: - The process-wide value

extension TerminalWidthTraits {

    /// The process-wide traits, before any task-local pin.
    ///
    /// `nonisolated(unsafe)` is intentional and matches
    /// ``TUIkitStyling/ColorDepth``: the value is set once at startup, from a
    /// host identification that cannot change for the life of the process, and
    /// is then read from the render path with no further writes.
    nonisolated(unsafe) private static var processCurrent: Self = .composing

    /// A task-scoped pin, bound by ``withTraits(_:operation:)``.
    ///
    /// Task-local rather than a plain global for the reason `ColorDepth` gives:
    /// Swift Testing runs suites in parallel, and a global mutate-and-restore
    /// would bleed one test's pinned host into another's rendering.
    @TaskLocal private static var taskCurrent: Self?

    /// Bumped every time the process-wide traits change.
    ///
    /// Measurements are memoized by content, and the claim is part of what a
    /// measurement means — so a cache populated under one host's traits is
    /// wrong under another's. Rather than reach for a shared cache the
    /// architecture deliberately does not have, the caches compare this counter
    /// once per render pass and drop themselves when it moves.
    ///
    /// Only the process value bumps it. A task-local pin is scoped to work that
    /// opts into it, and the render path is not that work.
    nonisolated(unsafe) public private(set) static var generation: Int = 0

    /// The traits in force. Assign to override process-wide — expected before
    /// rendering starts — or use ``withTraits(_:operation:)`` for a scoped pin.
    public static var current: Self {
        get { taskCurrent ?? processCurrent }
        set {
            guard newValue != processCurrent else { return }
            processCurrent = newValue
            generation &+= 1
        }
    }

    /// Runs `operation` with `traits` in force on this task only.
    public static func withTraits<R>(
        _ traits: Self, operation: () throws -> R
    ) rethrows -> R {
        try $taskCurrent.withValue(traits, operation: operation)
    }
}
