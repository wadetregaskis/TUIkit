//  🖥️ TUIKit — Terminal UI Kit for Swift
//  NavigationBreadcrumbTests.swift
//
//  The bar shows where you are AND how to get back, which at depth is a trail
//  rather than one button. The trail has to survive a narrow terminal, so it
//  degrades — full, then middle-elided, then back to the single Back button —
//  and these pin each rung of that ladder and the boundary between them.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Navigation breadcrumb")
struct NavigationBreadcrumbTests {

    private typealias Crumb = NavigationCrumbs.Crumb

    private func trail(_ titles: [String], width: Int) -> [Crumb]? {
        NavigationCrumbs.trail(titles: titles, fittingWidth: width)
    }

    /// What the bar actually draws: every crumb sits behind
    /// ``NavigationCrumbs/lead``, clickable or not — see that property.
    private func rendered(_ crumbs: [Crumb]?) -> String {
        (crumbs ?? []).map { NavigationCrumbs.lead + $0.label }.joined()
    }

    @Test("The root alone is not a trail")
    func rootAloneHasNoTrail() {
        // Nothing to go back to, so the bar has nothing a trail would add.
        #expect(trail(["Library"], width: 80) == nil)
        #expect(trail([], width: 80) == nil)
    }

    @Test("Every crumb shows when they fit")
    func fullTrail() {
        let crumbs = trail(["Library", "Albums", "Track"], width: 80)
        #expect(rendered(crumbs) == "  Library  ›  Albums  ›  Track")
    }

    @Test("Only the earlier crumbs navigate")
    func onlyAncestorsAreButtons() {
        guard let crumbs = trail(["Library", "Albums", "Track"], width: 80) else {
            Issue.record("no trail")
            return
        }
        // Root and middle pop to their own depth; the current screen and the
        // separators go nowhere — you are already there, and a separator is
        // punctuation.
        let targets = crumbs.map(\.popsTo)
        #expect(targets == [0, nil, 1, nil, nil], "targets: \(targets)")
    }

    @Test("A trail too wide elides its middle, keeping both ends")
    func elidedTrail() {
        let titles = ["Library", "Albums", "Nineteen Ninety Nine", "Track"]
        let full = rendered(trail(titles, width: 80))
        #expect(full.contains("Nineteen Ninety Nine"))

        // One cell narrower than the full trail forces the elision.
        let crumbs = trail(titles, width: full.count - 1)
        #expect(rendered(crumbs) == "  Library  ›  …  ›  Track", "got: \(rendered(crumbs))")
        // …and the surviving root still navigates, which is the point of
        // keeping that end rather than the nearest parent.
        #expect(crumbs?.first?.popsTo == 0)
    }

    @Test("The width budget counts the clickable crumbs' button chrome")
    func widthCountsButtonChrome() {
        // The regression this pins: a trail measured on labels alone fits at a
        // width where the rendered bar — two reserved cells per crumb — does
        // not, so the trail is drawn and then runs off the end instead of
        // degrading. One cell under the true width must not fit.
        let titles = ["Library", "Albums", "Track"]
        let full = rendered(trail(titles, width: 200))
        #expect(full == "  Library  ›  Albums  ›  Track")
        #expect(trail(titles, width: full.count) != nil)
        #expect(rendered(trail(titles, width: full.count - 1)) != full)
    }

    @Test("Too narrow for even the elided trail falls back to the Back button")
    func fallsBackToBackButton() {
        // `nil` is the signal the bar uses to draw `‹ Back` and the title, so
        // a cramped terminal degrades rather than showing a mangled trail.
        #expect(trail(["Library", "Albums", "Track"], width: 8) == nil)
    }

    @Test("A screen that published no title still holds its place")
    func untitledScreenKeepsItsSlot() {
        // An empty title would otherwise collapse two separators together and
        // read as a trail one level shorter than it is.
        let crumbs = trail(["Library", "", "Track"], width: 80)
        #expect(rendered(crumbs) == "  Library  ›  …  ›  Track", "got: \(rendered(crumbs))")
        #expect(crumbs?.count == 5, "an untitled screen still gets a crumb")
    }
}

@MainActor
@Suite("Navigation title memory")
struct NavigationTitleMemoryTests {

    @Test("Titles are remembered per depth")
    func remembersByDepth() {
        let coordinator = NavigationCoordinator()
        coordinator.recordTitle("Library", atDepth: 0)
        coordinator.recordTitle("Albums", atDepth: 1)
        coordinator.recordTitle("Track", atDepth: 2)
        #expect(coordinator.titles(upTo: 2) == ["Library", "Albums", "Track"])
        #expect(coordinator.titles(upTo: 1) == ["Library", "Albums"])
    }

    @Test("Popping and pushing elsewhere does not resurrect the old name")
    func staleDepthsAreDropped() {
        // The trap: pop from Track back to Albums, then push a DIFFERENT screen.
        // If depth 2 kept "Track", the trail would name a screen you never
        // opened.
        let coordinator = NavigationCoordinator()
        coordinator.recordTitle("Library", atDepth: 0)
        coordinator.recordTitle("Albums", atDepth: 1)
        coordinator.recordTitle("Track", atDepth: 2)
        coordinator.recordTitle("Albums", atDepth: 1)  // back
        coordinator.recordTitle("Artist", atDepth: 2)  // somewhere else
        #expect(coordinator.titles(upTo: 2) == ["Library", "Albums", "Artist"])
    }

    @Test("The root re-reporting itself does not erase the trail")
    func rootReportEveryFrameKeepsTheMiddle() {
        // The stack records the root every frame (it is the only frame in which
        // depth 0 publishes a title) and the top screen too — so nothing
        // reports the depths between them. Truncating on an UNCHANGED title
        // would wipe those out, leaving a two-crumb trail no matter how deep
        // the stack.
        let coordinator = NavigationCoordinator()
        coordinator.recordTitle("Library", atDepth: 0)
        coordinator.recordTitle("Albums", atDepth: 1)
        coordinator.recordTitle("Track", atDepth: 2)
        for _ in 0..<3 {
            coordinator.recordTitle("Library", atDepth: 0)  // the next frame
            coordinator.recordTitle("Track", atDepth: 2)
        }
        #expect(coordinator.titles(upTo: 2) == ["Library", "Albums", "Track"])
    }

    @Test("Recording out of order does not trap")
    func sparseDepths() {
        // Defensive: a depth recorded before its parent must not crash or
        // shuffle the earlier entries.
        let coordinator = NavigationCoordinator()
        coordinator.recordTitle("Deep", atDepth: 3)
        #expect(coordinator.titles(upTo: 3).count == 4)
        #expect(coordinator.titles(upTo: 3).last == "Deep")
    }
}
