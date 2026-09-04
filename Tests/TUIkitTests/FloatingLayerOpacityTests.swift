//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FloatingLayerOpacityTests.swift
//
//  Every surface that FLOATS over the page must be opaque.
//
//  A menu, a dialog, a toast and a popover are not translucent windows: what
//  is behind them is not meant to be legible through them, and a page whose
//  own background differs from the terminal's would otherwise show through
//  wherever the floating content happened not to paint. Before 590e71a4 they
//  were all opaque by ACCIDENT — compositing replaced the base cell under
//  every overlay cell, field included, so a layer that named no background of
//  its own still punched the page's away. That commit made a cell's glyph and
//  its field two separate statements (so `ZStack { Color.red; Text("hi") }`
//  draws the letters ON the red), which is right, and left every floating
//  surface relying on the accident showing the page through its blanks.
//
//  So the invariant is stated here rather than left to each presenter: render
//  each presentation over a page painted a colour nothing else uses, composite
//  it, and read the background of every cell the layer covers. None of them may
//  be the page's.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Floating layers are opaque")
struct FloatingLayerOpacityTests {

    // MARK: - The page underneath

    /// A colour no palette, theme or blend produces, so a cell wearing it can
    /// only have come from the page — which is what every assertion here means
    /// by "the page showed through".
    private static let pageBackground = Color.rgb(255, 0, 255)
    private static let pageEscape = "48;2;255;0;255"

    private func harness(width: Int = 60, height: Int = 24) -> (TUIContext, RenderContext) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        return (
            tui,
            RenderContext(
                availableWidth: width, availableHeight: height, environment: environment,
                tuiContext: tui)
        )
    }

    /// One full frame: the buffer as rendered (still carrying its pending
    /// layers) and the same buffer composited exactly as `RenderLoop`
    /// composites it.
    ///
    /// Both from ONE pass. Re-rendering to recover the layer afterwards looks
    /// equivalent and is not: an open menu's state lives in `StateStorage`
    /// against the render pass, so a second render outside the pass draws the
    /// menu closed and reports no layer at all.
    private func frame(_ view: some View, tui: TUIContext, context: RenderContext)
        -> (pending: FrameBuffer, composited: FrameBuffer)
    {
        tui.mouseEventDispatcher.beginRenderPass()
        tui.keyEventDispatcher.clearHandlers()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        context.environment.focusManager?.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        let composited = buffer.compositingOverlays(
            maxWidth: context.availableWidth, maxHeight: context.availableHeight,
            palette: context.environment.palette)
        tui.mouseEventDispatcher.setRegions(composited.hitTestRegions)
        tui.stateStorage.endRenderPass()
        context.environment.focusManager?.endRenderPass()
        return (buffer, composited)
    }

    /// A layer nested in another layer's content is lifted only when its host
    /// composites. Drawn a PASS later, it came after everything already on
    /// screen — so an alert raised from inside a sheet dimmed a `.notification`
    /// toast that the level order declares topmost.
    @Test("A layer lifted from inside another layer still respects the level order")
    func nestedLayerKeepsTheLevelOrder() {
        let palette = SystemPalette.green
        var page = FrameBuffer(lines: Array(repeating: String(repeating: " ", count: 20), count: 6))
        var sheet = FrameBuffer(lines: ["SHEET"])
        sheet.overlays = [
            OverlayLayer(
                offsetX: 0, offsetY: 0, content: FrameBuffer(lines: ["ALERT"]),
                level: .alert, dimsBackground: true)
        ]
        page.overlays = [
            OverlayLayer(offsetX: 0, offsetY: 2, content: sheet, level: .modal, dimsBackground: true),
            OverlayLayer(
                offsetX: 10, offsetY: 0,
                content: FrameBuffer(lines: [ANSIRenderer.colorize("TOAST", foreground: .rgb(1, 2, 3))]),
                level: .notification),
        ]
        let composited = page.compositingOverlays(maxWidth: 20, maxHeight: 6, palette: palette)
        let toastRow = composited.lines[0]
        #expect(toastRow.stripped.contains("TOAST"))
        #expect(
            toastRow.contains("38;2;1;2;3"),
            "the toast was dimmed by a layer lifted after it: \(toastRow.debugDescription)")
        #expect(composited.lines.joined().stripped.contains("ALERT"), "the nested alert is drawn")
    }

    // MARK: - Reading a composited line back

    /// The background each visible cell of `line` is painted with — `nil` where
    /// the cell names none and would therefore take the terminal's own.
    ///
    /// A cell-by-cell walk rather than a scan for escapes: the question is what
    /// is IN FORCE at a cell, and an escape earlier in the line answers for
    /// every cell after it until the next one.
    private func cellBackgrounds(_ line: String) -> [String?] {
        var state = SGRState()
        var backgrounds: [String?] = []
        var rest = Substring(line)
        while let next = rest.first {
            if next == "\u{1B}" {
                guard let end = rest.firstIndex(of: "m") else { break }
                state.apply(String(rest[rest.startIndex...end]))
                rest = rest[rest.index(after: end)...]
                continue
            }
            let cells = next.terminalWidth
            backgrounds.append(state.namesBackground ? state.renderedBackground : nil)
            // A wide character owns both its columns, and both are painted by
            // the same escape.
            if cells > 1 { backgrounds.append(contentsOf: Array(repeating: backgrounds.last!, count: cells - 1)) }
            rest = rest.dropFirst()
        }
        return backgrounds
    }

    /// Every cell of `frame` whose background is the page's — i.e. every cell
    /// the floating layer failed to cover.
    private func showThrough(_ frame: FrameBuffer, rows: Range<Int>, columns: Range<Int>) -> [(Int, Int)] {
        var leaks: [(Int, Int)] = []
        for row in rows where row < frame.lines.count {
            let backgrounds = cellBackgrounds(frame.lines[row])
            for column in columns where column < backgrounds.count {
                if backgrounds[column]?.contains(Self.pageEscape) == true {
                    leaks.append((row, column))
                }
            }
        }
        return leaks
    }

    /// A page that paints every cell, so anything showing through is unambiguous.
    @ViewBuilder
    private func page(_ overlaid: some View) -> some View {
        // Top-leading, so the trigger sits at a cell the tests can name.
        // Centred (the ZStack default) put the Picker at column 27 of row 11
        // and every click in this file missed it.
        ZStack(alignment: .topLeading) {
            Color.rgb(255, 0, 255)
            overlaid
        }
    }

    // MARK: - The presentations

    /// A `Picker`'s drop-down: the one the report came in about.
    @Test("A Picker's drop-down is opaque")
    func pickerDropdown() throws {
        let (tui, context) = harness()
        let view = page(
            VStack {
                Picker("Choose", selection: Binding<Int>.constant(0)) {
                    Text("Apple").tag(0)
                    Text("Banana").tag(1)
                    Text("Cherry").tag(2)
                }
            })
        _ = frame(view, tui: tui, context: context)
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 10, y: 0))
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 10, y: 0))
        try expectOpaqueLayer(frame(view, tui: tui, context: context), context: context)
    }

    /// A pop-up `Menu`.
    @Test("A pop-up Menu is opaque")
    func menuPopup() throws {
        let (tui, context) = harness()
        let view = page(
            VStack {
                Menu("Actions") {
                    Button("Rename") {}
                    Button("Delete", role: .destructive) {}
                }
            })
        _ = frame(view, tui: tui, context: context)
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: 0))
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: 0))
        try expectOpaqueLayer(frame(view, tui: tui, context: context), context: context)
    }

    /// A `.contextMenu`, opened with a right-click.
    @Test("A context menu is opaque")
    func contextMenu() throws {
        let (tui, context) = harness()
        let view = page(
            VStack {
                Text("Right-click me").contextMenu {
                    Button("Cut") {}
                    Button("Copy") {}
                }
            })
        _ = frame(view, tui: tui, context: context)
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .right, phase: .pressed, x: 3, y: 0))
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .right, phase: .released, x: 3, y: 0))
        try expectOpaqueLayer(frame(view, tui: tui, context: context), context: context)
    }

    /// A `.popover`.
    @Test("A popover is opaque")
    func popover() throws {
        let (tui, context) = harness()
        let view = page(
            VStack {
                Text("anchor")
                    .popover(isPresented: .constant(true)) {
                        Text("Popover body")
                    }
            })
        try expectOpaqueLayer(frame(view, tui: tui, context: context), context: context)
    }

    /// An `.alert`.
    @Test("An alert is opaque")
    func alert() throws {
        let (tui, context) = harness()
        let view = page(
            Text("page")
                .alert("Careful", isPresented: .constant(true)) {
                    Button("OK") {}
                })
        try expectOpaqueLayer(frame(view, tui: tui, context: context), context: context)
    }

    /// A `.sheet` hosting a `Dialog`.
    @Test("A sheet is opaque")
    func sheet() throws {
        let (tui, context) = harness()
        let view = page(
            Text("page")
                .sheet(isPresented: .constant(true)) {
                    Dialog(title: "Details") {
                        Text("Body")
                    }
                })
        try expectOpaqueLayer(frame(view, tui: tui, context: context), context: context)
    }

    /// A `.confirmationDialog`.
    @Test("A confirmation dialog is opaque")
    func confirmationDialog() throws {
        let (tui, context) = harness()
        let view = page(
            Text("page")
                .confirmationDialog("Delete this?", isPresented: .constant(true)) {
                    Button("Delete", role: .destructive) {}
                })
        try expectOpaqueLayer(frame(view, tui: tui, context: context), context: context)
    }

    // MARK: - The shared assertion

    /// Reads every cell of the layer's footprint out of the composited frame,
    /// and fails naming the cells where the page showed through.
    private func expectOpaqueLayer(
        _ rendered: (pending: FrameBuffer, composited: FrameBuffer), context: RenderContext,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let (pending, composited) = rendered
        let layer = try #require(
            pending.overlays.first, "no floating layer was emitted", sourceLocation: sourceLocation)
        let placed = layer.placed(maxWidth: context.availableWidth, maxHeight: context.availableHeight)
        let leaks = showThrough(
            composited,
            rows: placed.y..<(placed.y + placed.content.height),
            columns: placed.x..<(placed.x + placed.content.width))
        let leakList =
            leaks.prefix(8).map { "(row \($0.0), col \($0.1))" }.joined(separator: ", ")
            + (leaks.count > 8 ? " and \(leaks.count - 8) more" : "")
        #expect(
            leaks.isEmpty, "the page shows through at \(leakList)", sourceLocation: sourceLocation)
    }

    /// A toast. Notifications stack, so this one posts two: the gap BETWEEN
    /// two toasts is page, and only the toasts themselves are surface — which
    /// is why the assertion reads the toasts' own rows rather than the layer's
    /// bounding box.
    @Test("A notification toast is opaque")
    func notification() throws {
        let (tui, base) = harness()
        let service = NotificationService()
        service.post("First toast")
        service.post("Second toast")
        var environment = base.environment
        environment.notificationService = service
        let context = RenderContext(
            availableWidth: base.availableWidth, availableHeight: base.availableHeight,
            environment: environment, tuiContext: tui)
        let rendered = frame(page(Text("page")).notificationHost(), tui: tui, context: context)
        let layer = try #require(rendered.pending.overlays.first, "no toast layer was emitted")
        let placed = layer.placed(
            maxWidth: context.availableWidth, maxHeight: context.availableHeight)
        // Only the rows the toasts actually drew on — a blank row between two
        // toasts is not a surface and must keep showing the page.
        for (row, line) in placed.content.lines.enumerated() where line.stripped.contains(where: { !$0.isWhitespace }) {
            let leaks = showThrough(
                rendered.composited,
                rows: (placed.y + row)..<(placed.y + row + 1),
                columns: placed.x..<(placed.x + placed.content.width))
            #expect(leaks.isEmpty, "the page shows through toast row \(row) at \(leaks.map(\.1))")
        }
    }

    /// The two layers `WindowGroup.renderScene` makes itself — a lifted drag
    /// preview and its return flight — rather than a presentation. They took
    /// `isOpaque`'s default silently and no test rendered either; a row being
    /// carried is a card, and the page must not show through it.
    @Test("A lifted drag preview is opaque")
    func dragPreview() throws {
        let (tui, context) = harness()
        let session = try #require(context.environment.dragAndDropSession)
        session.beginFrame()
        session.lastAbsoluteEvent = MouseEvent(button: .left, phase: .pressed, x: 4, y: 3)
        session.lastAbsoluteEvent = MouseEvent(button: .left, phase: .dragged, x: 12, y: 7)
        session.begin(payload: "row", preview: FrameBuffer(lines: ["ROW", "ROW"]), grabX: 0, grabY: 0)

        let scene = WindowGroup { page(Text("page")) }
        let buffer = scene.renderScene(context: context)
        let layer = try #require(buffer.overlays.first, "no preview layer was emitted")
        #expect(layer.isOpaque, "a carried row is a card")
        let composited = buffer.compositingOverlays(
            maxWidth: context.availableWidth, maxHeight: context.availableHeight,
            palette: context.environment.palette)
        let placed = layer.placed(maxWidth: context.availableWidth, maxHeight: context.availableHeight)
        let leaks = showThrough(
            composited, rows: placed.y..<(placed.y + placed.content.height),
            columns: placed.x..<(placed.x + placed.content.width))
        #expect(leaks.isEmpty, "the page shows through the preview at \(leaks)")
        _ = tui
    }

    // MARK: - The other side of the rule

    /// `.offset` and `.position` displace a view; they do not wrap it in a
    /// surface. Whatever makes the presentations opaque must leave these two
    /// alone, or every offset label grows an opaque box the size of its line.
    @Test("Displaced content is not given a surface", arguments: [true, false])
    func displacedContentStaysTransparent(byOffset: Bool) throws {
        let (tui, context) = harness()
        let moved: AnyView =
            byOffset
            ? AnyView(Text("hi").offset(x: 4, y: 2))
            : AnyView(Text("hi").position(x: 6, y: 3))
        let rendered = frame(page(moved), tui: tui, context: context)
        let layer = try #require(rendered.pending.overlays.first, "nothing was displaced")
        let placed = layer.placed(
            maxWidth: context.availableWidth, maxHeight: context.availableHeight)
        // The page is EXPECTED to show through here — that is the whole point
        // of the negative case, so the assertion is the mirror of the others.
        let leaks = showThrough(
            rendered.composited,
            rows: placed.y..<(placed.y + placed.content.height),
            columns: placed.x..<(placed.x + placed.content.width))
        #expect(!leaks.isEmpty, "displaced text was given a background it never asked for")
    }

    /// Painting happens BEFORE the blend, so a faded layer still fades.
    ///
    /// The ordering is the whole risk in making layers opaque: paint after
    /// `resolvingOpacity` and the surface colour is stamped over the blend,
    /// freezing every translucent layer — a toast on its way out, a popover
    /// fading in — fully opaque for its whole life. Paint before, and the
    /// opacity has an opaque background to fade FROM, which is what a window
    /// fading over a page looks like.
    @Test("A faded floating layer still blends with the page")
    func fadedLayerStillBlends() throws {
        let (tui, context) = harness()
        let opaque = frame(
            page(
                Text("anchor").popover(isPresented: .constant(true)) { Text("Body") }),
            tui: tui, context: context)
        let (tui2, context2) = harness()
        let faded = frame(
            page(
                Text("anchor")
                    .popover(isPresented: .constant(true)) { Text("Body") }
                    .opacity(0.5)),
            tui: tui2, context: context2)
        let layer = try #require(faded.pending.overlays.first)
        let placed = layer.placed(
            maxWidth: context2.availableWidth, maxHeight: context2.availableHeight)
        let row = placed.y + 1
        #expect(
            opaque.composited.lines[row] != faded.composited.lines[row],
            "the fade was stamped over: a half-transparent popover rendered identically to an opaque one")
        // …and it is a BLEND, not the page: the popover is still hiding what is
        // behind it, just less completely.
        let leaks = showThrough(
            faded.composited, rows: row..<(row + 1),
            columns: placed.x..<(placed.x + placed.content.width))
        #expect(leaks.isEmpty, "a 50% popover let the page through unblended at \(leaks.map(\.1))")
    }
}
