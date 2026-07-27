//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollOverscroll.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Allowance

/// How far past an edge a scrollable may be pushed — §1.5 of
/// `Documentation/Scroll-anchoring.md`.
///
/// Overscroll is the empty space a deliberate push reveals beyond the content:
/// scroll up at the top and the content slides down, leaving blank rows above
/// it. It exists for two reasons. It gives the last row breathing space instead
/// of pinning it hard against the frame, and — because pushing *into* it is
/// unambiguous, while merely landing on the edge is not — it is the signal that
/// separates a deliberate push from a graze (§1.3's sticky edges).
public enum ScrollOverscroll: Sendable, Hashable {
    /// No overscroll: the content stops exactly at the edge. The default.
    case none

    /// A fixed number of rows (a `List`/`Table`) or lines (a `ScrollView`).
    case rows(Int)

    /// The viewport's own height, less `minus` rows/lines — the idiom for "you
    /// may scroll until only a couple of rows are left on screen".
    /// `.viewport(minus: 0)` allows a full viewport, so the content can be
    /// pushed entirely out of sight.
    case viewport(minus: Int)

    /// The allowance in rows/lines for a viewport of `viewportHeight`.
    func resolved(viewportHeight: Int) -> Int {
        switch self {
        case .none: return 0
        case .rows(let count): return max(0, count)
        case .viewport(let minus): return max(0, viewportHeight - max(0, minus))
        }
    }
}

// MARK: - Live state

/// A scrollable's live overscroll: how far it is currently pushed past an edge,
/// and the allowance bounding that.
///
/// The excursion is kept **separate from `scrollOffset`** rather than widening
/// the offset's range, which was measured to trap rather than merely misdraw:
/// `_ListCore`'s `(0..<scrollOffset)` is a fatal range when negative and
/// indexes past the data when over-max, and `ScrollView`'s
/// `lines.dropFirst(scrollOffset)` traps on a negative count. Keeping the offset
/// in `[0, maxOffset]` means no data-indexing consumer needs auditing at all,
/// the "N more" indicators ignore the excursion for free (they read the offset),
/// and the sticky-edge detector reads the excursion directly instead of
/// inferring a push from a clamped offset.
public struct ScrollOverscrollState: Sendable, Equatable {
    /// Rows/lines past an edge: **negative** past the top (blank space above the
    /// content), **positive** past the bottom. Zero whenever the content sits
    /// against its edges, which is always unless an allowance is configured.
    public internal(set) var excursion: Int = 0

    /// The resolved allowance above the content, in rows/lines.
    var top: Int = 0

    /// The resolved allowance below the content, in rows/lines.
    var bottom: Int = 0

    /// Whether any overscroll is permitted at all — the fast "this feature is
    /// off" test every hot path takes first.
    var isAllowed: Bool { top > 0 || bottom > 0 }

    public init() {}

    /// Re-resolves the allowance for the current viewport, and pulls an existing
    /// excursion back inside it (the terminal may have shrunk under a
    /// `.viewport`-relative allowance).
    mutating func resolve(top: ScrollOverscroll, bottom: ScrollOverscroll, viewportHeight: Int) {
        self.top = top.resolved(viewportHeight: viewportHeight)
        self.bottom = bottom.resolved(viewportHeight: viewportHeight)
        excursion = max(-self.top, min(self.bottom, excursion))
    }
}

// MARK: - Rendering the excursion

extension ScrollOverscrollState {
    /// Slides `lines` by the excursion, blank-filling the gap it opens and
    /// clipping the far side, so the count is unchanged.
    ///
    /// Callers pass the **content** lines only. `ScrollView` gets this effect
    /// from `replacingLines` on its finished viewport buffer because it appends
    /// its scrollbar as a whole column afterwards; the row-based views cannot,
    /// because they merge a bar cell into each line as they build it and stitch
    /// the "N more" indicators in at top and bottom. Both are chrome — they
    /// describe where the content sits — so they must not travel with it, which
    /// is why `List` and `Table` collect their row lines separately, slide them
    /// here, and only then assemble.
    func slid(_ lines: [String], blank: String) -> [String] {
        guard excursion != 0, !lines.isEmpty else { return lines }
        let gap = min(abs(excursion), lines.count)
        return excursion < 0
            ? Array(repeating: blank, count: gap) + lines.dropLast(gap)
            : Array(lines.dropFirst(gap)) + Array(repeating: blank, count: gap)
    }

    /// Where a row that occupied `yStart..<yStart + height` in the unslid
    /// content lands afterwards, clipped to `0..<lineCount` — or `nil` when the
    /// slide pushed it off entirely.
    ///
    /// Row hit-testing indexes the *drawn* lines, so a range that does not move
    /// with its row sends clicks to the wrong one. Clipping rather than
    /// translating keeps a partially-visible row clickable over the part of it
    /// that is actually on screen.
    func slidRange(yStart: Int, height: Int, lineCount: Int) -> (yStart: Int, height: Int)? {
        guard excursion != 0 else { return (yStart, height) }
        let moved = yStart - excursion
        let clippedStart = max(0, moved)
        let clippedEnd = min(lineCount, moved + height)
        guard clippedEnd > clippedStart else { return nil }
        return (clippedStart, clippedEnd - clippedStart)
    }
}

// MARK: - Environment

private struct ScrollOverscrollTopKey: EnvironmentKey {
    static let defaultValue: ScrollOverscroll = .none
}

private struct ScrollOverscrollBottomKey: EnvironmentKey {
    static let defaultValue: ScrollOverscroll = .none
}

extension EnvironmentValues {
    /// How far past its top a scrollable may be pushed. See
    /// ``TUIkit/View/scrollOverscroll(top:bottom:)``.
    public var scrollOverscrollTop: ScrollOverscroll {
        get { self[ScrollOverscrollTopKey.self] }
        set { self[ScrollOverscrollTopKey.self] = newValue }
    }

    /// How far past its bottom a scrollable may be pushed. See
    /// ``TUIkit/View/scrollOverscroll(top:bottom:)``.
    public var scrollOverscrollBottom: ScrollOverscroll {
        get { self[ScrollOverscrollBottomKey.self] }
        set { self[ScrollOverscrollBottomKey.self] = newValue }
    }
}

extension View {
    /// Lets the scrollables in this subtree be pushed past their edges, revealing
    /// blank space beyond the content.
    ///
    /// Each end is specified independently, because they are usually wanted for
    /// different reasons — a log view might allow a generous bottom overscroll so
    /// the newest line isn't jammed against the frame, and none at the top.
    ///
    /// ```swift
    /// ScrollView { LogLines(entries) }
    ///     .scrollOverscroll(top: .none, bottom: .viewport(minus: 1))
    /// ```
    ///
    /// Only a **user** gesture pushes into the allowance, and only once the
    /// content has actually reached the edge: a wheel tick that merely lands on
    /// the edge is spent getting there, and the next one pushes past. That is
    /// what makes a deliberate push distinguishable from a graze. Programmatic
    /// movement (`scrollTo`, an anchor, a reveal) never overscrolls, and never
    /// leaves an excursion behind.
    ///
    /// A view whose content already fits its viewport can still be pushed — the
    /// allowance is not conditional on there being anything to scroll.
    ///
    /// The "N more above/below" indicators count content, so they ignore the
    /// excursion entirely: pushing past the bottom does not invent rows below.
    ///
    /// - Parameters:
    ///   - top: The allowance above the content. Defaults to ``ScrollOverscroll/none``.
    ///   - bottom: The allowance below it. Defaults to ``ScrollOverscroll/none``.
    /// - Returns: A view whose scrollables permit that overscroll.
    public func scrollOverscroll(
        top: ScrollOverscroll = .none, bottom: ScrollOverscroll = .none
    ) -> some View {
        environment(\.scrollOverscrollTop, top)
            .environment(\.scrollOverscrollBottom, bottom)
    }
}
