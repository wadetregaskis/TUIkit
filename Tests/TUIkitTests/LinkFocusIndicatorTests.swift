//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LinkFocusIndicatorTests.swift
//
//  A link is written inside a sentence, so it must occupy exactly its own
//  words. Every other plain button reserves two cells for a focus bullet —
//  which is right for a column of controls, where the reservation is what keeps
//  them aligned as the focus moves, and wrong for four words in a paragraph:
//  the prose either side of the link cannot be spaced correctly when the
//  control silently takes two columns of it.
//
//  So a `Link` defaults to breathing its own label instead, and the bullet is
//  available through `.linkFocusIndicator(.bullet)`. Both directions are pinned
//  here, because the default is the part that is easy to lose.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Link focus indication")
struct LinkFocusIndicatorTests {

    private func harness(
        width: Int = 40, palette: (any Palette)? = nil
    ) -> (TUIContext, RenderContext) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        if let palette { environment.palette = palette }
        environment.applyRuntimeServices(from: tui)
        return (
            tui,
            RenderContext(
                availableWidth: width, availableHeight: 6, environment: environment,
                tuiContext: tui)
        )
    }

    private func render(_ view: some View, tui: TUIContext, context: RenderContext) -> FrameBuffer {
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        context.environment.focusManager?.beginRenderPass()
        defer {
            tui.stateStorage.endRenderPass()
            context.environment.focusManager?.endRenderPass()
        }
        return renderToBuffer(view, context: context)
    }

    private var link: some View {
        Link("swift.org", destination: URL(string: "https://swift.org")!)
    }

    /// The default: the label starts at column 0. Nothing sits in front of it,
    /// so the words either side of it in a sentence are the author's to space.
    @Test("A link reserves no cells beside its label")
    func linkOccupiesItsOwnWidth() {
        let (tui, context) = harness()
        let buffer = render(link, tui: tui, context: context)
        let line = try? #require(buffer.lines.first).stripped
        #expect(line == "swift.org", "got \(line ?? "nil")")
    }

    /// …and the same link asked for the bullet gets the plain button's two
    /// reserved cells back.
    @Test("The bullet affordance restores the two reserved cells")
    func bulletReservesTwoCells() {
        let (tui, context) = harness()
        let buffer = render(
            link.linkFocusIndicator(.bullet), tui: tui, context: context)
        let line = (try? #require(buffer.lines.first).stripped) ?? ""
        // Two cells, whatever is IN them — the bullet when focused (which it is
        // here, nothing else having registered), two spaces when not. The
        // reservation is the point, not the glyph.
        #expect(line.hasSuffix("swift.org"), "got \(line)")
        #expect(line.count == "swift.org".count + 2, "got \(line)")
    }

    /// A plain `Button` is NOT changed by any of this. It is the control the
    /// reservation is right for, and a link's default must not reach it.
    @Test("A plain Button keeps its reserved cells")
    func plainButtonIsUntouched() {
        let (tui, context) = harness()
        let buffer = render(
            Button("Press") {}.buttonStyle(.plain), tui: tui, context: context)
        let line = (try? #require(buffer.lines.first).stripped) ?? ""
        #expect(line.hasSuffix("Press"), "got \(line)")
        #expect(line.count == "Press".count + 2, "got \(line)")
    }

    /// The two affordances differ in WHICH cells move, not in whether anything
    /// does: a focused link still animates, on the same clock.
    @Test("A focused link animates its label rather than a prefix")
    func focusedLinkAnimatesTheLabel() throws {
        let (tui, context) = harness()
        let manager = try #require(context.environment.focusManager)
        // One pass to register the link's focusID, then focus it by id and
        // render again — the ring only exists after something has drawn.
        _ = render(link, tui: tui, context: context)
        let id = try #require(
            manager.registeredFocusIDsInActiveSection().first,
            "the link should have registered a focusID")
        manager.focus(id: id)
        let focused = render(link, tui: tui, context: context)

        let run = try #require(
            focused.animatedCells.first, "a focused link should hand the loop a run")
        #expect(run.offsetX == 0, "the run starts at the label, not two cells in")
        #expect(
            run.width == "swift.org".count,
            "the run covers the whole label, not a two-cell prefix; got \(run.width)")
        #expect(run.frames.count > 1, "…and it actually animates")
    }

    /// The frames must actually DIFFER, which the first version of this did not
    /// manage: it breathed between the label's resting colour and
    /// `palette.accent`, and a `Link` rests AT the accent — so both ends were
    /// the same colour, the run replayed one picture, and a focused link sat
    /// there motionless. It appeared to work under the pointer only because
    /// hover lifts the resting colour away from the accent and accidentally
    /// gave the breath somewhere to go.
    @Test("A focused link's breath is made of different colours")
    func focusedLinkFramesDiffer() throws {
        let (tui, context) = harness()
        let manager = try #require(context.environment.focusManager)
        _ = render(link, tui: tui, context: context)
        let id = try #require(manager.registeredFocusIDsInActiveSection().first)
        manager.focus(id: id)
        let run = try #require(render(link, tui: tui, context: context).animatedCells.first)

        #expect(
            Set(run.frames).count > 1,
            "every frame is identical — the breath has nowhere to go, so nothing moves")
    }

    /// The quiet end of the breath is a fifth of the label's colour over WHAT
    /// IS BEHIND IT, and both ends were composited over `palette.background`
    /// regardless — which is the page, and a `TabView` body is not on the page.
    /// It is painted on the strip's own surface, one plane step off it
    /// (`TabView.surfaceColor`), and `Color.opacity(_:over:)` says in as many
    /// words to "pass the surface the colour actually draws on".
    ///
    /// Homebrew is the palette that makes the difference visible rather than
    /// merely wrong: a black page, a stated chrome tone 16 L\* above it, and a
    /// `(0, 249, 0)` accent. Dimmed over the page the trough came out
    /// `(0, 50, 0)` — luminance 0.0228 against the tab body's 0.0222, a ratio
    /// of **1.01:1** — so a focused link went the colour of the tab it sat in,
    /// once per breath. Over the body it is `(33, 83, 33)`, and 1.61:1.
    ///
    /// ``ViewConstants/chromeSeparationFloor`` is the floor for exactly this
    /// failure ("a thumb that fades to its track's colour on the way past"),
    /// and Homebrew clears it by a hair — 1.610 against 1.6 — which is the
    /// other reason to pin this palette rather than a comfortable one.
    ///
    /// Both affordances, because the two ends helpers carried the same page
    /// blend separately: `.text` breathes the label and `.bullet` the ●.
    ///
    /// Measured on the raw 24-bit colours, NOT through
    /// ``Color/downsampledToPalette256()`` as the chrome floors elsewhere are.
    /// Those measure a colour being *derived*, and want the answer a
    /// 256-colour terminal would also get. This measures a colour being
    /// *painted*, on a terminal that paints exactly these bytes — and the cube
    /// would hide it, snapping `(0, 50, 0)` up to `(0, 95, 0)` at nearly twice
    /// the luminance actually emitted.
    @Test(
        "A focused link's breath never sinks into the tab body behind it",
        arguments: [LinkFocusIndicator.text, .bullet])
    func theBreathStepsOffTheSurfaceItIsDrawnOn(indicator: LinkFocusIndicator) throws {
        let homebrew = try #require(PaletteRegistry.all.first { $0.name == "Homebrew" })
        try withColorDepth(.truecolor) {
            let (tui, context) = harness(palette: homebrew)
            let manager = try #require(context.environment.focusManager)
            let view = TabView(selection: .constant(0)) {
                Tab("Tab", value: 0) { link.linkFocusIndicator(indicator) }
            }
            _ = render(view, tui: tui, context: context)
            // By name, not by auto-focus: the `TabView` registers a focusID of
            // its own for arrow-key tab switching, and it registers first.
            let id = try #require(
                manager.registeredFocusIDsInActiveSection().first { $0.hasPrefix("button-") },
                "the link inside the tab should have registered a focusID")
            manager.focus(id: id)
            let run = try #require(render(view, tui: tui, context: context).animatedCells.first)
            let drawn = try run.frames.map(drawnForeground(of:))

            let surface = homebrew.liftedBackground.resolve(with: homebrew)
            // (33, 83, 33) is the accent at `focusBorderDim` over the tab
            // body; blended over the page instead it is (0, 50, 0).
            #expect(
                drawn.contains(.rgb(33, 83, 33)),
                "the trough is not the accent at 20% over the tab body")
            let worst = drawn.map { $0.contrastRatio(against: surface) }.min() ?? 0
            #expect(
                worst >= ViewConstants.chromeSeparationFloor,
                "the breath comes within \(worst):1 of the tab body it is drawn on")
        }
    }

    /// The focus SECTION's ● is the third breath drawn over a tab body — the
    /// one `AnimatedColor.activeSection` makes for a bordered container inside
    /// an active section. Same rule, same surface.
    @Test("A focus section's ● never sinks into the tab body behind it")
    func theSectionIndicatorStepsOffTheSurface() throws {
        let homebrew = try #require(PaletteRegistry.all.first { $0.name == "Homebrew" })
        try withColorDepth(.truecolor) {
            let (tui, context) = harness(palette: homebrew)
            let manager = try #require(context.environment.focusManager)
            let view = TabView(selection: .constant(0)) {
                Tab("Tab", value: 0) { Panel("Section") { link }.focusSection() }
            }
            let first = render(view, tui: tui, context: context)
            // The link registers in the SECTION, which is not the active one on
            // the first frame — so its id is read off the hit regions, and
            // focusing it activates the section.
            let id = try #require(
                first.hitTestRegions.compactMap(\.focusID).first { $0.hasPrefix("button-") },
                "the link inside the section should have registered a focusID")
            manager.focus(id: id)
            let runs = render(view, tui: tui, context: context).animatedCells
            let indicator = try #require(
                runs.first { $0.frames.contains { $0.contains(String(BorderRenderer.focusIndicator)) } },
                "the active section's border should breathe a ●; runs: \(runs.count)")
            let drawn = try indicator.frames.map(drawnForeground(of:))
            let surface = homebrew.liftedBackground.resolve(with: homebrew)
            #expect(drawn.contains(.rgb(33, 83, 33)), "the ●'s trough is the accent at 20% over the tab body")
            let worst = drawn.map { $0.contrastRatio(against: surface) }.min() ?? 0
            #expect(worst >= ViewConstants.chromeSeparationFloor, "the ● comes within \(worst):1 of the tab body")
        }
    }

    /// The 24-bit foreground a frame paints its text in.
    ///
    /// Read out of the escape directly rather than through `SGRState`, which
    /// nets the parameters into a state and does not hand them back.
    private func drawnForeground(of frame: String) throws -> Color {
        let marker = try #require(
            frame.range(of: "38;2;"), "no 24-bit foreground in \(frame.debugDescription)")
        let channels = frame[marker.upperBound...]
            .prefix { $0.isNumber || $0 == ";" }
            .split(separator: ";")
            .compactMap { UInt8($0) }
        try #require(channels.count >= 3, "truncated foreground in \(frame.debugDescription)")
        return .rgb(channels[0], channels[1], channels[2])
    }

    /// …and it must do that WITHOUT the pointer, which is the case that was
    /// broken. Hover is a separate signal and must not be what makes focus
    /// visible.
    @Test("The breath does not depend on the pointer being over the link")
    func breathIsIndependentOfHover() throws {
        let (tui, context) = harness()
        let manager = try #require(context.environment.focusManager)
        _ = render(link, tui: tui, context: context)
        let id = try #require(manager.registeredFocusIDsInActiveSection().first)
        manager.focus(id: id)
        // No mouse event has been dispatched, so nothing is hovered.
        let run = try #require(render(link, tui: tui, context: context).animatedCells.first)
        #expect(Set(run.frames).count > 1, "unhovered focus must still move")
    }
}

/// A held Enter auto-repeats in the terminal, so the application receives a
/// stream of activations and every one is real. A `Button` wants that — holding
/// `+` should keep counting. A link does not: each repeat is another browser
/// window, or under a custom `OpenURLAction` another request.
@MainActor
@Suite("Link activation does not auto-repeat")
struct LinkActivationRepeatTests {

    private final class OpenCount: @unchecked Sendable {
        var count = 0
    }

    private func harness() -> (TUIContext, RenderContext, FocusManager) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        let manager = FocusManager()
        environment.focusManager = manager
        environment.applyRuntimeServices(from: tui)
        return (
            tui,
            RenderContext(
                availableWidth: 40, availableHeight: 4, environment: environment,
                tuiContext: tui),
            manager
        )
    }

    /// Activating repeatedly within the window opens once. The activations are
    /// delivered back to back, which is what a key repeat looks like.
    @Test("A burst of activations opens the link once")
    func burstOpensOnce() throws {
        let counter = OpenCount()
        let (tui, context, manager) = harness()
        let view = Link("swift.org", destination: URL(string: "https://swift.org")!)
            .environment(\.openURL, OpenURLAction { _ in counter.count += 1 })

        for _ in 0..<5 {
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            manager.beginRenderPass()
            _ = renderToBuffer(view, context: context)  // registers + auto-focuses
            _ = manager.dispatchKeyEvent(KeyEvent(key: .enter))
            tui.stateStorage.endRenderPass()
            manager.endRenderPass()
        }

        #expect(
            counter.count == 1,
            "five back-to-back activations should open once, opened \(counter.count) times")
    }

    /// The window has to SLIDE with the hold. Anchored only at accepted
    /// activations, it re-opened the URL every 700 ms for as long as the key
    /// was held: five browser windows from a three-second press.
    @Test("A held key is one activation however long it is held")
    func heldKeyIsOneActivation() {
        let gate = LinkActivationGate()
        let ms: UInt64 = 1_000_000
        var accepted = 0
        var now: UInt64 = 5_000 * ms
        while now < 8_000 * ms {
            if gate.allows(nowNanos: now) { accepted += 1 }
            now += 80 * ms  // a terminal's repeat cadence
        }
        #expect(accepted == 1, "a 3 s hold at 80 ms repeats was accepted \(accepted) times")
        #expect(gate.allows(nowNanos: now + 700 * ms), "a press after the window is a new gesture")
    }

    /// …and the window is the same one every other "is this one gesture or
    /// two?" decision in the framework uses. A link and a stepper arrow must
    /// not disagree about where one gesture ends.
    @Test("The window matches the framework's other repeat decisions")
    func windowMatchesAutoRepeat() {
        #expect(
            AutoRepeatTimer.defaultInitialDelayMs * 1_000_000
                == Int(ScrollbarRenderer.autoRepeatInitialDelayNanos))
        #expect(AutoRepeatTimer().initialDelayMs == AutoRepeatTimer.defaultInitialDelayMs)
    }
}
