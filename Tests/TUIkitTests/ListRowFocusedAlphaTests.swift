//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListRowFocusedAlphaTests.swift
//
//  §33.3's recorded hole: every translucent thing a `List` row can paint needs
//  the list to hold the FOCUS, and focusing one from a headless render did not
//  work — so `_ListCore`'s arm was tested at the shared seam and its focused
//  path had no assertion at all. This is that assertion.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A focused List row's own colours")
struct ListRowFocusedAlphaTests {

    private struct Row: Identifiable, Hashable {
        let id: Int
        let name: String
    }

    private let rows = (0..<4).map { Row(id: $0, name: "row\($0)") }

    private var half: Double { 128.0 / 255 }

    /// **What §33.3 was missing, and it was one line.**
    ///
    /// The earlier attempt built its context with
    /// `RenderContext(availableWidth:availableHeight:tuiContext:)`, which leaves
    /// `environment.focusManager` nil — so the rows registered with nothing, and no
    /// number of render passes or `focus(id:)` calls could make one of them focused.
    /// The manager has to be put IN the environment, the way the render loop does it
    /// and the way `WindowedFocusReachTests.renderFrame` already showed.
    ///
    /// Two passes, because the first is what registers: a row cannot be focused
    /// before it has said it exists.
    ///
    /// The other half of why the earlier attempt failed is the SELECTION.
    /// `RowSelectionIndicator.forRow` takes `isFocused`, and `_ListCore` computes that
    /// as `handler.isCursorRow(rowIndex) && listHasFocus` — so the raw-accent branch
    /// needs the selected row to also be the row the keyboard cursor is on. Selecting
    /// row 1 while the cursor sat on row 0 rendered the *unfocused* mark, which is a
    /// composite (`opacity(_:over:)`) and therefore opaque and unclaimed: a render
    /// that looks focused and is not, which is exactly the "passed for the wrong
    /// reason" shape §33.3 refused to paper over.
    private func focusedListBuffer<V: View>(_ view: V, focusID: String) -> FrameBuffer {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()

        func pass() -> FrameBuffer {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.applyRuntimeServices(from: tuiContext)
            let context = RenderContext(
                availableWidth: 30, availableHeight: 10,
                environment: environment, tuiContext: tuiContext)
            tuiContext.preferences.beginRenderPass()
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
            return buffer
        }

        _ = pass()
        focusManager.focus(id: focusID)
        return pass()
    }

    /// A focused, selected row takes the accent RAW for its mark — that is the one
    /// path where a faded `.tint` survives as far as the glyph, because the unfocused
    /// mark spends its alpha through `opacity(_:over:)` instead. So this is the
    /// assertion the seam test could not make.
    @Test("A focused List's selection mark claims the tint's alpha")
    func focusedMarkClaims() {
        let drawn = focusedListBuffer(
            List(selection: .constant(Set([0]))) {
                ForEach(rows) { row in Text(row.name) }
            }
            .focusID("faded-list")
            .tint(Color.red.opacity(0.5)),
            focusID: "faded-list")
        let ink = drawn.opacityRegions.filter { $0.inkOpacity == half }
        #expect(!ink.isEmpty, "no claim reached the mark: \(drawn.opacityRegions)")
        // The mark is one cell at the head of its row, which is what
        // `SelectableRowClaims` states and what the seam test pins the shape of.
        // Exactly one cell: the mark. `offsetX == 1` and `offsetY == 1` because a
        // `List` draws itself inside a border, so the row's own column zero is the
        // buffer's column one — which is the shift the list's region attach applies and the
        // seam test, working in row-local coordinates, cannot see.
        #expect(ink.count == 1, "\(ink)")
        #expect(ink.first?.width == 1, "one cell, the mark: \(ink)")
        #expect(ink.first?.offsetX == 1 && ink.first?.offsetY == 1, "inside the border: \(ink)")
    }

    /// And the byte half of the pairing: the mark's own SGR must be the opaque
    /// spelling. A claim without it is a double fade; the spelling without a claim is
    /// a silently discarded alpha. This is the assertion that would have caught either
    /// one, and it is the whole reason the hole mattered.
    @Test("The focused mark's bytes are its opaque spelling")
    func focusedMarkBytesAreOpaque() {
        let drawn = focusedListBuffer(
            List(selection: .constant(Set([0]))) {
                ForEach(rows) { row in Text(row.name) }
            }
            .focusID("faded-list-bytes")
            .tint(Color.rgb(200, 40, 40).opacity(0.5)),
            focusID: "faded-list-bytes")
        let joined = drawn.lines.joined()
        #expect(joined.contains("●"), "the focused mark is drawn: \(drawn.lines)")
        #expect(joined.contains("200;40;40"), "at its opaque spelling: \(drawn.lines)")
    }

    /// The control that proves the focus actually took: with an opaque tint the same
    /// render claims nothing. Without this a broken `focusedListBuffer` would make the
    /// test above fail rather than pass for the wrong reason — but a broken CLAIM would
    /// make this one pass for the wrong reason, so both are needed.
    @Test("The same focused list with an opaque tint claims nothing")
    func focusedOpaqueClaimsNothing() {
        let drawn = focusedListBuffer(
            List(selection: .constant(Set([0]))) {
                ForEach(rows) { row in Text(row.name) }
            }
            .focusID("opaque-list")
            .tint(.red),
            focusID: "opaque-list")
        #expect(drawn.lines.joined().contains("●"), "still focused: \(drawn.lines)")
        #expect(drawn.opacityRegions.isEmpty, "\(drawn.opacityRegions)")
    }
}
