//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationCrumbs.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Navigation crumbs

/// Builds the breadcrumb trail a ``NavigationStack``'s bar draws, and decides
/// when it will not fit.
///
/// Pure: titles and a width in, crumbs out. That is deliberate — the trail's
/// interesting behaviour is what it does when it runs out of room, and testing
/// that through a rendered bar would mean reading a screen to check arithmetic.
@MainActor
enum NavigationCrumbs {
    /// One element of the trail.
    struct Crumb: Sendable, Equatable {
        /// What it reads.
        let label: String
        /// The depth clicking it returns to, or `nil` for the current screen
        /// (which is where you already are) and for the elision marker.
        let popsTo: Int?
        /// Whether this is punctuation rather than a screen — the `›` between
        /// crumbs, and the `…` standing in for the ones that did not fit.
        ///
        /// Not derivable from the label: an untitled screen reads `…` too, and
        /// it is a screen, drawn like one.
        let isChrome: Bool

        init(label: String, popsTo: Int?, isChrome: Bool = false) {
            self.label = label
            self.popsTo = popsTo
            self.isChrome = isChrome
        }
    }

    /// The trail for `titles`, or `nil` when even its shortest form will not
    /// fit and the caller should fall back to the Back button.
    ///
    /// Three forms, tried widest first:
    ///
    /// 1. every crumb — `Root › Section › Detail`;
    /// 2. the middle elided — `Root › … › Detail`, which keeps the two ends
    ///    that orient you (where the trail starts, where you are);
    /// 3. nothing, so the bar draws `‹ Back` and the title as it always did.
    ///
    /// The root is kept rather than the nearest parent because "how do I get
    /// all the way out" is the question a deep trail is usually being asked,
    /// and the parent is one Escape away regardless.
    static func trail(titles: [String], fittingWidth width: Int) -> [Crumb]? {
        let named = titles.enumerated().map { depth, title in
            (depth: depth, label: title.isEmpty ? "…" : title)
        }
        guard named.count > 1 else { return nil }  // the root alone is not a trail

        func build(_ parts: [(depth: Int, label: String)], elided: Bool) -> [Crumb] {
            var crumbs: [Crumb] = []
            for (index, part) in parts.enumerated() {
                if index > 0 {
                    crumbs.append(Crumb(label: Self.separator, popsTo: nil, isChrome: true))
                }
                let isCurrent = part.depth == (titles.count - 1)
                crumbs.append(Crumb(label: part.label, popsTo: isCurrent ? nil : part.depth))
            }
            if elided, crumbs.count > 2 {
                crumbs.insert(Crumb(label: "…", popsTo: nil, isChrome: true), at: 1)
                crumbs.insert(Crumb(label: Self.separator, popsTo: nil, isChrome: true), at: 1)
            }
            return crumbs
        }

        let full = build(named, elided: false)
        if Self.width(full) <= width { return full }

        // Elided: first and last, with a marker between them.
        if named.count > 2 {
            let ends = [named[0], named[named.count - 1]]
            let short = build(ends, elided: true)
            if Self.width(short) <= width { return short }
        }
        return nil
    }

    /// The glyph between crumbs. `›` (U+203A) rather than `>` so it reads as
    /// chrome rather than as text, and it is single-width everywhere TUIkit
    /// measures (see Terminal-compatibility.md).
    static var separator: String { "\u{203A}" }

    /// The blank cell every crumb sits behind, separators included.
    ///
    /// One cell, uniformly, which is what makes the trail read as evenly spaced
    /// (`Planets › Mars › Deimos`) and what makes ``width(_:)`` match what lands
    /// on the screen — a trail measured without it overruns by a cell per crumb,
    /// which is exactly where the fallback to the Back button would misfire.
    ///
    /// It was two cells while the clickable crumbs were plain `Button`s: that
    /// style reserves two for its focus bullet whether or not anyone plans for
    /// them, so the separators and the current screen had to be padded to match
    /// or the row read as ragged. ``_NavigationCrumbButtonStyle`` puts the focus
    /// in the crumb's own text instead, so nothing reserves anything and the
    /// trail spaces itself.
    static var lead: String { " " }

    /// What a crumb occupies on screen: its lead plus its label.
    private static func width(_ crumbs: [Crumb]) -> Int {
        crumbs.reduce(0) { $0 + lead.count + $1.label.strippedLength }
    }
}
