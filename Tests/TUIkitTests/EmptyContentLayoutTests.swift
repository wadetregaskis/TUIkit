//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EmptyContentLayoutTests.swift
//
//  What a stack gives content with nothing in it: a frame on a `nil`, on an
//  empty `Group`, on `EmptyView`, and an empty stack between two siblings.
//  SwiftUI's answers were measured with an `NSHostingView` probe and are
//  recorded in `Documentation/SwiftUI-compatibility.md` §3, beside the two
//  places TUIkit answers differently.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// The rows `view` draws, styling stripped, between an `A` and a `B`.
@MainActor
private func rows<V: View>(between view: V, spacing: Int) -> [String] {
    let context = makeRenderContext(width: 8, height: 12)
    let stack = VStack(alignment: .leading, spacing: spacing) {
        Text("A")
        view
        Text("B")
    }
    return renderToBuffer(stack, context: context).lines.map {
        $0.stripped.trimmingCharacters(in: .whitespaces)
    }
}

@MainActor
@Suite("Content with nothing in it, in a stack")
struct EmptyContentLayoutTests {
    private let absent: Text? = nil
    private let never = false

    /// SwiftUI: 32 points for the two texts, and 32 again with each of these.
    @Test("A frame on a nil or an empty Group keeps no rows, as in SwiftUI")
    func frameOnNothingKeepsNoRows() {
        #expect(rows(between: absent.frame(height: 5), spacing: 0) == ["A", "B"])
        #expect(
            rows(between: Group { if never { Text("x") } }.frame(height: 5), spacing: 0)
                == ["A", "B"])
    }

    /// SwiftUI: 82 points — the 32 and the frame's 50.
    @Test("A frame on a stack that is always there keeps its rows, as in SwiftUI")
    func frameOnAStackKeepsItsRows() {
        let slot = VStack(spacing: 0) { if never { Text("x") } }.frame(height: 5)
        #expect(rows(between: slot, spacing: 0) == ["A", "", "", "", "", "", "B"])
    }

    /// SwiftUI: 32 — a frame on `EmptyView` is as empty as one on a `nil`.
    /// TUIkit keeps the frame's minimum height: `EmptyView` is a view here, not
    /// a provider with no members, so nothing distributes the frame away.
    @Test("A frame on EmptyView keeps its rows, where SwiftUI's keeps none")
    func frameOnEmptyViewKeepsRows() {
        #expect(rows(between: EmptyView().frame(height: 5), spacing: 0) == ["A", "", "", "", "", "", "B"])
    }

    /// SwiftUI: 32 — `EmptyView().padding(20)` adds nothing either. TUIkit
    /// pads the empty buffer like any other, so padding rows are there: the
    /// same divergence as the frame's, through `PaddingModifier` rather than
    /// `FlexibleFrameView`. Three rows, not four: a padding always keeps back
    /// a row of what it is offered for its content, out of the inset after
    /// it, and the empty content draws nothing in it.
    @Test("A padding on EmptyView keeps rows, where SwiftUI's keeps none")
    func paddingOnEmptyViewKeepsRows() {
        #expect(rows(between: EmptyView().padding(2), spacing: 0) == ["A", "", "", "", "B"])
    }

    /// SwiftUI: 52 points against 42 — the empty stack is a child, and has the
    /// stack's 10 points on each side of it. TUIkit charges spacing only
    /// between children that take a row (or are spacers), so an empty stack
    /// changes nothing, as a `nil` changes nothing in both.
    @Test("An empty stack takes no spacing, where SwiftUI's takes it on both sides")
    func emptyStackTakesNoSpacing() {
        #expect(rows(between: VStack(spacing: 0) { if never { Text("x") } }, spacing: 1) == ["A", "", "B"])
        #expect(rows(between: absent, spacing: 1) == ["A", "", "B"])
    }
}
