//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimatedRunGroundTests.swift
//
//  A run records what its containers painted beneath its cells — its GROUND —
//  as they paint it, because nothing downstream can recover it: where the frame
//  the render drew gives a cell a field of its own, the row shows that field and
//  not the one beneath it.
//
//  The property every painter owes is one sentence: under every cell of a run
//  whose drawn frame states no field, the ground records exactly the field the
//  finished row shows there. So the suite draws a probe run inside each kind of
//  painter the framework has, builds its row the way the run loop does, and holds
//  the two to it — and then draws the same probe with a field of its own and
//  checks the ground did not move.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// A two-cell run whose frames are `ab` on a field of its own (frame 0, a caret
/// drawn visible) and `cd` on none (frame 1), drawing frame `drawn` into its
/// lines — so a test can put either on screen and ask what is beneath.
private struct GroundProbe: View, Renderable {
    var drawn = 1
    var body: Never { fatalError("renders via Renderable") }

    static let frames = ["\u{1B}[48;5;196mab\u{1B}[0m", "cd"]

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = FrameBuffer(lines: [Self.frames[drawn]])
        guard !context.isMeasuring else { return buffer }
        buffer.animatedCells = [
            AnimatedCellRun(offsetX: 0, offsetY: 0, width: 2, frames: Self.frames, clock: .content)
        ]
        return buffer
    }
}

/// Alternating rows, so a list paints a still fill of its own under a row that is
/// neither selected nor under the cursor.
private struct ZebraListStyle: ListStyle {
    var alternatingRowColors: Bool { true }
    var showsBorder: Bool { false }
    var rowPadding: EdgeInsets { EdgeInsets(all: 0) }
}

@MainActor
@Suite("A run records the ground its containers painted under it")
struct AnimatedRunGroundTests {

    /// The page every row here is built on, as the run loop's content area has it.
    private static let page = "\u{1B}[48;2;5;10;5m"
    private static let width = 24

    /// Every kind of painter a run can sit inside.
    enum Painter: String, CaseIterable, Sendable {
        /// Nothing but the page.
        case none
        /// A flat `.background`.
        case background
        /// A `.background` outside padding and a border: what is under the run
        /// is the fill, however far out it was painted.
        case backgroundAroundPadding
        /// Two backgrounds: the inner one is what the run sits on.
        case nestedBackgrounds
        /// A ramp across the row, a different entry under each cell.
        case horizontalRamp
        /// A `ZStack` over a colour: compositing paints the overlay over it.
        case zStackOverColour
        /// An `.overlay` on a view with a background.
        case overlayOnFill
        /// A row of a `List` that paints a fill of its own.
        case listRowFill
        /// A tab's surface, from `TabView`.
        case tabSurface

        @MainActor @ViewBuilder
        fileprivate func view(_ probe: GroundProbe) -> some View {
            switch self {
            case .none:
                probe
            case .background:
                probe.background(Color.rgb(200, 40, 40))
            case .backgroundAroundPadding:
                probe.padding(1).border().background(Color.rgb(40, 40, 200))
            case .nestedBackgrounds:
                HStack(spacing: 0) {
                    probe
                    Text(" ")
                    probe.background(Color.rgb(200, 40, 40))
                }
                .background(Color.rgb(40, 40, 200))
            case .horizontalRamp:
                HStack(spacing: 0) { Text("    "); probe; Text("    ") }
                    .background(
                        LinearGradient(
                            colors: [Color.rgb(200, 40, 40), Color.rgb(40, 40, 200)],
                            startPoint: .leading, endPoint: .trailing))
            case .zStackOverColour:
                ZStack { Color.rgb(40, 160, 40).frame(width: 6, height: 1); probe }
            case .overlayOnFill:
                Text("      ").background(Color.rgb(40, 160, 40)).overlay { probe }
            case .listRowFill:
                List(selection: .constant(Int?.none)) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: 0) { Text("row \(row) "); probe }
                    }
                }
                .listStyle(ZebraListStyle())
                .frame(height: 3)
            case .tabSurface:
                TabView(selection: .constant(0)) {
                    Tab("One", value: 0) { probe }
                    Tab("Two", value: 1) { Text("two") }
                }
                .tabViewStyle(.bordered)
            }
        }
    }

    /// The view's rows as the run loop builds them, and the probe's runs on them
    /// — only the probe's: a focused control beside it leaves a run of its own,
    /// whose drawn frame this suite knows nothing about.
    private func built(_ view: some View) -> (rows: [String], runs: [AnimatedCellRun]) {
        let context = makeRenderContext(width: Self.width, height: 12)
        let buffer = ColorDepth.withCurrent(.truecolor) { renderToScreen(view, context: context) }
        let writer = FrameDiffWriter(
            isAppleTerminal: false, isITerm2: false, isGhostty: false, isWarp: false, isTmux: false)
        let rows = writer.buildOutputLines(
            buffer: buffer, terminalWidth: Self.width, terminalHeight: buffer.lines.count,
            bgCode: Self.page, reset: ANSIRenderer.reset)
        return (rows, buffer.animatedCells.filter { $0.frames == GroundProbe.frames })
    }

    @Test("Under a frame that states no field, the ground is the field the row shows", arguments: Painter.allCases)
    func groundIsWhatTheRowShows(painter: Painter) throws {
        let (rows, runs) = built(painter.view(GroundProbe(drawn: 1)))
        try #require(!runs.isEmpty, "\(painter) carried no run up")
        for run in runs {
            let cells = paintedCells(rows[run.offsetY])
            let ground = run.groundFields(onPage: Self.page).map(spelled)
            let shown = (run.offsetX..<(run.offsetX + run.width)).map { cells[$0].background }
            #expect(ground == shown, "\(painter): run at (\(run.offsetX), \(run.offsetY)) records \(ground)")
            // Not vacuous: the probe itself paints nothing, so the row's field
            // under it is the painter's — or, with no painter, the page.
            if painter == .none { #expect(shown.allSatisfy { $0 == Self.page }) }
        }
    }

    @Test("A frame drawn with a field of its own leaves the ground where it was", arguments: Painter.allCases)
    func theDrawnFrameDoesNotMoveTheGround(painter: Painter) throws {
        let bare = built(painter.view(GroundProbe(drawn: 1)))
        let own = built(painter.view(GroundProbe(drawn: 0)))
        try #require(bare.runs.count == own.runs.count && !own.runs.isEmpty)
        for (drawnBare, drawnOwn) in zip(bare.runs, own.runs) {
            #expect(
                drawnOwn.groundFields(onPage: Self.page) == drawnBare.groundFields(onPage: Self.page),
                "\(painter): the ground moved with the frame the render drew")
            // And the row does show the frame's own field there — the thing a
            // replay reading the row would have taken for the ground.
            let cells = paintedCells(own.rows[drawnOwn.offsetY])
            #expect(cells[drawnOwn.offsetX].background == "\u{1B}[48;5;196m")
        }
    }

    /// A view that paints a field under its own run must declare the run INSIDE
    /// that painter, or nothing records the field: the run is attached after the
    /// paint. A colour swatch's focused bullet is the shape — ink over the
    /// swatch's own fill — and declared on the whole swatch it recorded nothing.
    @Test("A colour swatch's focused bullet records the swatch under it")
    func aSwatchBulletRecordsTheSwatch() throws {
        let context = makeRenderContext(width: Self.width, height: 3)
        let buffer = ColorDepth.withCurrent(.truecolor) {
            renderToScreen(ColorPicker("Colour", selection: .constant(.rgb(200, 40, 40))), context: context)
        }
        let run = try #require(
            buffer.animatedCells.first { $0.frames.contains { $0.contains("●") } },
            "the focused swatch left no bullet run")
        #expect(run.groundFields(onPage: Self.page).map(spelled) == ["\u{1B}[48;2;200;40;40m"])
    }

    // MARK: - The ground itself

    @Test("A run nothing painted under has no ground, and sits on the page")
    func noPainterNoGround() {
        let run = AnimatedCellRun(offsetX: 0, offsetY: 0, width: 3, frames: ["a", "b"], clock: .content)
        #expect(run.ground == nil)
        #expect(run.groundFields(onPage: Self.page).map(spelled) == Array(repeating: Self.page, count: 3))
        // A row built on nothing puts nothing under it.
        #expect(run.groundFields(onPage: "") == [nil, nil, nil])
    }

    /// A row is built with the page restated after every reset, so a reset inside
    /// a ground puts the page back — and a painter's colour restated after it wins,
    /// as the painter's restatement does in the row. The collapsed spelling is a
    /// reset too. An explicit `49` is the terminal's own field, not the page.
    @Test("A ground reads the way the row builder reads a row")
    func groundReadsLikeARow() {
        var run = AnimatedCellRun(offsetX: 0, offsetY: 0, width: 5, frames: ["a", "b"], clock: .content)
        let red = "\u{1B}[48;5;196m"
        run.ground = "\(red) \u{1B}[0m \u{1B}[0;48;5;21m \u{1B}[49m \u{1B}[0m\(red) "
        #expect(
            run.groundFields(onPage: Self.page).map(spelled)
                == [red, Self.page, "\u{1B}[48;5;21m", "", red])
    }

    @Test("A cut run keeps the ground of the cells it kept")
    func aCutKeepsItsGround() throws {
        var run = AnimatedCellRun(offsetX: 2, offsetY: 0, width: 4, frames: ["abcd", "efgh"], clock: .content)
        let red = "\u{1B}[48;5;196m"
        let blue = "\u{1B}[48;5;21m"
        run.ground = "\(red)  \(blue)  \u{1B}[0m"
        let cut = try #require(run.clipped(toColumns: 3..<5))
        #expect(cut.groundFields(onPage: "").map(spelled) == [red, blue])
    }

    @Test("A floating layer made opaque paints its runs' grounds")
    func anOpaqueLayerPaintsItsRuns() {
        var buffer = FrameBuffer(lines: ["ab"])
        buffer.animatedCells = [
            AnimatedCellRun(offsetX: 0, offsetY: 0, width: 2, frames: ["ab", "cd"], clock: .content)
        ]
        let green = "\u{1B}[48;5;28m"
        let painted = buffer.paintedOver(background: green)
        #expect(painted.animatedCells.first?.groundFields(onPage: "").map(spelled) == [green, green])
    }
}
