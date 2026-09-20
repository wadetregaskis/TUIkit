//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DragSessionRegistryMemoTests.swift
//
//  The drag session keeps THREE per-frame registries — drop targets,
//  auto-scroll zones and reorder hosts — and `beginFrame()` empties all three
//  before every walk, exactly as the mouse dispatcher empties its handler
//  table. A subtree served from a value memo does not render, so it refilled
//  none of them: the stored buffer still carried the region, the handler
//  behind it was refiled from the effect journal, and the registry the drop
//  resolves that id against was empty. The row looked alive and accepted
//  nothing.
//
//  These assert on the REGISTRIES and on the drop, never on the rendered
//  lines. The buffer is identical either way, and a write journalled nowhere
//  is recorded by neither side of the render-memo verifier's comparison — so
//  `TUIKIT_VERIFY_RENDER_MEMO` reported no mismatch at all while every one of
//  these was being dropped.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitView

/// What the destinations were handed, kept outside the memo's key so nothing
/// in the view value changes when a drop lands.
private final class DropTally: @unchecked Sendable {
    var dropped: [String] = []
}

/// A memoizable card that is a drop destination. Equality is by title alone —
/// the tally is the view's construction, not its content — which is what lets
/// two separately-built values compare equal and hit.
private struct DropCard: View, @MainActor Equatable {
    let title: String
    let tally: DropTally

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.title == rhs.title }

    var body: some View {
        Text(title)
            .dropDestination(for: String.self) { payloads, _ in
                self.tally.dropped.append("\(self.title)←\(payloads.joined())")
                return true
            }
    }
}

/// A memoizable card holding a `List` that registers all three: a row drop
/// target (`dropDestination`), a reorder host (`onMove`) and — since it
/// scrolls — an auto-scroll zone.
private struct ListCard: View, @MainActor Equatable {
    let title: String

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.title == rhs.title }

    var body: some View {
        List {
            ForEach(["a", "b", "c"], id: \.self) { Text($0) }
                .onMove { _, _ in }
                .dropDestination(for: String.self) { _, _ in }
        }
        .frame(width: 20, height: 6)
    }
}

/// A memoizable card holding a scrolling `ScrollView`, which registers an
/// auto-scroll zone and nothing else.
private struct ScrollCard: View, @MainActor Equatable {
    let title: String

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.title == rhs.title }

    var body: some View {
        ScrollView {
            VStack {
                Text("one")
                Text("two")
                Text("three")
                Text("four")
                Text("five")
            }
        }
        .frame(width: 20, height: 3)
    }
}

/// Renders frames the way `RenderLoop` brackets them — every per-walk registry
/// emptied first, including the drag session's — and publishes the frame's
/// regions to the dispatcher as the loop publishes the composited root
/// buffer's.
@MainActor
private final class DropLoopHarness {
    let tui = TUIContext()
    let focusManager = FocusManager()

    var cache: RenderCache { tui.renderCache }
    var dispatcher: MouseEventDispatcher { tui.mouseEventDispatcher }
    var session: DragAndDropSession { tui.dragAndDropSession }

    init() {
        dispatcher.setActiveSupport(.full)
    }

    /// Renders one frame and returns its buffer.
    @discardableResult
    func frame(_ view: some View) -> FrameBuffer {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tui)
        environment.installVolatileReadTracker(VolatileReadTracker())
        let context = RenderContext(
            availableWidth: 40, availableHeight: 20,
            environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        cache.beginRenderPass()
        focusManager.beginRenderPass()
        focusManager.beginSceneRender()
        dispatcher.beginRenderPass()
        // What `WindowGroup.renderScene` does before the tree renders.
        session.beginFrame()
        let buffer = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tui.stateStorage.endRenderPass()
        cache.removeInactive()
        dispatcher.setRegions(buffer.hitTestRegions)
        return buffer
    }

    /// Renders `view` and returns the frame's buffer, checking that nothing
    /// under the memos rendered — so whatever is in the registries afterwards
    /// got there by replay.
    @discardableResult
    func servedFrame(_ view: some View, _ number: Int) -> FrameBuffer {
        let missesBefore = cache.stats.misses
        let buffer = frame(view)
        #expect(
            cache.stats.misses == missesBefore,
            "frame \(number) re-rendered the memoized subtree, so it proves nothing")
        return buffer
    }

    /// Drags `payload` from nowhere in particular and releases it at `(x, y)`,
    /// which is the whole of a drop as far as the session is concerned.
    @discardableResult
    func drop(_ payload: String, atX x: Int, y: Int) -> Bool {
        session.lastAbsoluteEvent = MouseEvent(button: .left, phase: .pressed, x: x, y: y)
        session.begin(payload: payload, preview: FrameBuffer(text: payload))
        session.lastAbsoluteEvent = MouseEvent(button: .left, phase: .released, x: x, y: y)
        return session.performDrop()
    }
}

/// Where `label` is drawn, found IN the rendered lines rather than computed: a
/// test that adds up the stack's own padding is testing its copy of the
/// arithmetic.
@MainActor
private func dropCell(of label: String, in buffer: FrameBuffer) -> (x: Int, y: Int)? {
    for (y, line) in buffer.lines.enumerated() {
        let stripped = line.stripped
        guard let range = stripped.range(of: label) else { continue }
        return (stripped.distance(from: stripped.startIndex, to: range.lowerBound), y)
    }
    return nil
}

@MainActor
@Suite("The drag session's registries through the render memo")
struct DragSessionRegistryMemoTests {

    @MainActor
    private static func page(_ tally: DropTally) -> some View {
        VStack {
            DropCard(title: "alpha", tally: tally).equatable()
            DropCard(title: "bravo", tally: tally).equatable()
            DropCard(title: "charlie", tally: tally).equatable()
        }
    }

    @Test("Every frame registers the drop targets, whether it rendered them or served them")
    func targetsAreRegisteredOnServedFrames() {
        let harness = DropLoopHarness()
        let tally = DropTally()

        harness.frame(Self.page(tally))
        #expect(harness.session.targets.count == 3, "frame 1 registered the three destinations")
        #expect(!harness.cache.isEmpty, "no destination's buffer was stored")

        // Nothing under the memos renders on these frames, so the targets can
        // only be there if the registration was made again from the journal.
        for number in 2...3 {
            harness.servedFrame(Self.page(tally), number)
            #expect(
                harness.session.targets.count == 3,
                "frame \(number) registered \(harness.session.targets.count) of 3 destinations")
        }
    }

    @Test("A drop on a served frame reaches the destination's action")
    func servedDestinationStillAcceptsADrop() {
        let harness = DropLoopHarness()
        let tally = DropTally()
        harness.frame(Self.page(tally))
        let served = harness.servedFrame(Self.page(tally), 2)

        let spot = dropCell(of: "bravo", in: served)
        #expect(spot != nil, "the middle destination is not on screen")
        guard let spot else { return }
        let took = harness.drop("cargo", atX: spot.x, y: spot.y)
        #expect(took, "the served destination refused the drop")
        #expect(tally.dropped == ["bravo←cargo"], "the drop did not reach the action")
    }

    /// The recording itself, pinned by kind: the target is journalled beside
    /// the handler it accompanies, and in the order the walk made them. A
    /// registration that stopped being recorded would leave the two tests above
    /// passing on a subtree that had simply stopped being stored.
    @Test("A drop destination records its handler and its drop target, in that order")
    func recordsBothOfItsRegistrations() {
        let harness = DropLoopHarness()
        let journal = harness.tui.renderCache.effectJournal
        let start = journal.beginRecording()
        harness.frame(DropCard(title: "alpha", tally: DropTally()))
        let kinds = Array(journal.entries(since: start)).map(\.kind.name)
        journal.endRecording()
        #expect(kinds == ["mouseHandler", "dropTarget"])
    }

    /// The same class, reached through a container rather than a modifier: a
    /// `List` writes to all three registries, and a memoized one wrote to none
    /// of them.
    @Test("A served List keeps its row drop target, its reorder host and its auto-scroll zone")
    func servedListKeepsAllThreeRegistrations() {
        let harness = DropLoopHarness()
        let page = VStack {
            Text("ahead").focusable()
            ListCard(title: "rows").equatable()
        }
        harness.frame(page)
        #expect(harness.session.targets.count == 1, "frame 1 registered the row drop target")
        #expect(harness.session.reorderHosts.count == 1, "frame 1 registered the reorder host")
        #expect(harness.session.autoScrollZones.count == 1, "frame 1 registered the zone")

        for number in 2...3 {
            harness.servedFrame(page, number)
            #expect(
                harness.session.targets.count == 1,
                "frame \(number) lost the served List's row drop target")
            #expect(
                harness.session.reorderHosts.count == 1,
                "frame \(number) lost the served List's reorder host")
            #expect(
                harness.session.autoScrollZones.count == 1,
                "frame \(number) lost the served List's auto-scroll zone")
        }
    }

    /// The shape an app actually writes, and the one the `Example`'s
    /// Drag Auto-scroll demo is: no `.equatable()` anywhere, just a
    /// `.dropDestination` on a `ForEach` row. The row memo stores on the
    /// second identical frame and serves from the third, which is where the
    /// targets used to go.
    @Test("A ForEach row's drop destination survives the frame its row memo starts serving")
    func foreachRowDestinationsSurviveTheRowMemo() {
        let harness = DropLoopHarness()
        let page = List {
            ForEach(1...3, id: \.self) { index in
                HStack {
                    Text("Folder \(index)")
                    Spacer()
                }
                .dropDestination(for: String.self) { _, _ in true }
            }
        }
        .frame(width: 24, height: 6)

        // Three frames, because the row memo needs two to store and the third
        // is the first one served. Asserted on every frame rather than the
        // last: which frame first serves is the row memo's business, and the
        // answer has to be three targets on all of them either way.
        for number in 1...3 {
            harness.frame(page)
            #expect(
                harness.session.targets.count == 3,
                "frame \(number) registered \(harness.session.targets.count) of 3 row destinations")
        }
        #expect(harness.cache.stats.hits > 0, "no row was ever served, so this proves nothing")
    }

    @Test("A served ScrollView keeps its auto-scroll zone")
    func servedScrollViewKeepsItsZone() {
        let harness = DropLoopHarness()
        let page = VStack {
            Text("ahead").focusable()
            ScrollCard(title: "viewport").equatable()
        }
        harness.frame(page)
        #expect(harness.session.autoScrollZones.count == 1, "frame 1 registered the zone")

        for number in 2...3 {
            harness.servedFrame(page, number)
            #expect(
                harness.session.autoScrollZones.count == 1,
                "frame \(number) lost the served ScrollView's auto-scroll zone")
        }
    }
}
