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

    private func harness(width: Int = 40) -> (TUIContext, RenderContext) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
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
