//  🖥️ TUIkit — Terminal UI Kit for Swift
//  WindowedFillerWidthTests.swift
//
//  A lazy stack of rows that fill their width, in a scroll view, in a tab: the
//  tab view sizes its panel to the scroll view's ideal width, which is the
//  stack's. The stack's seek answered that from width records the RENDER
//  took, and the render measures its rows at the viewport less the
//  scrollbar's column — so from the second frame on the stack said it was one
//  column narrower than it had on the first, the panel cut the scrollbar off,
//  and after a resize the list was drawn at the old terminal's width, shifted
//  and truncated. The frame depended on what had been drawn before it.
//
//  Counted instead as filling any width, a row capped by `.frame(maxWidth:)`
//  — which fills an offer below its cap and stops at it — answered every
//  later ask with the whole ask: twenty columns too wide from the second
//  frame. A filler is as wide as any ask up to how far it filled, and is
//  measured at a wider one.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// What the app does between frames: which tab is showing, where the list is
/// scrolled — a class, so a test can change either between frames.
@Observable
@MainActor
final class FillerListModel {
    var tab = 0
    var position = ScrollPosition()
}

/// One row of the list.
enum FillerListRow: Sendable, Equatable {
    /// A title at the leading edge and a number at the trailing one, a
    /// `Spacer` between: it fills whatever it is offered.
    case fills
    /// The same, capped by `.frame(maxWidth:)`: it fills an offer below the
    /// cap and is the cap's width at any offer past it.
    case capped(Int)
    /// A short text, with a width of its own.
    case short
    /// A navigation link whose label is `.fills`' — the `notes` stress
    /// session's row, which reaches the stack as a `Button` measured by
    /// rendering its label.
    case link
    /// A navigation link whose label fills only once its own `@State` says
    /// so, which it does on appearing.
    case statefulLink
}

/// The list: how many rows, what each is, and whether it opens scrolled to
/// its end.
struct FillerListPlan: Sendable {
    var count = 48
    var anchoredAtBottom = false
    var row: @Sendable (Int) -> FillerListRow

    static func every(_ row: FillerListRow) -> Self {
        Self(row: { _ in row })
    }
}

/// The `notes` stress session in miniature: a header over a list that
/// overflows its viewport, in the first of two tabs.
struct FillerListApp: App {
    let model: FillerListModel
    let plan: FillerListPlan

    init() {
        self.init(plan: .every(.fills))
    }

    init(model: FillerListModel = FillerListModel(), plan: FillerListPlan) {
        self.model = model
        self.plan = plan
    }

    var body: some Scene {
        WindowGroup { FillerListPage(model: model, plan: plan) }
    }
}

private struct FillerListPage: View {
    let model: FillerListModel
    let plan: FillerListPlan

    var body: some View {
        TabView(selection: Binding(get: { model.tab }, set: { model.tab = $0 })) {
            Tab("Notes", value: 0) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: "\(plan.count) notes")
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(0..<plan.count, id: \.self) { index in
                                    FillerListRowView(index: index, row: plan.row(index))
                                }
                            }
                        }
                        .defaultScrollAnchor(plan.anchoredAtBottom ? .bottom : nil)
                        .scrollPosition(Binding(get: { model.position }, set: { model.position = $0 }))
                    }
                }
            }
            Tab("Archive", value: 1) {
                Text(verbatim: "nothing archived")
            }
        }
    }
}

private struct FillerListRowView: View {
    let index: Int
    let row: FillerListRow

    var body: some View {
        switch row {
        case .fills:
            FillingRowLabel(index: index)
        case .capped(let cap):
            FillingRowLabel(index: index).frame(maxWidth: .fixed(cap))
        case .short:
            Text(verbatim: "row \(index)")
        case .link:
            NavigationLink(value: index) { FillingRowLabel(index: index) }
        case .statefulLink:
            NavigationLink(value: index) { FillsOnAppearing(index: index) }
        }
    }
}

/// A title at the leading edge and a number at the trailing one.
struct FillingRowLabel: View {
    let index: Int

    var body: some View {
        HStack(spacing: 1) {
            Text(verbatim: "note \(index)")
            Spacer()
            Text(verbatim: "#\(index)")
        }
    }
}

/// `FillingRowLabel`, but only once it has appeared: its `Spacer` is behind
/// its own `@State`.
private struct FillsOnAppearing: View {
    let index: Int
    @State private var fills = false

    var body: some View {
        HStack(spacing: 1) {
            Text(verbatim: "note \(index)")
            if fills { Spacer() }
            Text(verbatim: "#\(index)")
        }
        .onAppear { fills = true }
    }
}

/// Drives a `FillerListApp` a frame at a time, as the render loop would.
@MainActor
struct FillerListDriver {
    static let frameNanos: Int64 = 16_666_667

    let model: FillerListModel
    let app: HeadlessApp<FillerListApp>
    private var now: Int64 = 0

    init(plan: FillerListPlan, width: Int = 60, height: Int = 20) {
        model = FillerListModel()
        app = HeadlessApp(FillerListApp(model: model, plan: plan), width: width, height: height)
    }

    /// Draws a frame and returns its lines, styling stripped.
    mutating func frame() -> [String] {
        now += Self.frameNanos
        app.frame(atNanos: now)
        return app.screen.map(\.stripped)
    }
}

/// Whether some row of the list has something drawn in the screen's last
/// column — where a scroll view that fills the width draws its scrollbar.
/// Glyph-agnostic: which glyphs the bar uses depends on the terminal.
func drawsScrollbarAtTheEdge(_ screen: [String]) -> Bool {
    screen.filter { $0.contains("note ") || $0.contains("row ") }.contains { ($0.last ?? " ") != " " }
}

@MainActor
@Suite("A windowed stack of fillers measures the width it is asked at")
struct WindowedFillerWidthTests {
    /// The rows every test below is run over, bar the ones about one site.
    nonisolated static let lists: [FillerListRow] = [.fills, .capped(40), .link]

    @Test(
        "The list is drawn the same from its second frame, and after a trip to another tab",
        arguments: lists)
    func steadyFramesMatchTheFirst(row: FillerListRow) {
        var driver = FillerListDriver(plan: .every(row))
        let first = driver.frame()
        if row != .capped(40) {
            #expect(drawsScrollbarAtTheEdge(first), "precondition: the opening frame draws the bar")
        }
        let second = driver.frame()
        #expect(second == first, "a frame with no input between redrew the list differently")
        #expect(driver.frame() == first)

        driver.model.tab = 1
        _ = driver.frame()
        driver.model.tab = 0
        let back = driver.frame()
        let settled = driver.frame()
        #expect(back == first)
        #expect(settled == first, "the frame after coming back and the one after it disagree")
    }

    /// Besides lists of one kind: rows capped at different widths, both past
    /// the width they are first drawn at, so each fills it and only a measure
    /// at the new width tells the wider cap from the narrower one. They are
    /// the list's first rows and it opens at its end, so no band draws them:
    /// the first of them alone answered 70.
    nonisolated static let resized: [FillerListPlan] = [
        .every(.fills), .every(.capped(40)), .every(.link),
        FillerListPlan(
            anchoredAtBottom: true, row: { $0 == 0 ? .capped(70) : $0 == 1 ? .capped(80) : .short }),
    ]

    @Test(
        "A resized frame is the one an app opened at that size draws",
        arguments: resized, [(from: 60, to: 110), (from: 110, to: 60)])
    func aResizeDrawsTheNewWidth(plan: FillerListPlan, widths: (from: Int, to: Int)) {
        var driver = FillerListDriver(plan: plan, width: widths.from)
        _ = driver.frame()
        _ = driver.frame()
        driver.app.resize(width: widths.to, height: 20)
        let resized = driver.frame()
        let settled = driver.frame()

        var control = FillerListDriver(plan: plan, width: widths.to)
        let opened = control.frame()

        #expect(resized == opened, "the resized frame was laid out at the old width")
        #expect(settled == opened)
    }

    @Test("No served size disagrees with a fresh measure across a tab round trip", arguments: lists)
    func theMeasureMemoServesWhatAFreshMeasureSays(row: FillerListRow) {
        let wasVerifying = RenderCache.verifiesMeasureMemo
        RenderCache.verifiesMeasureMemo = true
        defer { RenderCache.verifiesMeasureMemo = wasVerifying }
        var driver = FillerListDriver(plan: .every(row))
        for tab in [0, 0, 0, 1, 1, 0, 0] {
            driver.model.tab = tab
            _ = driver.frame()
        }
        let mismatches = driver.app.renderCache.measureMemoMismatches
        #expect(mismatches.isEmpty, "\(mismatches)")
    }

    // MARK: - Each place a filler is recorded

    /// The rows the render's one-time seed measures, and nothing else: the
    /// list opens at its end, so no band ever draws its first rows, and those
    /// are the only ones that fill. The first frame's walk counts them at the
    /// ask; the seek that answers every later frame has only the seed's word.
    @Test("Fillers only the seed has seen are counted at the ask")
    func fillersTheSeedSaw() {
        var driver = FillerListDriver(
            plan: FillerListPlan(anchoredAtBottom: true, row: { $0 < 4 ? .fills : .short }))
        let first = driver.frame()
        #expect(drawsScrollbarAtTheEdge(first), "precondition: the opening frame is as wide as the ask")
        #expect(!first.contains { $0.contains("note 3") }, "precondition: the fillers are not drawn")
        for _ in 0..<3 {
            #expect(driver.frame() == first)
        }
    }

    /// The rows the last render DREW, and nothing else: the fillers are the
    /// list's last rows, it opens at its end, and the rows its budget reaches
    /// from the top are short. A filler on screen fills whatever it is given,
    /// so the stack must say it is as wide as the ask — not the width the
    /// render gave it, a column short of the ask under the scroll view.
    ///
    /// The opening frame is sized by the walk, which runs before any band is
    /// drawn and so knows only the rows its budget reaches from the top; the
    /// band's floor applies from the frame after.
    @Test("Fillers only the band drew are counted at the ask")
    func fillersTheBandDrew() {
        var driver = FillerListDriver(
            plan: FillerListPlan(anchoredAtBottom: true, row: { $0 < 40 ? .short : .fills }))
        _ = driver.frame()
        let second = driver.frame()
        #expect(second.contains { $0.contains("note 47") }, "precondition: the fillers are drawn")
        #expect(drawsScrollbarAtTheEdge(second), "the stack said it was narrower than its fillers")
        for _ in 0..<3 {
            #expect(driver.frame() == second)
        }
    }

    /// The rows past the seed that an earlier band drew: a collection over
    /// `anchoredWindowThreshold` rows is seeded from its first sixteen only,
    /// and rows sixteen and seventeen — within the budget of the ask, and
    /// drawn by the opening band — fill. Scrolled away, only the records the
    /// band left say they do.
    ///
    /// From the second frame: the opening frame of a collection this large is
    /// answered by the anchored estimate, whose sample is those sixteen rows.
    @Test("Fillers an earlier band drew are counted at the ask")
    func fillersAnEarlierBandDrew() {
        var driver = FillerListDriver(
            plan: FillerListPlan(count: 300, row: { (16..<18).contains($0) ? .fills : .short }),
            height: 30)
        _ = driver.frame()
        let second = driver.frame()
        #expect(second.contains { $0.contains("note 17") }, "precondition: the fillers are drawn")
        #expect(drawsScrollbarAtTheEdge(second))

        driver.model.position.scrollTo(edge: .bottom)
        _ = driver.frame()
        let scrolled = driver.frame()
        #expect(scrolled.contains { $0.contains("row 299") }, "precondition: scrolled to the end")
        #expect(!scrolled.contains { $0.contains("note 17") }, "precondition: the fillers are not drawn")
        #expect(drawsScrollbarAtTheEdge(scrolled), "the records answered with the width the band was drawn at")
    }

    /// Links whose labels fill only once their own `@State` says so: the
    /// button learns that its label fills by asking it, and the label's state
    /// lives where the button's style DRAWS it, inside the standard variant's
    /// row. Asked anywhere else, the label read its state fresh — not filling
    /// — the button was recorded one column short of the ask, and the list
    /// drawn so from then on.
    ///
    /// From the third frame. The labels' state changes after the first, and
    /// the seek answers the frame after a write from what the render recorded
    /// on the frame before it: the second frame is laid out at the labels'
    /// old width and its rows are clipped to it. That lag is the records',
    /// not the probe's, and is not fixed here.
    @Test("Links whose labels fill once their state says so are counted as filling")
    func statefulFillingLinks() {
        var driver = FillerListDriver(plan: .every(.statefulLink))
        _ = driver.frame()
        _ = driver.frame()
        let settled = driver.frame()
        #expect(drawsScrollbarAtTheEdge(settled), "the links were recorded one column short")
        for _ in 0..<2 {
            #expect(driver.frame() == settled)
        }
    }

    // MARK: - The seek against the walk

    /// Rows past the budget that filled a narrower offer than this ask's: the
    /// walk that answers a stack's first measure asks every row, and its
    /// flexibility is theirs at THIS ask — a true filler still fills it, a
    /// row capped at 40 does not once the ask is past 40. The seek has only
    /// the records, taken at 35 columns, and has to ask those rows too.
    @Test(
        "Fillers past the budget make the seek as flexible as the walk",
        arguments: [FillerListRow.fills, .capped(40)])
    func flexibilityPastTheBudget(row: FillerListRow) {
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        environment.installVolatileReadTracker(VolatileReadTracker())
        var context = RenderContext(
            availableWidth: 60, availableHeight: 10, environment: environment, tuiContext: tuiContext)
        context.isMeasuring = true
        let stack = _VStackCore(
            alignment: .leading, spacing: 0, overflow: .window,
            content: ForEach(0..<48, id: \.self) { index in
                FillerListRowView(index: index, row: index < 30 ? .short : row)
            })
        let proposal = ProposedSize(width: nil, height: nil)
        // No hypothesis yet: the walk answers.
        let walked = stack.sizeThatFits(proposal: proposal, context: context)

        // What a render at 35 columns leaves behind: every row recorded, as
        // the seed records a stack this size.
        let state = stack.uniformWindowState(context: context)
        state.hypothesisExtent = 1
        let children = resolveChildViewCollection(from: stack.content, context: context)
        var narrow = context
        narrow.availableWidth = 35
        for ordinal in 0..<children.count {
            let size = children[ordinal].measure(proposal: ProposedSize(width: 35, height: nil), context: narrow)
            state.rowWidths.note(ordinal: ordinal, size: size)
        }
        state.rowWidths.markSeeded()
        let sought = stack.uniformSeekSizeThatFits(children, proposal: proposal, context: context)

        #expect(walked.isWidthFlexible == (row == .fills), "precondition: the walk's own answer")
        #expect(sought?.width == walked.width)
        #expect(sought?.isWidthFlexible == walked.isWidthFlexible)
    }

    /// A filling row squeezed below what it wants does not always reach its
    /// offer: `note 16`, a `Spacer` and `#16` offered 8 columns drops `#16`,
    /// which no longer fits whole, and reports 7 — flexible, a column short.
    /// It has no more of a width of its own than a row that reached its
    /// offer, and filed as 7 wide it was answered 7 at every ask, where the
    /// walk fills 60.
    @Test("A filler squeezed a column below its offer is counted as a filler")
    func aSqueezedFillerIsAFiller() {
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        environment.installVolatileReadTracker(VolatileReadTracker())
        var context = RenderContext(
            availableWidth: 60, availableHeight: 10, environment: environment, tuiContext: tuiContext)
        context.isMeasuring = true
        let stack = _VStackCore(
            alignment: .leading, spacing: 0, overflow: .window,
            content: ForEach(10..<58, id: \.self) { index in
                FillerListRowView(index: index, row: .fills)
            })
        let proposal = ProposedSize(width: nil, height: nil)
        let walked = stack.sizeThatFits(proposal: proposal, context: context)

        let state = stack.uniformWindowState(context: context)
        state.hypothesisExtent = 1
        let children = resolveChildViewCollection(from: stack.content, context: context)
        var narrow = context
        narrow.availableWidth = 8
        var squeezed = 0
        for ordinal in 0..<children.count {
            let size = children[ordinal].measure(proposal: ProposedSize(width: 8, height: nil), context: narrow)
            if size.isWidthFlexible, size.width < 8 { squeezed += 1 }
            state.rowWidths.note(ordinal: ordinal, size: size)
        }
        state.rowWidths.markSeeded()
        let sought = stack.uniformSeekSizeThatFits(children, proposal: proposal, context: context)

        #expect(squeezed == children.count, "precondition: every row came back short of its offer")
        #expect(walked.width == 60, "precondition: the walk's own answer")
        #expect(sought?.width == walked.width)
        #expect(sought?.isWidthFlexible == walked.isWidthFlexible)
    }
}

// MARK: - Other parents of a windowed stack of fillers

/// Where the list sits, besides a tab: each asks the stack its width a
/// different way.
enum FillerListParent: CaseIterable, Sendable, CustomStringConvertible {
    /// A scroll view on both axes: the whole-content ask.
    case twoAxisScrollView
    /// A vertical scroll view beside a text: the row distributes its width.
    case besideText
    /// The same, the scroll view at its ideal width.
    case fixedSizeBesideText
    /// Rows capped at 30, beside a text.
    case cappedBesideText
    /// Rows capped at 30, in a vertical scroll view in a horizontal one.
    case cappedVerticalInHorizontal
    /// A vertical scroll view in a horizontal one: the inner one is asked its
    /// ideal size by the outer one's probe, and measures its content for it.
    case verticalInHorizontal

    var description: String {
        switch self {
        case .twoAxisScrollView: "two-axis scroll view"
        case .besideText: "beside a text"
        case .fixedSizeBesideText: "fixed-size, beside a text"
        case .cappedBesideText: "capped, beside a text"
        case .cappedVerticalInHorizontal: "capped, vertical in horizontal"
        case .verticalInHorizontal: "vertical in horizontal"
        }
    }
}

private struct FillerParentApp: App {
    let parent: FillerListParent

    init() { parent = .besideText }
    init(parent: FillerListParent) { self.parent = parent }

    var body: some Scene {
        WindowGroup { FillerParentPage(parent: parent) }
    }
}

private struct FillerParentList: View {
    let row: FillerListRow

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<48, id: \.self) { index in
                FillerListRowView(index: index, row: row)
            }
        }
    }
}

private struct FillerParentPage: View {
    let parent: FillerListParent

    var body: some View {
        switch parent {
        case .twoAxisScrollView:
            ScrollView([.horizontal, .vertical]) { FillerParentList(row: .fills) }
        case .besideText:
            HStack(spacing: 1) {
                ScrollView { FillerParentList(row: .fills) }
                Text(verbatim: "side")
            }
        case .fixedSizeBesideText:
            HStack(spacing: 1) {
                ScrollView { FillerParentList(row: .fills) }.fixedSize(horizontal: true, vertical: false)
                Text(verbatim: "side")
            }
        case .cappedBesideText:
            HStack(spacing: 1) {
                ScrollView { FillerParentList(row: .capped(30)) }
                Text(verbatim: "side")
            }
        case .cappedVerticalInHorizontal:
            ScrollView(.horizontal) { ScrollView { FillerParentList(row: .capped(30)) } }
        case .verticalInHorizontal:
            ScrollView(.horizontal) { ScrollView { FillerParentList(row: .fills) } }
        }
    }
}

@MainActor
@Suite("A windowed stack of fillers answers every parent the same from frame to frame")
struct WindowedFillerParentTests {
    @Test("Frames with no input between are drawn the same, and no served size is stale",
        arguments: FillerListParent.allCases)
    func steadyFrames(parent: FillerListParent) {
        let wasVerifying = RenderCache.verifiesMeasureMemo
        RenderCache.verifiesMeasureMemo = true
        defer { RenderCache.verifiesMeasureMemo = wasVerifying }
        let app = HeadlessApp(FillerParentApp(parent: parent), width: 60, height: 12)
        var now: Int64 = 0
        var frames: [[String]] = []
        for _ in 0..<4 {
            now += FillerListDriver.frameNanos
            app.frame(atNanos: now)
            frames.append(app.screen.map(\.stripped))
        }
        #expect(frames[1] == frames[0], "\(parent): the second frame differs from the first")
        #expect(frames[3] == frames[2], "\(parent): the fourth frame differs from the third")
        let mismatches = app.renderCache.measureMemoMismatches
        #expect(mismatches.isEmpty, "\(parent): \(mismatches.first ?? "")")
    }
}
