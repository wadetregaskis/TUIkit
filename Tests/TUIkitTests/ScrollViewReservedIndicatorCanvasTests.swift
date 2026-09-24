//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollViewReservedIndicatorCanvasTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitImage

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// Under `.scrollIndicators(.visible, axes: .vertical)` +
/// `.scrollIndicatorStyle(.text)` a `ScrollView` reserves the "N more" pair
/// OUTSIDE its content window, two lines shorter than the viewport. Content that
/// fills whatever it is given — a `Spacer`, a `.frame(maxHeight: .infinity)` —
/// must fill that window, and not the viewport; and content sized FROM the
/// window — an image fitted to it — must be measured at it.
///
/// Neither held when the scroll view also scrolled horizontally with an
/// `.automatic` bar. That configuration measures the content to decide the
/// horizontal bar, and the measure was taken at the viewport less the bar's row
/// but NOT less the two reserved lines; its extents were then handed to the
/// render as already settled, while the render published the shorter window.
/// So the canvas was two lines taller than the window it scrolled through — the
/// bottom of a `Spacer` layout sat on a line the reader had to scroll to — and a
/// picture was measured two lines taller, so wider, than it was drawn: a bar was
/// reserved for columns that never existed.
@MainActor
@Suite("Reserved indicator lines leave the content its real canvas")
struct ScrollViewReservedIndicatorCanvasTests {
    private static let width = 30

    /// Two frames, driven the way the run loop drives them; the second is the
    /// one asserted on, so nothing here is a first-frame artefact.
    private func settledLines<V: View>(_ view: V, height: Int) -> [String] {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: Self.width, availableHeight: height,
            environment: environment, tuiContext: tuiContext)
        var buffer = FrameBuffer()
        for _ in 0..<2 {
            tuiContext.preferences.beginRenderPass()
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            buffer = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
        }
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    /// Scrolls both ways, the horizontal bar left to decide for itself — the
    /// one arrangement that measured the content before the reservation — and
    /// the vertical indicator the always-drawn "N more" pair.
    private func twoAxis(_ content: some View) -> some View {
        ScrollView([.horizontal, .vertical]) { content }
            .scrollIndicators(.visible, axes: .vertical)
            .scrollIndicators(.automatic, axes: .horizontal)
            .scrollIndicatorStyle(.text)
    }

    /// The count an indicator line reports: "▼ 2 more lines below" → 2.
    private func count(in line: String?, arrow: Character) -> Int? {
        guard let line, line.first == arrow else { return nil }
        return Int(line.dropFirst().drop { $0 == " " }.prefix { $0.isNumber })
    }

    @Test("A Spacer spreads its layout over the content window, not the viewport")
    func spacerFillsTheWindow() {
        // Eight lines: "▲ …", six content lines, "▼ …".
        let drawn = settledLines(
            twoAxis(
                VStack(alignment: .leading, spacing: 0) {
                    Text("top")
                    Spacer()
                    Text("bottom")
                }),
            height: 8)
        #expect(drawn.count == 8, "\(drawn)")
        #expect(drawn[1] == "top", "the first content line: \(drawn)")
        #expect(drawn[6] == "bottom", "the last content line, directly above ▼: \(drawn)")
        #expect(count(in: drawn.last, arrow: "▼") == 0, "nothing to scroll to: \(drawn)")
    }

    @Test("A frame with an unbounded height fills the content window, not the viewport")
    func infiniteFrameFillsTheWindow() {
        let drawn = settledLines(
            twoAxis(Text("floor").frame(maxHeight: .infinity, alignment: .bottom)),
            height: 8)
        #expect(drawn.count == 8, "\(drawn)")
        #expect(drawn[6] == "floor", "bottom-aligned on the last content line: \(drawn)")
        #expect(count(in: drawn.last, arrow: "▼") == 0, "nothing to scroll to: \(drawn)")
    }

    /// The control for the loaded case below. A placeholder is exactly as wide
    /// as the viewport at any height, and is drawn to the window the render
    /// publishes; the content height is what was DRAWN, not the canvas, so the
    /// taller canvas cost it nothing. It held before the fix and must still.
    @Test("An image fitted to the viewport leaves no blank lines to scroll into")
    func viewportImageFillsTheWindow() {
        let drawn = settledLines(
            twoAxis(Image(.file("/no/such/x.png")).imageFitTarget(.viewport)),
            height: 8)
        #expect(drawn.count == 8, "\(drawn)")
        #expect(count(in: drawn.first, arrow: "▲") == 0, "\(drawn)")
        #expect(count(in: drawn.last, arrow: "▼") == 0, "nothing below the image: \(drawn)")
    }

    /// With the horizontal bar taking a row as well: the reservation's height
    /// follows the bar, round by round, so the measure that added the bar and
    /// the one after it must both be taken at what is left.
    @Test("Under a horizontal bar too, a Spacer fills the window both leave")
    func spacerFillsTheWindowUnderAHorizontalBar() {
        // Nine lines: "▲ …", six content lines, "▼ …", the horizontal bar.
        let drawn = settledLines(
            twoAxis(
                VStack(alignment: .leading, spacing: 0) {
                    Text(String(repeating: "w", count: 50))
                    Spacer()
                    Text("bottom")
                }),
            height: 9)
        #expect(drawn.count == 9, "\(drawn)")
        #expect(count(in: drawn[7], arrow: "▼") == 0, "nothing to scroll to: \(drawn)")
        #expect(drawn[6] == "bottom", "the last content line, above ▼ and the bar: \(drawn)")
    }

    /// Too short for the indicator lines, they are not drawn, and nothing is
    /// reserved for them: the probe must measure at the whole height left
    /// above the bar, or bottom-aligned content lands a line too high.
    /// (A probe that ignored the floor passed every other test here.)
    @Test("Too short to draw the indicator lines, the content keeps the whole height")
    func noReservationUnderTheFloor() {
        let drawn = settledLines(
            twoAxis(Text(String(repeating: "w", count: 50)).frame(maxHeight: .infinity, alignment: .bottom)),
            height: 3)
        #expect(drawn.count == 3, "\(drawn)")
        #expect(drawn[1].hasPrefix("www"), "bottom-aligned on the line above the bar: \(drawn)")
    }

    // MARK: A loaded picture

    /// Records the identity it is drawn at, and draws `_ImageCore` there — so a
    /// test can seat a loaded picture in the image's phase box, which is keyed on
    /// that identity (`LoadedImageGeometryTests`' recipe, one level down). Both
    /// halves forward at the probe's OWN identity, so the measure and the render
    /// read the same box.
    private struct ImageIdentityProbe: View, Renderable, Layoutable {
        final class Seen { var identity: ViewIdentity? }
        let source: ImageSource
        let seen: Seen
        var body: Never { fatalError("ImageIdentityProbe renders via Renderable") }

        func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
            _ImageCore(source: source).sizeThatFits(proposal: proposal, context: context)
        }

        func renderToBuffer(context: RenderContext) -> FrameBuffer {
            seen.identity = context.identity
            return _ImageCore(source: source).renderToBuffer(context: context)
        }
    }

    /// Effects off, as `ViewRenderer` builds one for a snapshot: nothing may start
    /// a real load over the phase this seats.
    private static func snapshotContext() -> TUIContext {
        TUIContext(
            lifecycle: LifecycleManager(firesEffects: false),
            keyEventDispatcher: KeyEventDispatcher(),
            preferences: PreferenceStorage(),
            stateStorage: StateStorage())
    }

    /// `frames` frames of `view` through `tui`, the last one's lines returned.
    private func frames<V: View>(_ view: V, height: Int, tui: TUIContext, count: Int) -> [String] {
        let focusManager = FocusManager()
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tui)
        environment.imageCellAspect = 2.0
        let context = RenderContext(
            availableWidth: Self.width, availableHeight: height,
            environment: environment, tuiContext: tui, identity: ViewIdentity(path: "Root"))
        var buffer = FrameBuffer()
        for _ in 0..<count {
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            buffer = KittyGraphics.withSupport(false) { renderToBuffer(view, context: context) }
            focusManager.endRenderPass()
            tui.stateStorage.endRenderPass()
            tui.renderCache.removeInactive()
        }
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    /// The bar is decided by the width the picture measures to, and a picture
    /// fitted to the viewport is as wide as the viewport is TALL lets it be. So a
    /// measure at the wrong height is a wrong bar, not only a wrong canvas: here
    /// the picture is 32 columns at the 16 lines the measure used to offer and
    /// 28 at the 14 the window has, in a 30-column viewport. A bar was reserved
    /// for columns that were never drawn, and took a row from the picture.
    @Test("A loaded picture fitted to the window reserves no horizontal bar it does not overflow")
    func loadedImageBarFollowsTheWindow() throws {
        // 20 × 40 pixels on a cell twice as tall as it is wide: square in cells.
        let fixture = try BitmapFixture(width: 20, height: 40)
        let image = try PlatformImageLoader().loadImage(from: fixture.path)
        let seen = ImageIdentityProbe.Seen()
        let view = twoAxis(ImageIdentityProbe(source: .file(fixture.path), seen: seen))
            .imageFitTarget(.viewport)
            .imageZoom(2)

        // Where the image's box lives, found by drawing it once; then seated,
        // loaded, in a context of its own, before its first frame there.
        _ = frames(view, height: 16, tui: Self.snapshotContext(), count: 1)
        let identity = try #require(seen.identity, "the probe was never drawn")
        let tui = Self.snapshotContext()
        let phase: StateBox<ImageLoadingPhase> = tui.stateStorage.storage(
            for: StateStorage.StateKey(identity: identity, propertyIndex: 0), default: .loading)
        phase.value = .success(image)

        let drawn = frames(view, height: 16, tui: tui, count: 2)
        #expect(drawn.count == 16, "\(drawn)")
        #expect(!drawn.contains { $0.hasPrefix("◀") }, "no horizontal bar: \(drawn)")
        // 28 rows of picture (14, zoomed twice) through a 14-line window.
        #expect(count(in: drawn.last, arrow: "▼") == 14, "the picture's own height below: \(drawn)")
    }
}
