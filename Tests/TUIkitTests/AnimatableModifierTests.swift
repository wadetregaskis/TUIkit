//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimatableModifierTests.swift
//
//  The built-in modifiers that nominate something continuous about themselves.
//  Each is checked by DRAWING it: a modifier that claims to animate and does
//  not is invisible to a conformance check.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// One place in the tree, rendered again as the frame clock advances.
@MainActor
private final class Screen {
    var context = makeRenderContext(width: 30, height: 8)

    init(_ animation: Animation?) {
        context.environment.canAnimate = true
        context.environment.transaction = Transaction(animation: animation)
    }

    func draw<V: View>(_ view: V, atMillis millis: Int) -> [String] {
        context.environment.frameNowNanos = Int64(millis) * 1_000_000
        let storage = context.environment.stateStorage!
        storage.beginRenderPass()
        defer { storage.endRenderPass() }
        return renderToBuffer(view, context: context).lines.map(\.stripped)
    }

    func measure<V: View>(_ view: V, atMillis millis: Int) -> ViewSize {
        context.environment.frameNowNanos = Int64(millis) * 1_000_000
        return measureChild(
            view, proposal: ProposedSize(width: 30, height: 8), context: context)
    }
}

@MainActor
@Suite("Animatable modifiers")
struct AnimatableModifierTests {

    /// Where the text starts, as a column — the only thing an offset changes.
    private func indent(_ lines: [String]) -> Int? {
        for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            return line.count - line.drop(while: { $0 == " " }).count
        }
        return nil
    }

    @Test("An offset slides")
    func offsetSlides() {
        // `.offset` paints into an overlay layer rather than into its own
        // lines — a terminal has no transparency, so the vacated cells must
        // show what is under them — so the displacement to read is the
        // layer's, not an indent.
        let screen = Screen(.linear(duration: 1))
        func column(_ x: Int, atMillis millis: Int) -> Int? {
            screen.context.environment.frameNowNanos = Int64(millis) * 1_000_000
            let storage = screen.context.environment.stateStorage!
            storage.beginRenderPass()
            defer { storage.endRenderPass() }
            return renderToBuffer(Text("ab").offset(x: x), context: screen.context)
                .overlays.first?.offsetX
        }

        #expect(column(0, atMillis: 0) == 0)
        // The frame the change lands on is still at the old position.
        #expect(column(20, atMillis: 0) == 0)
        #expect(column(20, atMillis: 500) == 10)
        #expect(column(20, atMillis: 1000) == 20)
    }

    @Test("Padding opens rather than jumping")
    func paddingOpens() {
        let screen = Screen(.linear(duration: 1))
        _ = screen.draw(Text("ab").padding(.leading, 0), atMillis: 0)
        #expect(indent(screen.draw(Text("ab").padding(.leading, 8), atMillis: 0)) == 0)
        #expect(indent(screen.draw(Text("ab").padding(.leading, 8), atMillis: 500)) == 4)
        #expect(indent(screen.draw(Text("ab").padding(.leading, 8), atMillis: 1000)) == 8)
    }

    @Test("Padding's size follows the picture, on both walks")
    func paddingMeasuresWhatItDraws() {
        // A layout animation whose measure disagreed with its render would lay
        // the page out for a frame that is not on screen.
        let screen = Screen(.linear(duration: 1))
        _ = screen.draw(Text("ab").padding(.leading, 0), atMillis: 0)
        _ = screen.draw(Text("ab").padding(.leading, 8), atMillis: 0)
        for millis in [0, 250, 500, 750, 1000] {
            let drawn = screen.draw(Text("ab").padding(.leading, 8), atMillis: millis)
            let measured = screen.measure(Text("ab").padding(.leading, 8), atMillis: millis)
            #expect(measured.width == drawn.map(\.count).max(), "at \(millis)ms")
        }
    }

    @Test("A fixed frame resizes")
    func fixedFrameResizes() {
        // Drawn, not only measured: a measure walk never STARTS an animation
        // (it must have no side effects), so a test that only measures would
        // watch a change that was never seen by a render.
        let screen = Screen(.linear(duration: 1))
        _ = screen.draw(Text("ab").frame(width: 4), atMillis: 0)
        #expect(screen.draw(Text("ab").frame(width: 24), atMillis: 0)[0].count == 4)
        #expect(screen.draw(Text("ab").frame(width: 24), atMillis: 500)[0].count == 14)
        #expect(screen.draw(Text("ab").frame(width: 24), atMillis: 1000)[0].count == 24)
    }

    @Test("A flexible frame has no number to move between, so it snaps")
    func flexibleFrameDoesNotAnimate() {
        // `.frame(maxWidth: .infinity)` is not a width; there is nothing to
        // interpolate, and pretending otherwise would animate from a sentinel.
        // A `-1` in the animatable data is the sentinel that says so; a
        // pinned dimension reports its width. (`.frame(…)` returns `some View`,
        // so the frame view is built directly here to read it.)
        let flexible = FlexibleFrameView(
            content: Text("ab"), minWidth: 4, idealWidth: nil, maxWidth: .infinity,
            minHeight: nil, idealHeight: nil, maxHeight: nil, alignment: .center)
        #expect(flexible.animatableData.first == -1)

        let fixed = FlexibleFrameView(
            content: Text("ab"), minWidth: 12, idealWidth: 12, maxWidth: .fixed(12),
            minHeight: nil, idealHeight: nil, maxHeight: nil, alignment: .center)
        #expect(fixed.animatableData.first == 12)
        #expect(fixed.animatableData.second == -1, "height was not pinned")

        // And writing into an unpinned dimension leaves it alone.
        var mutable = flexible
        mutable.animatableData = AnimatablePair(30, 30)
        #expect(mutable.animatableData.first == -1)
    }

    @Test("An app's own ViewModifier animates by declaring one property")
    func appModifierAnimates() {
        // The general route: `ModifiedView` is `Animatable` when its modifier
        // is, so a modifier author writes `animatableData` and nothing else.
        struct Indent: ViewModifier, Animatable {
            var columns: Int

            var animatableData: Double {
                get { Double(columns) }
                set { columns = Int(newValue.rounded()) }
            }

            func modify(buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
                buffer.replacingLines(buffer.lines.map { String(repeating: " ", count: columns) + $0 })
            }
        }

        let screen = Screen(.linear(duration: 1))
        _ = screen.draw(Text("ab").modifier(Indent(columns: 0)), atMillis: 0)
        #expect(indent(screen.draw(Text("ab").modifier(Indent(columns: 10)), atMillis: 0)) == 0)
        #expect(indent(screen.draw(Text("ab").modifier(Indent(columns: 10)), atMillis: 500)) == 5)
        #expect(indent(screen.draw(Text("ab").modifier(Indent(columns: 10)), atMillis: 1000)) == 10)
    }

    @Test("The geometry value types interpolate componentwise")
    func geometryTypesAnimate() {
        var insets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        insets.animatableData = EdgeInsets(top: 4, leading: 8, bottom: 12, trailing: 16)
            .animatableData.scaled(by: 0.5)
        #expect(insets == EdgeInsets(top: 2, leading: 4, bottom: 6, trailing: 8))

        var size = CellSize(width: 0, height: 0)
        size.animatableData = CellSize(width: 10, height: 5).animatableData.scaled(by: 0.5)
        #expect(size == CellSize(width: 5, height: 3), "a half cell rounds, it does not truncate")

        var point = UnitPoint.zero
        point.animatableData = UnitPoint.bottomTrailing.animatableData.scaled(by: 0.25)
        #expect(point == UnitPoint(x: 0.25, y: 0.25))
    }
}
