//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalColorRefresher.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// What the terminal says about its colours after the startup exchange has
/// closed, published to `TerminalColors.current` and repainted.
///
/// The exchange (`TerminalClient.detectColors(using:)`) asks once, before the
/// first frame, and stops listening at its fence or half a second, whichever
/// comes first. Two kinds of answer arrive after that:
/// - one that missed the deadline. Under tmux that is the normal case for the
///   sixteen slots: a silent client holds the fence about half a second
///   (measured, tmux 3.7c), which is why the startup request does not ask for
///   them there at all;
/// - one nobody asked for, when the terminal's own theme changes.
///
/// Both land on stdin exactly as a keystroke does. The input parser tells them
/// apart and keeps them (`Terminal.noteVolunteeredColorReply`); `AppRunner`
/// hands what it kept to ``noteReplies(_:)`` once per drain, so a burst of
/// eighteen replies is one publication and one repaint rather than eighteen.
///
/// **What a late answer means.** It says what it says, and nothing about what it
/// does not mention: a table of sixteen slots is no statement about the default
/// pair reported before it. So this keeps everything heard since the app
/// started and resolves that over what the exchange published, through
/// `TerminalColorQuery.refreshed(_:over:environment:)`. A report that resolves
/// to the colours already in force publishes nothing and repaints nothing.
///
/// **Why a repaint, and a full one.** Every colour on screen may have been
/// spelled, blended, floored or quantised from the colours before the report:
/// at sixteen colours an RGB colour is emitted as the slot nearest to what that
/// slot paints, a terminal-defined colour measures as nothing until it is
/// reported, and a palette of the terminal's own roles is grounded on its page.
/// The generation the publication moves clears the render cache and the memos
/// keyed on it; the diff writer's own idea of what is on screen is this class's
/// `onChange` to invalidate.
///
/// Non-generic and separate from `RenderLoop` for the reason
/// ``ClientCapabilityRefresher`` gives: it is unit-testable on its own, with
/// what it publishes recorded rather than assigned process-wide, which every
/// suite rendering beside such a test would otherwise read.
@MainActor
internal final class TerminalColorRefresher {

    /// Everything the terminal has said since the startup exchange closed,
    /// accumulated: a reply for one slot is a fact about that slot, and sixteen
    /// of them spread over several drains are a table only once the last lands.
    private var heard = TerminalColorReport()

    /// Whether a theme report has arrived and not yet been taken — see
    /// ``takeAppearanceReport()``.
    private var sawAppearanceReport = false

    /// What the startup exchange published, which a late answer adds to.
    private let known: TerminalColors

    /// The process environment, for `COLORFGBG`. Read once: a running process's
    /// environment does not change under it.
    private let environment: [String: String]

    /// The colours this has published, or `known` before it has published any.
    ///
    /// Kept rather than read back from `TerminalColors.current`, so a test can
    /// record publications instead of assigning the process value, and so
    /// "did this change anything?" is answered by what this class did.
    private var inForce: TerminalColors

    /// Where a changed record goes: ``publishProcessWide(_:)`` in an app.
    private let publish: (TerminalColors) -> Void

    /// Runs when a report changed the record: the owner invalidates the whole
    /// screen and asks for a frame.
    private let onChange: @MainActor () -> Void

    /// Assigns `colours` to `TerminalColors.current`, which every frame in the
    /// process reads: where an app's record goes.
    ///
    /// Named rather than written as a closure where it is the default, because
    /// `RenderLoop` takes the same default for the refresher it builds, and a test
    /// driving a loop passes something else there.
    nonisolated static func publishProcessWide(_ colours: TerminalColors) {
        TerminalColors.current = colours
    }

    init(
        known: TerminalColors = .current,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        publish: @escaping (TerminalColors) -> Void = publishProcessWide,
        onChange: @escaping @MainActor () -> Void
    ) {
        self.known = known
        self.environment = environment
        self.inForce = known
        self.publish = publish
        self.onChange = onChange
    }

    /// Whether the terminal has ever said anything of its own about its
    /// colours: named one in the startup exchange, named one since, or reported
    /// its own theme with a `CSI ? 997`.
    ///
    /// What decides whether it is worth asking again — see
    /// ``TerminalColorRequester``. A terminal that answered nothing when it was
    /// asked properly will not have learned how by the next resize.
    ///
    /// `prefersDark` alone is deliberately not enough: it can come from
    /// `COLORFGBG`, which is the environment talking rather than the terminal,
    /// and under a multiplexer it can describe a terminal that is no longer
    /// attached. Limit: a `997` the STARTUP exchange heard is folded into
    /// `prefersDark` by `TerminalColorQuery.resolve` and is indistinguishable
    /// from that hint here, so only one heard since the app started counts.
    var hasAnsweredAboutColors: Bool {
        known.foreground != nil || known.background != nil || known.slots != nil
            || heard.foreground != nil || heard.background != nil || heard.appearance != nil
            || heard.slots.contains(where: { $0 != nil })
    }

    /// Applies the replies the parser siphoned out of one drain's bytes.
    ///
    /// `TerminalColorQuery.parse(_:)` is the walk, as it is for the exchange —
    /// safe here because the fence is the one sequence that ends that walk and
    /// the parser never keeps a fence.
    func noteReplies(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        record(TerminalColorQuery.parse(bytes))
        let colours = TerminalColorQuery.refreshed(heard, over: known, environment: environment)
        guard colours != inForce else { return }
        inForce = colours
        publish(colours)
        onChange()
    }

    /// Whether a `CSI ? 997 ; Ps n` has arrived since the last call, clearing it.
    ///
    /// The terminal saying its own theme changed — which is not a colour. It
    /// names light or dark and nothing else, so the colours behind it have to be
    /// asked for: `RenderLoop` hands this to `TerminalColorRequester`, the one
    /// moment a host volunteers that anything changed at all.
    ///
    /// Kept apart from what this class publishes, because the two answer
    /// different questions. A report that resolves to the colours already in
    /// force publishes nothing — and still means the theme changed, since it
    /// says nothing about the sixteen slots or the default pair it does not
    /// carry.
    func takeAppearanceReport() -> Bool {
        defer { sawAppearanceReport = false }
        return sawAppearanceReport
    }

    /// Folds one drain's report into everything heard before it. A field the
    /// report does not fill is not a denial of what an earlier one said.
    private func record(_ report: TerminalColorReport) {
        if let foreground = report.foreground { heard.foreground = foreground }
        if let background = report.background { heard.background = background }
        for (index, slot) in report.slots.enumerated() where slot != nil {
            heard.slots[index] = slot
        }
        if let appearance = report.appearance {
            heard.appearance = appearance
            sawAppearanceReport = true
        }
    }
}
