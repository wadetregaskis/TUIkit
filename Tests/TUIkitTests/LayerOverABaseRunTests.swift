//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LayerOverABaseRunTests.swift
//
//  A layer composited over a run of its base — a `ZStack`'s later child, an
//  `.overlay`, a `Layout`'s later subview, a `List` row's content over its
//  `.listRowBackground` view — punches the run under its footprint:
//  the layer's cells replace the base's, and a run replaying there would paint
//  over them. But a layer's cell that names no field of its own shows the base's
//  field, which the composite fills in from the frame the render drew. Where the
//  run's frames disagree about that field, a render at a later step shows the
//  layer's glyph on another field, and the punched run cannot replay it: the cell
//  froze on the drawn frame's field. So the compositor asks for a render at each
//  of the run's steps (`Opacity as composition.md` §109), each `.overlay` of a
//  chain under a token of its own. A layer that fades over the run is not asked
//  for yet, nor is a floating one the root lays over it, and both are held here as
//  known issues.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// Two cells whose field turns red and blue, frame by frame, drawn at the frame the
/// render's instant shows — or, `glyphOnly`, two glyphs on one field.
private struct TurningField: View, Renderable {
    var glyphOnly = false
    var body: Never { fatalError("renders via Renderable") }

    static let fields = ["\u{1B}[48;2;200;0;0m  \u{1B}[0m", "\u{1B}[48;2;0;0;200m  \u{1B}[0m"]
    static let glyphs = ["\u{1B}[48;2;0;0;200m⠋⠋\u{1B}[0m", "\u{1B}[48;2;0;0;200m⠙⠙\u{1B}[0m"]

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let run = AnimatedCellRun(
            offsetX: 0, offsetY: 0, width: 2, frames: glyphOnly ? Self.glyphs : Self.fields, frameTicks: 3,
            clock: .content)
        let elapsed = Double(context.environment.frameNowNanos) / 1_000_000_000
        var buffer = FrameBuffer(lines: [run.frame(atElapsed: elapsed)])
        guard !context.isMeasuring else { return buffer }
        // Drawn at the instant, as an animating view is: never served from a memo.
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        buffer.animatedCells = [run]
        return buffer
    }
}

/// A `Layout` that lays every subview at the same origin, the last on top.
private struct Stacked: Layout {
    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        ViewSize(width: 2, height: 1)
    }

    func placeSubviews(in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()) {
        for index in subviews.indices {
            subviews[index].place(at: (x: bounds.x, y: bounds.y), proposal: .unspecified)
        }
    }
}

private struct LayerOverARunApp: App {
    var shape = LayerOverABaseRunTests.Shape.zStack
    var glyphOnly = false
    var layer = LayerOverABaseRunTests.Layer.label
    init() {}
    init(
        _ shape: LayerOverABaseRunTests.Shape, glyphOnly: Bool = false,
        layer: LayerOverABaseRunTests.Layer = .label
    ) {
        self.shape = shape
        self.glyphOnly = glyphOnly
        self.layer = layer
    }

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                Button("focus") {}
                shape.view(over: TurningField(glyphOnly: glyphOnly), layer: layer)
            }
        }
    }
}

/// Two runs turning their fields on two clocks: the first two cells every 3 ticks,
/// the last two every 7, with two plain cells between them.
private struct TwoTurningFields: View, Renderable {
    var body: Never { fatalError("renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let first = AnimatedCellRun(
            offsetX: 0, offsetY: 0, width: 2, frames: TurningField.fields, frameTicks: 3, clock: .content)
        let last = AnimatedCellRun(
            offsetX: 4, offsetY: 0, width: 2, frames: TurningField.fields, frameTicks: 7, clock: .content)
        let elapsed = Double(context.environment.frameNowNanos) / 1_000_000_000
        var buffer = FrameBuffer(lines: [first.frame(atElapsed: elapsed) + "  " + last.frame(atElapsed: elapsed)])
        guard !context.isMeasuring else { return buffer }
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        buffer.animatedCells = [first, last]
        return buffer
    }
}

/// A label a floating layer lays on the run's first cell, which the root's flatten
/// composites after the walk: `.offset` from the line below, or `.position` in a
/// `ZStack` over the run.
private struct FloatingLabelOverARunApp: App {
    var floating = LayerOverABaseRunTests.Floating.offset
    init() {}
    init(_ floating: LayerOverABaseRunTests.Floating) { self.floating = floating }

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 0) {
                Button("focus") {}
                switch floating {
                case .offset:
                    TurningField()
                    Text("x").offset(y: -1)
                case .position:
                    ZStack(alignment: .topLeading) {
                        TurningField()
                        Text("x").position(x: 0, y: 0)
                    }
                }
            }
        }
    }
}

/// A label over each of `TwoTurningFields`' runs, laid by two `.overlay`s chained on it.
private struct ChainedOverlaysApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                Button("focus") {}
                TwoTurningFields()
                    .overlay(alignment: .leading) { Text("x") }
                    .overlay(alignment: .trailing) { Text("y") }
            }
        }
    }
}

/// Two cells turning their field every `frameTicks` ticks, after `offsetX` plain ones.
private struct TurningFieldAt: View, Renderable {
    let offsetX: Int
    let frameTicks: Int
    var body: Never { fatalError("renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let run = AnimatedCellRun(
            offsetX: offsetX, offsetY: 0, width: 2, frames: TurningField.fields, frameTicks: frameTicks,
            clock: .content)
        let elapsed = Double(context.environment.frameNowNanos) / 1_000_000_000
        var buffer = FrameBuffer(lines: [String(repeating: " ", count: offsetX) + run.frame(atElapsed: elapsed)])
        guard !context.isMeasuring else { return buffer }
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        buffer.animatedCells = [run]
        return buffer
    }
}

/// A row's label over two background views chained on it, each with a run under a
/// letter of the label: the inner's at `x` every 3 ticks, the outer's at `y` every 7.
private struct ChainedRowBackgroundsApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                Button("focus") {}
                List {
                    Text("x   y")
                        .listRowBackground(TurningFieldAt(offsetX: 0, frameTicks: 3))
                        .listRowBackground(TurningFieldAt(offsetX: 4, frameTicks: 7))
                }
            }
        }
    }
}

/// A three-line row over the one-line run as its background view, which the row
/// repeats down itself; on the run's own line a chip that names its field covers
/// the run, so nothing there shows the run's field.
private struct TallRowOverARunApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                Button("focus") {}
                List {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("xy").background(Color.rgb(0, 160, 0))
                        Text("b")
                        Text("c")
                    }
                    .listRowBackground(TurningField())
                }
            }
        }
    }
}

@MainActor
@Suite("A layer over a run of its base")
struct LayerOverABaseRunTests {

    /// The compositors that lay a label over the base's run.
    enum Shape: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case zStack
        case overlay
        case layout
        /// A `List` row's content over a background view: `.listRowBackground(_:)`.
        case rowBackground

        var testDescription: String { rawValue }

        @MainActor @ViewBuilder
        func view(over base: some View, layer: Layer) -> some View {
            switch self {
            case .zStack: ZStack(alignment: .leading) { base; layer.view }
            case .overlay: base.overlay(alignment: .leading) { layer.view }
            case .layout: Stacked { base; layer.view }
            case .rowBackground: List { layer.view.listRowBackground(base) }
            }
        }
    }

    /// The floating layers the root's flatten lays over the run.
    enum Floating: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case offset
        case position

        var testDescription: String { rawValue }
    }

    /// What is laid over the run's first cell.
    enum Layer: String, CaseIterable, Sendable, CustomTestStringConvertible {
        /// `Text("x")`: names no field, and does not fade.
        case label
        /// `Text("x").opacity(0.4)`: a label that loses its cell's glyph contest to
        /// what is behind it.
        case fadedLabel
        /// A one-cell black scrim at one half: names its field, and fades.
        case scrim
        /// `Text("x")` on green, faded to one half: its field mixed toward what is
        /// behind it.
        case fadedChip

        var testDescription: String { rawValue }

        @MainActor @ViewBuilder
        var view: some View {
            switch self {
            case .label: Text("x")
            case .fadedLabel: Text("x").opacity(0.4)
            case .scrim: Color.rgb(0, 0, 0).opacity(0.5).frame(width: 1, height: 1)
            case .fadedChip: Text("x").background(Color.rgb(0, 160, 0)).opacity(0.5)
            }
        }
    }

    /// The label shows the run's field, and the run's frames turn it: every tick shows
    /// the label on the field a render at that instant draws it on. Punched, the run
    /// left the label's cell on the drawn frame's field — `x` on `rgb(200, 0, 0)` where
    /// a render drew it on `rgb(0, 0, 200)` — at every tick of the other frame.
    @Test("A label over a run turning its field is on the field each step shows", arguments: Shape.allCases)
    func aLabelOverATurningField(shape: Shape) throws {
        let found = ReplayOracle.compare({ LayerOverARunApp(shape) }, ticks: 24, size: (30, 8))
        try #require(found.compared >= 24, "\(shape): only \(found.compared) rows were compared")
        // A render at each of the run's steps, and no more: 3 ticks a frame, 24 steps
        // of 3 ticks walked, so one a step — 20 a second, the run's own rate.
        #expect(found.scheduledRenders == 24, "\(shape): \(found.scheduledRenders) renders asked for")
        for mismatch in found.mismatches { Issue.record("\(shape): \(mismatch)") }
    }

    /// A run whose frames change only their glyphs under the label shows the label on
    /// one field at every step: nothing to ask a render for.
    @Test("A label over a run turning only its glyphs asks for no render", arguments: Shape.allCases)
    func aLabelOverTurningGlyphs(shape: Shape) throws {
        let found = ReplayOracle.compare({ LayerOverARunApp(shape, glyphOnly: true) }, ticks: 24, size: (30, 8))
        try #require(found.compared >= 24, "\(shape): only \(found.compared) rows were compared")
        #expect(found.scheduledRenders == 0, "\(shape): \(found.scheduledRenders) renders asked for")
        for mismatch in found.mismatches { Issue.record("\(shape): \(mismatch)") }
    }

    /// Two `.overlay`s chained on one base, each over a run of its own that turns its
    /// field, the first every 3 ticks and the second every 7: each label is on the
    /// field each step shows. The base renders at the modifier's own identity, so the
    /// two overlays share one; under one token for both, the outer's request replaced
    /// the inner's, and `x` held its field between the 7-tick run's steps.
    @Test("Chained overlays each ask for the steps of the run under their own label")
    func chainedOverlays() throws {
        let found = ReplayOracle.compare({ ChainedOverlaysApp() }, ticks: 24, size: (30, 8))
        try #require(found.compared >= 24, "only \(found.compared) rows were compared")
        // A render at each step of either run: the 3-tick run's 24 in the 72 ticks
        // walked, and the 7-tick run's 11, 4 of them at the same instants.
        #expect(found.scheduledRenders == 31, "\(found.scheduledRenders) renders asked for")
        for mismatch in found.mismatches { Issue.record(Comment(rawValue: mismatch)) }
    }

    /// Two `.listRowBackground` views chained on one row, each with a run under a
    /// letter of the label, the inner's every 3 ticks and the outer's every 7: each
    /// letter is on the field each step shows. The row's content renders at the
    /// modifier's own identity, as an `.overlay`'s base does, so the two share one;
    /// under one token for both, the outer's request replaced the inner's.
    @Test("Chained row backgrounds each ask for the steps of the run under their own label")
    func chainedRowBackgrounds() throws {
        let found = ReplayOracle.compare({ ChainedRowBackgroundsApp() }, ticks: 24, size: (30, 8))
        try #require(found.compared >= 24, "only \(found.compared) rows were compared")
        // As for the chained overlays: the 3-tick run's 24 steps and the 7-tick run's
        // 11, 4 of them at the same instants.
        #expect(found.scheduledRenders == 31, "\(found.scheduledRenders) renders asked for")
        for mismatch in found.mismatches { Issue.record(Comment(rawValue: mismatch)) }
    }

    /// Known issue: a background view shorter than its row is repeated down the row
    /// as lines alone (`_ListRowBackgroundView.filled`), its run left on the first
    /// copy. Where nothing on the run's own line shows its field — here a chip that
    /// names its own covers it — nothing asks for a render, and the copies below hold
    /// the drawn frame's field between renders: `b` on `rgb(200, 0, 0)` where a render
    /// draws it on `rgb(0, 0, 200)`. Older than §109; pinned until the copies carry
    /// the run, or ask for its steps.
    @Test("A background view repeated down a tall row holds its copies' drawn field (known issue)")
    func aBackgroundRepeatedDownATallRow() throws {
        let found = ReplayOracle.compare({ TallRowOverARunApp() }, ticks: 24, size: (30, 10))
        try #require(found.compared >= 24, "only \(found.compared) rows were compared")
        withKnownIssue("a repeated background's copies carry no run and ask for no render (§109)") {
            #expect(
                found.mismatches.isEmpty,
                "\(found.mismatches.count) mismatches, first \(found.mismatches.first ?? "")")
        }
    }

    /// Known issue: a layer that fades, or names a translucent field, over a run of
    /// its base is resolved over the run's drawn frame, and the composite punches the
    /// run as it does under a label. §109's rule asks for a render only where the
    /// layer's cell takes the base's field and the run's frames disagree about it, so
    /// where the layer loses the glyph to the run, or mixes its ink or field toward
    /// the run's, the cell holds the drawn frame's between renders: a faded label or a
    /// scrim over a run turning only its glyphs, a faded chip over one turning its
    /// field. Older than the rule; pinned until the rule asks there too.
    @Test(
        "A fading layer over a run holds the drawn frame between renders (known issue)",
        arguments: Shape.allCases, [Layer.fadedLabel, .scrim, .fadedChip])
    func aFadingLayerOverARun(shape: Shape, layer: Layer) throws {
        let found = ReplayOracle.compare(
            { LayerOverARunApp(shape, glyphOnly: layer != .fadedChip, layer: layer) }, ticks: 24, size: (30, 8))
        try #require(found.compared >= 24, "\(shape), \(layer): only \(found.compared) rows were compared")
        withKnownIssue("a fading layer over a base run asks for no render at the run's steps (§109)") {
            #expect(
                found.mismatches.isEmpty,
                "\(shape), \(layer): \(found.mismatches.count) mismatches, first \(found.mismatches.first ?? "")")
        }
    }

    /// Known issue: the root's flatten of floating layers (`compositingOverlays`)
    /// punches a base's run under a layer as the compositors above do — an `.offset`
    /// or `.position` label over the run — and asks for nothing: it runs after the
    /// walk, with no render context to ask from. So the label holds the drawn frame's
    /// field between renders, `x` on `rgb(200, 0, 0)` where a render draws it on
    /// `rgb(0, 0, 200)`. Older than §109; pinned until the flatten asks too.
    @Test(
        "A floating label over a run turning its field holds the drawn field (known issue)",
        arguments: Floating.allCases)
    func aFloatingLabelOverATurningField(floating: Floating) throws {
        let found = ReplayOracle.compare({ FloatingLabelOverARunApp(floating) }, ticks: 24, size: (30, 8))
        try #require(found.compared >= 24, "\(floating): only \(found.compared) rows were compared")
        withKnownIssue("the root's flatten punches a run under a floating layer and asks for no render (§109)") {
            #expect(
                found.mismatches.isEmpty,
                "\(floating): \(found.mismatches.count) mismatches, first \(found.mismatches.first ?? "")")
        }
    }
}
