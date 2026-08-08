//  🖥️ TUIKit — Terminal UI Kit for Swift
//  GeometryReaderTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

/// `GeometryReader` closes the one gap an app could not work around: reading the
/// space a view was actually given, and branching on it.
@MainActor
@Suite("GeometryReader")
struct GeometryReaderTests {

    @Test("The proxy reports the offered size")
    func proxyReportsOfferedSize() {
        let context = makeRenderContext(width: 30, height: 8)
        var seen: ProxySize?
        _ = renderToBuffer(
            GeometryReader { proxy in
                seen = proxy.size
                return Text("x")
            }, context: context)

        #expect(seen == ProxySize(width: 30, height: 8))
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
        var seen: ProxySize?
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
        #expect(frame == ProxyRect(x: 0, y: 0, width: 20, height: 5))
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
        #expect(positioned.frame(in: .global) == ProxyRect(x: 4, y: 2, width: 20, height: 5))
        #expect(positioned.frame(in: .local).x == 0)
    }

    @Test("A zero-sized proposal does not crash or go negative")
    func degenerateSizes() {
        // The negative-size class: chrome subtractions reach zero on a tiny
        // terminal, and every container has to survive it.
        let buffer = renderToBuffer(
            GeometryReader { proxy in Text("\(proxy.size.width)") },
            context: makeRenderContext(width: 0, height: 0))
        #expect(buffer.width >= 0)
    }
}
