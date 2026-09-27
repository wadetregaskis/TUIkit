//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GeometryReaderTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

/// The sidebar's `@State`, handed back by its body so a test can flip it
/// between frames — a "show sidebar" toggle.
@MainActor
private final class SidebarHandle {
    var binding: Binding<Bool>?
    func flip() { binding?.wrappedValue.toggle() }
}

/// A sidebar 4 cells wide, or 30 once widened by its own `@State`.
private struct ReaderSidebar: View {
    @State private var wide: Bool
    let handle: SidebarHandle

    init(wide: Bool, handle: SidebarHandle) {
        _wide = State(initialValue: wide)
        self.handle = handle
    }

    var body: some View {
        handle.binding = $wide
        return Text(String(repeating: "s", count: wide ? 30 : 4))
    }
}

/// A sidebar beside a reader whose rows print the reader's width. The rows sit
/// in a stack 20 cells wide, so each is memoized by its element and offered the
/// same 20 cells whatever size the reader has: nothing a memo keys on moves
/// when the reader does.
private struct ReaderRowsPage: App {
    let wide: Bool
    let handle: SidebarHandle

    init() { self.init(wide: false, handle: SidebarHandle()) }

    init(wide: Bool, handle: SidebarHandle) {
        self.wide = wide
        self.handle = handle
    }

    var body: some Scene {
        WindowGroup {
            HStack(alignment: .top, spacing: 0) {
                ReaderSidebar(wide: wide, handle: handle)
                GeometryReader { proxy in
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<3, id: \.self) { index in
                            Text(verbatim: "row \(index) in \(proxy.size.width)")
                        }
                    }
                    .frame(width: 20, alignment: .leading)
                }
            }
        }
    }
}

/// One frame of `app`, a sixtieth of a second after the one before.
@MainActor
private func step<A: App>(_ app: HeadlessApp<A>, _ frame: Int) {
    app.frame(atNanos: 1_000_000_000 + Int64(frame) * 16_666_667)
}

/// `GeometryReader` closes the one gap an app could not work around: reading the
/// space a view was actually given, and branching on it.
@MainActor
@Suite("GeometryReader")
struct GeometryReaderTests {

    /// Widening the sidebar beside the reader is a `@State` write. It clears
    /// the sidebar and what contains it, and nothing inside the reader,
    /// because the reader's content does not read the sidebar's state. But it
    /// narrows the reader from 56 cells to 30, and the rows read that size.
    /// Each row is memoized by its element and offered the same 20 cells as
    /// before, so each was served as it was drawn at 56.
    @Test("Rows under a GeometryReader that read its size are drawn for the size it has now")
    func rowsReadingTheProxyFollowIt() {
        let handle = SidebarHandle()
        let app = HeadlessApp(ReaderRowsPage(wide: false, handle: handle), width: 60, height: 16)
        for frame in 0..<3 { step(app, frame) }
        #expect(app.screen.contains { $0.contains("row 2 in 56") }, "precondition: the rows drew the reader's width")
        handle.flip()
        for frame in 3..<5 { step(app, frame) }

        let control = HeadlessApp(ReaderRowsPage(wide: true, handle: SidebarHandle()), width: 60, height: 16)
        for frame in 0..<5 { step(control, frame) }
        #expect(app.screen.contains { $0.contains("row 2 in 30") }, "the rows kept the reader's old width")
        #expect(app.screen == control.screen)
    }

    /// The reader notes the size it hands its content once a pass, as a
    /// modifier notes the value it applies, and clears its content only when
    /// that size moves: a reader that holds still costs its memos nothing.
    @Test("A reader clears its content once when its size moves, and not when it holds")
    func aReaderClearsOnlyWhenItMoves() {
        let handle = SidebarHandle()
        let app = HeadlessApp(ReaderRowsPage(wide: false, handle: handle), width: 60, height: 16)
        for frame in 0..<3 { step(app, frame) }
        let settled = app.renderCache.stats.subtreeClears
        for frame in 3..<6 { step(app, frame) }
        #expect(app.renderCache.stats.subtreeClears == settled, "a reader whose size held cleared")

        handle.flip()
        step(app, 6)
        #expect(
            app.renderCache.stats.subtreeClears == settled + 2,
            "expected the sidebar's clear and the reader's, once each")
        step(app, 7)
        #expect(app.renderCache.stats.subtreeClears == settled + 2, "the reader cleared again at the same size")
    }

    @Test("The proxy reports the offered size")
    func proxyReportsOfferedSize() {
        let context = makeRenderContext(width: 30, height: 8)
        var seen: CellSize?
        _ = renderToBuffer(
            GeometryReader { proxy in
                seen = proxy.size
                return Text("x")
            }, context: context)

        #expect(seen == CellSize(width: 30, height: 8))
    }

    @Test("Content can branch on the size it is given")
    func contentBranchesOnSize() {
        // The whole point of the type: the same view, two widths, two layouts.
        func render(width: Int) -> FrameBuffer {
            renderToBuffer(
                GeometryReader { proxy in
                    if proxy.size.width >= 20 {
                        Text("wide")
                    } else {
                        Text("narrow")
                    }
                }, context: makeRenderContext(width: width, height: 3))
        }

        #expect(render(width: 30).lines[0].stripped.hasPrefix("wide"))
        #expect(render(width: 10).lines[0].stripped.hasPrefix("narrow"))
    }

    @Test("The reader fills the space it was offered")
    func readerFillsItsProposal() {
        // SwiftUI's rule, and the one that makes the reported size meaningful:
        // the size is the container's, not the content's. A one-cell Text must
        // not shrink the reader around itself.
        let buffer = renderToBuffer(
            GeometryReader { _ in Text("x") },
            context: makeRenderContext(width: 12, height: 4))

        #expect(buffer.width == 12)
        #expect(buffer.lines.count == 4)
    }

    @Test("A frame around the reader bounds it")
    func frameBoundsTheReader() {
        let context = makeRenderContext(width: 40, height: 10)
        var seen: CellSize?
        _ = renderToBuffer(
            GeometryReader { proxy in
                seen = proxy.size
                return Text("x")
            }
            .frame(width: 15, height: 4),
            context: context)

        // Reads the frame's size, not the terminal's — the documented way to
        // bound a greedy reader.
        #expect(seen?.width == 15)
        #expect(seen?.height == 4)
    }

    @Test("Measuring reports the proposal without building the content")
    func measureIsGreedyAndDoesNotBuild() {
        var built = 0
        let view = GeometryReader { _ -> Text in
            built += 1
            return Text("x")
        }
        let size = measureChild(
            view,
            proposal: ProposedSize(width: 25, height: 6),
            context: makeRenderContext(width: 40, height: 10))

        #expect(size.width == 25)
        #expect(size.height == 6)
        #expect(size.isWidthFlexible)
        #expect(size.isHeightFlexible)
        // Building would need a proxy, which would need the size being computed.
        #expect(built == 0)
    }

    @Test("frame(in: .local) is the reader's own rectangle")
    func localFrame() {
        let proxy = GeometryProxy(width: 20, height: 5)
        let frame = proxy.frame(in: .local)
        #expect(frame == CellRect(x: 0, y: 0, width: 20, height: 5))
        #expect(frame.maxX == 20)
        #expect(frame.maxY == 5)
    }

    @Test("A global frame says so when it does not know the position")
    func globalFrameIsHonestAboutNotKnowing() {
        // Most readers render into a buffer that is composed into its parent
        // afterwards, so there is no screen position to report. Falling back to
        // the local frame is the least-wrong answer; `hasGlobalPosition` is how
        // a caller tells the difference instead of being quietly misled.
        let unpositioned = GeometryProxy(width: 20, height: 5)
        #expect(!unpositioned.hasGlobalPosition)
        #expect(unpositioned.frame(in: .global) == unpositioned.frame(in: .local))

        let positioned = GeometryProxy(width: 20, height: 5, globalOrigin: (x: 4, y: 2))
        #expect(positioned.hasGlobalPosition)
        #expect(positioned.frame(in: .global) == CellRect(x: 4, y: 2, width: 20, height: 5))
        #expect(positioned.frame(in: .local).x == 0)
    }

    @Test("A negative proposal is clamped before the proxy ever sees it")
    func degenerateSizes() {
        // The negative-size class: chrome subtractions reach zero — and, when
        // a clamp is missing, go past it — on a tiny terminal, and every
        // container has to survive it.
        //
        // Read out of the CLOSURE, not off the buffer. What the reader hands
        // its content cannot be recovered downstream: at width 0 the content's
        // own text is truncated to "" (`String.truncatedToWidth` returns empty
        // below 1), so `Text("\(proxy.size.width)")` draws the same nothing for
        // 0 as for -2, and the reader's padding guard `buffer.width < width` is
        // false against a negative width so it returns early without trapping.
        // Asserting anything about the buffer — including a `>= 0` bound, or an
        // exact `width == 0` — therefore passes with the clamps deleted.
        var seen: CellSize?
        let buffer = renderToBuffer(
            GeometryReader { proxy in
                seen = proxy.size
                return Text("\(proxy.size.width)")
            },
            context: makeRenderContext(width: -2, height: -1))

        #expect(seen == CellSize(width: 0, height: 0))
        // And at zero the content is truncated away entirely, as documented:
        // the reader fills its (empty) proposal rather than drawing the digits.
        #expect(buffer.width == 0)
        #expect(buffer.lines.allSatisfy { $0.stripped.isEmpty })
    }
}
