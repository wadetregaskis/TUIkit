//  🖥️ TUIkit — Terminal UI Kit for Swift
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
        #expect(rendered(crumbs) == " Library › Albums › Track")
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
        #expect(rendered(crumbs) == " Library › … › Track", "got: \(rendered(crumbs))")
        // …and the surviving root still navigates, which is the point of
        // keeping that end rather than the nearest parent.
        #expect(crumbs?.first?.popsTo == 0)
    }

    @Test("The width budget counts the blanks the crumbs sit behind")
    func widthCountsTheLead() {
        // The regression this pins: a trail measured on labels alone fits at a
        // width where the rendered bar — one blank cell per crumb — does not,
        // so the trail is drawn and then runs off the end instead of
        // degrading. One cell under the true width must not fit.
        let titles = ["Library", "Albums", "Track"]
        let full = rendered(trail(titles, width: 200))
        #expect(full == " Library › Albums › Track")
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
        #expect(rendered(crumbs) == " Library › … › Track", "got: \(rendered(crumbs))")
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

// MARK: - Appearance

/// How a crumb shows its states. The trail is a row of words, not a row of
/// controls, so its focus cue is the word itself: `.plain`'s two-cell bullet
/// landed against the preceding `›` (`Albums  ›●  Track`) and forced the whole
/// trail to double-space around it.
@MainActor
@Suite("Navigation crumb appearance", .serialized)
struct NavigationCrumbAppearanceTests {

    private struct Item: Hashable {
        let name: String
    }

    private func crumb(_ label: String) -> some View {
        Button(label) {}.buttonStyle(_NavigationCrumbButtonStyle())
    }

    @Test("A focused crumb breathes its own text, with no bullet beside it")
    func focusIsTheTextItself() {
        withColorDepth(.truecolor) {
            let context = makeRenderContext(width: 40, height: 3)
            let palette = context.environment.palette
            // First registrant takes the focus, which is the crumb under test.
            let buffer = renderToBuffer(crumb(" Library"), context: context)

            #expect(!buffer.lines.joined().contains(String(BorderRenderer.focusIndicator)))
            // The whole breath is handed to the run loop, so a focused bar does
            // not cost a screen render per tick.
            #expect(buffer.animatedCells.count == 1, "one run: \(buffer.animatedCells.count)")
            let frames = buffer.animatedCells.first?.frames ?? []
            #expect(frames.count > 1, "a pulse is more than one frame")
            #expect(
                frames.contains { $0.contains(code(palette.accent, palette)) },
                "the bright end is the accent")
            #expect(
                frames.contains { $0.contains(code(palette.foregroundSecondary, palette)) },
                "the dim end is where an unfocused crumb rests")
            #expect(frames.allSatisfy { !$0.contains(String(BorderRenderer.focusIndicator)) })
        }
    }

    @Test("An unfocused crumb is quiet, and still")
    func restingCrumbIsQuiet() {
        withColorDepth(.truecolor) {
            let context = makeRenderContext(width: 40, height: 3)
            let palette = context.environment.palette
            context.environment.focusManager!.register(FocusSentinel())
            let buffer = renderToBuffer(crumb(" Albums"), context: context)

            #expect(buffer.lines.joined().contains(code(palette.foregroundSecondary, palette)))
            #expect(buffer.animatedCells.isEmpty, "nothing to animate when nothing is focused")
        }
    }

    @Test("The pointer lifts a resting crumb")
    func hoverLiftsACrumb() {
        withColorDepth(.truecolor) {
            let context = makeRenderContext(width: 40, height: 3)
            let dispatcher = context.environment.mouseEventDispatcher!
            dispatcher.setActiveSupport(.full)
            let palette = context.environment.palette
            context.environment.focusManager!.register(FocusSentinel())

            let view = crumb(" Albums")
            let regions = renderToBuffer(view, context: context).hitTestRegions
            dispatcher.setRegions(regions)
            guard let region = regions.first else {
                Issue.record("expected a hit-test region from a crumb")
                return
            }
            _ = dispatcher.dispatch(
                MouseEvent(
                    button: .none, phase: .moved, x: region.offsetX + 2, y: region.offsetY))

            let hovered = renderToBuffer(view, context: context).lines.joined()
            #expect(
                hovered.contains(
                    code(palette.hoveredForeground(palette.foregroundSecondary), palette)),
                "lifted under the pointer: \(hovered)")
        }
    }

    @Test("The bar spaces its trail with single blanks")
    func theBarSpacesItselfSingly() {
        var path = NavigationPath()
        path.append(Item(name: "Deimos"))
        let binding = Binding(get: { path }, set: { path = $0 })

        let bar = renderToBuffer(
            NavigationStack(path: binding) {
                Text("root").navigationTitle("Planets")
                    .navigationDestination(for: Item.self) { item in
                        Text("body").navigationTitle(item.name)
                    }
            }, context: makeRenderContext(width: 40, height: 8)
        ).lines[0].stripped

        #expect(
            bar.hasPrefix(" Planets \(NavigationCrumbs.separator) Deimos"),
            "one blank between each part: \(bar)")
        #expect(!bar.contains(String(BorderRenderer.focusIndicator)), "no bullet in the bar: \(bar)")
    }

    // MARK: - Under a translucent palette or tint (§47)

    /// The breath under a wholly faded palette: every frame must be spent — opaque —
    /// so the run replays with no claim under it. Every frame is drawn when the run
    /// is built, so a translucent one traps inside this test: that covers every tick,
    /// not only the two ends (§29.3).
    @Test("A focused crumb under a faded palette breathes opaque, and claims nothing")
    func focusedCrumbSpendsAFadedPalette() {
        withColorDepth(.truecolor) {
            let context = makeRenderContext(width: 40, height: 3) { environment, _ in
                environment.palette = FadedAll()
            }
            let palette = context.environment.palette
            let ground = palette.background.resolve(with: palette)
            let buffer = renderToBuffer(crumb(" Library"), context: context)
            #expect(buffer.opacityRegions.isEmpty, "\(buffer.opacityRegions)")
            let frames = buffer.animatedCells.first?.frames ?? []
            #expect(frames.count > 1, "still focused, still breathing")
            #expect(frames.contains { $0.contains(code(palette.accent.spendingAlpha(over: ground), palette)) })
            #expect(frames.contains {
                $0.contains(code(palette.foregroundSecondary.spendingAlpha(over: ground), palette))
            })
        }
    }

    /// The ground is the surface the crumb sits on, not the page. With no surface set
    /// the two are one colour, and the test above cannot tell them apart.
    @Test("A focused crumb spends over the surface it sits on, not the page")
    func focusedCrumbSpendsOverTheSurface() {
        withColorDepth(.truecolor) {
            let surface = Color.rgb(90, 20, 20)
            let context = makeRenderContext(width: 40, height: 3) { environment, _ in
                environment.palette = FadedAll()
                environment.surfaceBackground = surface
            }
            let palette = context.environment.palette
            let page = palette.background.resolve(with: palette)
            let frames =
                renderToBuffer(crumb(" Library"), context: context).animatedCells.first?.frames ?? []
            #expect(frames.contains { $0.contains(code(palette.accent.spendingAlpha(over: surface), palette)) })
            #expect(!frames.contains { $0.contains(code(palette.accent.spendingAlpha(over: page), palette)) })
        }
    }

    /// §29's pair again: an opaque resting rung and a translucent tint. Pinned by the
    /// bytes: the bright end is the tint spent over the page, the dim end the rung as
    /// it was.
    @Test("A focused crumb under a faded tint breathes opaque, and claims nothing")
    func focusedCrumbSpendsAFadedTint() {
        withColorDepth(.truecolor) {
            let context = makeRenderContext(width: 40, height: 3)
            let palette = context.environment.palette
            let ground = palette.background.resolve(with: palette)
            let tint = Color.red.opacity(0.5)
            let buffer = renderToBuffer(crumb(" Library").tint(tint), context: context)
            let frames = buffer.animatedCells.first?.frames ?? []
            #expect(frames.count > 1)
            #expect(frames.contains { $0.contains(code(tint.spendingAlpha(over: ground), palette)) })
            #expect(frames.contains { $0.contains(code(palette.foregroundSecondary, palette)) })
            #expect(buffer.opacityRegions.isEmpty, "\(buffer.opacityRegions)")
        }
    }

    @Test("A still focus under a faded palette is drawn spent: no run, no claim")
    func stillFocusSpends() {
        withColorDepth(.truecolor) {
            let context = makeRenderContext(width: 40, height: 3) { environment, _ in
                environment.palette = FadedAll()
                environment.selectionIndicatorStyle = .none
            }
            let palette = context.environment.palette
            let ground = palette.background.resolve(with: palette)
            let buffer = renderToBuffer(crumb(" Library"), context: context)
            #expect(buffer.animatedCells.isEmpty && buffer.opacityRegions.isEmpty)
            #expect(buffer.lines.joined().contains(code(palette.accent.spendingAlpha(over: ground), palette)))
        }
    }

    /// Every cell of the label owes the rung's alpha — the lead blank included, as a
    /// `Text` claims its own blanks — and the cell after it owes nothing.
    @Test("A resting crumb under a faded palette claims exactly its own cells")
    func restingCrumbClaims() {
        withColorDepth(.truecolor) {
            let context = makeRenderContext(width: 40, height: 3) { environment, _ in
                environment.palette = FadedAll()
            }
            let palette = context.environment.palette
            context.environment.focusManager!.register(FocusSentinel())
            let buffer = renderToBuffer(crumb(" Albums"), context: context)
            for column in 0..<7 {
                let owes = owed(atColumn: column, row: 0, in: buffer)
                #expect(
                    owes.ink == owed(palette.foregroundSecondary) && owes.field == 1,
                    "column \(column) owes \(owes): \(buffer.opacityRegions)")
            }
            let past = owed(atColumn: 7, row: 0, in: buffer)
            #expect(past.ink == 1 && past.field == 1, "the cell after the crumb owes \(past)")
            #expect(buffer.lines.joined().contains(code(palette.foregroundSecondary, palette)))
        }
    }

    /// The lift carries its base's alpha, so the ALPHA cannot tell a hover claim from
    /// a resting one — the bytes are what show the lift happened.
    @Test("A hovered crumb under a faded palette claims the lift it drew")
    func hoveredCrumbClaims() {
        withColorDepth(.truecolor) {
            let context = makeRenderContext(width: 40, height: 3) { environment, _ in
                environment.palette = FadedAll()
            }
            let dispatcher = context.environment.mouseEventDispatcher!
            dispatcher.setActiveSupport(.full)
            let palette = context.environment.palette
            context.environment.focusManager!.register(FocusSentinel())

            let view = crumb(" Albums")
            let regions = renderToBuffer(view, context: context).hitTestRegions
            dispatcher.setRegions(regions)
            guard let region = regions.first else {
                Issue.record("expected a hit-test region from a crumb")
                return
            }
            _ = dispatcher.dispatch(
                MouseEvent(
                    button: .none, phase: .moved, x: region.offsetX + 2, y: region.offsetY))

            let hovered = renderToBuffer(view, context: context)
            let lift = palette.hoveredForeground(palette.foregroundSecondary)
            #expect(hovered.lines.joined().contains(code(lift, palette)), "lifted: \(hovered.lines)")
            for column in 0..<7 {
                #expect(owed(atColumn: column, row: 0, in: hovered).ink == owed(lift))
            }
        }
    }

    /// A GUARD, not coverage of the fix: the disabled colour was already a composite
    /// over the page, opaque, so this passes before and after. It holds §31.3's
    /// choice in place.
    @Test("A disabled crumb spends against the page, and claims nothing")
    func disabledCrumbSpends() {
        let context = makeRenderContext(width: 40, height: 3) { environment, _ in
            environment.palette = FadedAll()
        }
        #expect(renderToBuffer(crumb(" Albums").disabled(true), context: context).opacityRegions.isEmpty)
    }
}
