//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ViewThatFitsTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("ViewThatFits Tests")
struct ViewThatFitsTests {

    private func context(width: Int, height: Int = 24) -> RenderContext {
        RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIContext())
    }

    @Test("Picks the first candidate when it fits the available space")
    func picksFirstWhenItFits() {
        let view = ViewThatFits {
            HStack(spacing: 1) {
                Text("Alpha")
                Text("Beta")
                Text("Gamma")
            }
            VStack(spacing: 0) {
                Text("Alpha")
                Text("Beta")
                Text("Gamma")
            }
        }
        let buffer = renderToBuffer(view, context: context(width: 60))
        #expect(
            buffer.height == 1,
            "Ample width should select the single-row horizontal candidate, got height \(buffer.height)"
        )
    }

    @Test("Falls back to a later candidate when the first does not fit")
    func fallsBackWhenFirstDoesNotFit() {
        let view = ViewThatFits {
            HStack(spacing: 1) {
                Text("Alpha")
                Text("Beta")
                Text("Gamma")
            }
            VStack(spacing: 0) {
                Text("Alpha")
                Text("Beta")
                Text("Gamma")
            }
        }
        let buffer = renderToBuffer(view, context: context(width: 8))
        #expect(
            buffer.height == 3,
            "Narrow width should select the stacked vertical candidate, got height \(buffer.height)"
        )
    }

    @Test("Uses the last candidate when none of them fit")
    func usesLastWhenNoneFit() {
        let view = ViewThatFits {
            Text("AAAAAAAAAA")
            Text("BBBBB")
        }
        // Width 3: neither candidate fits, so the last (shortest) is used.
        let buffer = renderToBuffer(view, context: context(width: 3))
        #expect(buffer.lines.first?.stripped.contains("B") == true)
        #expect(buffer.lines.first?.stripped.contains("A") != true)
    }

    @Test("A horizontal-only axis ignores height overflow")
    func horizontalAxisIgnoresHeight() {
        let view = ViewThatFits(in: .horizontal) {
            Text("a\nb\nc\nd")  // 1 cell wide, 4 lines tall
            Text("xy")
        }
        // Height 2 is less than the first candidate's 4 lines, but with the
        // axis set to .horizontal only width is tested — so the first
        // candidate is still chosen despite overflowing vertically.
        let buffer = renderToBuffer(view, context: context(width: 20, height: 2))
        #expect(buffer.lines.first?.stripped == "a", "The tall first candidate should have been chosen")
    }

    @Test("A single candidate is always rendered")
    func singleCandidate() {
        let view = ViewThatFits { Text("only") }
        let buffer = renderToBuffer(view, context: context(width: 40))
        #expect(buffer.lines.first?.stripped == "only")
    }
}
