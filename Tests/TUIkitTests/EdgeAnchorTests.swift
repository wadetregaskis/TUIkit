//  🖥️ TUIKit — Terminal UI Kit for Swift
//  EdgeAnchorTests.swift
//
//  `Documentation/Scroll-anchoring.md` §1.1's two POSITIONAL modes: Top ("the
//  view stays at the top, irrespective of rows being added, removed, or
//  moved") and Bottom (follow-the-log). They name an EDGE, never a row — which
//  is exactly what separates them from Row mode, and what these tests pin.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Edge anchors (§1.1 Top / Bottom)")
struct EdgeAnchorTests {

    private static let viewport = 8

    /// One rendered frame of a `ScrollView` over a `LazyVStack`, as the visible
    /// lines. `uniform: false` with >256 rows takes the ANCHORED walk — the path
    /// that persists a row key across frames, and so the only one where an edge
    /// mode could be confused for a row mode.
    private func renderFrame(
        items: [Int], declared: UnitPoint?, bound: ErasedScrollAnchor?, uniform: Bool,
        tuiContext: TUIContext, focusManager: FocusManager
    ) -> [String] {
        let view = ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(items, id: \.self) { i in
                    Text("row \(i)").frame(height: uniform ? 1 : i % 3 + 1)
                }
            }
        }
        .frame(height: Self.viewport)

        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        environment.defaultScrollAnchor = declared
        if let bound { environment.anchorPosition = .constant(bound) }
        let context = RenderContext(
            availableWidth: 30, availableHeight: Self.viewport,
            environment: environment, tuiContext: tuiContext)

        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    /// The row ids visible in a frame, in screen order.
    private func shownIDs(_ lines: [String]) -> [Int] {
        lines.compactMap { line in
            guard let marker = line.range(of: "row ") else { return nil }
            return Int(line[marker.upperBound...].prefix { $0.isNumber })
        }
    }

    // MARK: - Top mode is positional, not a row hold

    /// Top's whole content is "stay at the top". On the anchored walk the stack
    /// persists a row key across frames, and Top used to re-bind that key like
    /// Row mode — so prepending held the row that had been at the top and the
    /// view silently followed it DOWN, away from the top. The new rows were
    /// unreachable without scrolling, which is the opposite of what the app
    /// asked for.
    private func expectTopStaysAtTheTop(bound: ErasedScrollAnchor?, comment: Comment) {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        // >256 rows, variable heights: the anchored walk.
        var items = Array(1_000..<1_400)
        let declared: UnitPoint? = bound == nil ? .top : nil

        for _ in 0..<3 {
            _ = renderFrame(
                items: items, declared: declared, bound: bound, uniform: false,
                tuiContext: tuiContext, focusManager: focusManager)
        }
        let before = shownIDs(
            renderFrame(
                items: items, declared: declared, bound: bound, uniform: false,
                tuiContext: tuiContext, focusManager: focusManager))
        #expect(before.first == 1_000, "\(comment): starts at the top")

        items.insert(contentsOf: 0..<60, at: 0)
        let after = shownIDs(
            renderFrame(
                items: items, declared: declared, bound: bound, uniform: false,
                tuiContext: tuiContext, focusManager: focusManager))
        #expect(
            after.first == 0,
            """
            \(comment): Top must show the NEW first rows after a prepend, \
            not follow the row that used to be at the top. before=\(before) after=\(after)
            """)
    }

    @Test("A declared .top stays at the top when rows are prepended")
    func declaredTopStaysAtTheTop() {
        expectTopStaysAtTheTop(bound: nil, comment: "declared .top")
    }

    @Test("A bound .top stays at the top when rows are prepended")
    func boundTopStaysAtTheTop() {
        expectTopStaysAtTheTop(bound: .top, comment: "bound .top")
    }

    // MARK: - Bottom is untouched by the above

    /// The guard on the positional change: Bottom's follow is offset-driven
    /// (glue to `maxOffset`), so dropping its key re-bind must leave it exactly
    /// as shipped.
    @Test("A declared .bottom still follows appended rows")
    func declaredBottomFollowsAppends() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        var items = Array(0..<40)

        for _ in 0..<3 {
            _ = renderFrame(
                items: items, declared: .bottom, bound: nil, uniform: true,
                tuiContext: tuiContext, focusManager: focusManager)
        }
        let before = shownIDs(
            renderFrame(
                items: items, declared: .bottom, bound: nil, uniform: true,
                tuiContext: tuiContext, focusManager: focusManager))
        #expect(before.last == 39, "starts at the tail: \(before)")

        items.append(contentsOf: 100..<105)
        let after = shownIDs(
            renderFrame(
                items: items, declared: .bottom, bound: nil, uniform: true,
                tuiContext: tuiContext, focusManager: focusManager))
        #expect(after.last == 104, "follows the new tail: \(after)")
    }

    // MARK: - The policy itself

    /// `.top`/`.bottom` are POSITIONAL and `.row` is IDENTITY — the distinction
    /// `ScrollAnchor`'s doc comment exists to protect. Only the identity policy
    /// may re-bind the persisted anchor to a row key.
    @Test("Only Row mode holds row identity")
    func onlyRowHoldsIdentity() {
        #expect(ScrollAnchorMode.row.holdsRowIdentity == true)
        #expect(ScrollAnchorMode.top.holdsRowIdentity == false)
        #expect(ScrollAnchorMode.bottom.holdsRowIdentity == false)
        #expect(ScrollAnchorMode.window.holdsRowIdentity == false)
    }
}
