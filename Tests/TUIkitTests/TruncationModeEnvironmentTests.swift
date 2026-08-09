//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TruncationModeEnvironmentTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// `.truncationMode(_:)` on a **View**, which is where SwiftUI puts it: one
/// application decides how every piece of clipped text beneath it reads.
///
/// `Text` has had its own `.truncationMode(_:)` all along; what was missing was
/// the cascading one, and the rule that decides which of the two wins.
@MainActor
@Suite("truncationMode (View)")
struct TruncationModeEnvironmentTests {

    /// A path is the case the mode exists for: it identifies itself at the end.
    private let path = "/Users/someone/Documents/TUIkit/Sources/Text.swift"

    private func line(_ view: some View, width: Int) -> String {
        renderToBuffer(view, context: makeRenderContext(width: width, height: 1))
            .lines.first?.stripped ?? ""
    }

    @Test("The cascaded mode reaches text that never mentioned it")
    func cascadeReachesDescendants() {
        let tail = line(VStack { Text(path).lineLimit(1) }, width: 20)
        let head = line(VStack { Text(path).lineLimit(1) }.truncationMode(.head), width: 20)

        // Tail keeps the beginning, head keeps the end — and the end is the
        // half of a path anyone is reading it for.
        #expect(tail.hasPrefix("/Users"))
        #expect(head.hasSuffix("Text.swift"))
        #expect(tail != head)
    }

    @Test("A Text's own mode beats the one cascaded to it")
    func textOwnModeWins() {
        // The Form precedent: a modifier applied to the specific view is more
        // specific than one applied to everything above it.
        let rendered = line(
            VStack { Text(path).lineLimit(1).truncationMode(.tail) }.truncationMode(.head),
            width: 20)
        #expect(rendered.hasPrefix("/Users"))
    }

    @Test("Every mode cuts where it says")
    func allThreeModes() {
        func rendered(_ mode: TruncationMode) -> String {
            line(Text(path).lineLimit(1).truncationMode(mode), width: 20)
        }
        #expect(rendered(.tail).hasPrefix("/Users"))
        #expect(rendered(.head).hasSuffix("Text.swift"))
        let middle = rendered(.middle)
        #expect(middle.hasPrefix("/"))
        #expect(middle.hasSuffix("swift"))
        // Whatever the mode, the result fits the space it was given — the point
        // of truncating at all.
        for mode in [TruncationMode.tail, .head, .middle] {
            #expect(rendered(mode).count <= 20)
        }
    }

    @Test("Truncation is not conditional on a line limit")
    func appliesWithoutALineLimit() {
        // A word longer than the wrap boundary is cut wherever it appears, so
        // the cascaded mode has to reach that path too — not only the
        // `.lineLimit` one.
        let head = line(Text("supercalifragilistic").truncationMode(.head), width: 10)
        #expect(head.hasSuffix("listic"))
    }

    @Test("The default is still tail")
    func defaultIsUnchanged() {
        #expect(EnvironmentValues().truncationMode == .tail)
        #expect(line(Text(path).lineLimit(1), width: 20).hasPrefix("/Users"))
    }
}
