//  🖥️ TUIKit — Terminal UI Kit for Swift
//  NavigationSplitViewSizingTests.swift
//
//  Regression coverage for the "Size to Fit (from left)" column mode, split out
//  of NavigationSplitViewTests.swift to keep that file under the length limit.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("NavigationSplitView size-to-fit sizing")
struct NavigationSplitViewSizingTests {
    /// The column at which the detail's `D` run begins in the first rendered row
    /// — i.e. the leading columns' total width plus dividers.
    private func detailStart(style: some NavigationSplitViewStyle) -> Int {
        let view = NavigationSplitView {
            List { Text("A"); Text("BB"); Text("CCC") }
        } detail: {
            Text(String(repeating: "D", count: 300))
        }
        .navigationSplitViewStyle(style)
        .navigationSplitViewResizable(false)  // no stored-width override: pure style default
        let tui = TUIContext()
        var env = EnvironmentValues()
        env.focusManager = FocusManager()
        let ctx = RenderContext(
            availableWidth: 100, availableHeight: 6, environment: env, tuiContext: tui)
        let row = renderToBuffer(view, context: ctx).lines.first?.stripped ?? ""
        return row.firstIndex(of: "D").map { row.distance(from: row.startIndex, to: $0) } ?? -1
    }

    @Test("Size-to-fit hugs a width-greedy List column, snugger than Balanced")
    func sizeToFitHugsListColumn() {
        // The reported bug: a List sidebar reports itself width-FLEXIBLE, so
        // size-to-fit bucketed every column flexible and split the width evenly
        // (1/N ≈ 33% at 3 columns) — WIDER than Automatic (25%) or Balanced
        // (30%). The fix measures each column's hugged content width, so a short
        // List hugs. (A plain Text sidebar never exercised this, since Text is
        // not width-greedy — that case lives in NavigationSplitViewTests.)
        let fit = detailStart(style: .sizeToFitFromLeft)
        let balanced = detailStart(style: .balanced)
        #expect(fit > 0, "the detail column must render (found the D run)")
        #expect(
            fit < balanced,
            "size-to-fit List sidebar (detail@\(fit)) must be snugger than Balanced (detail@\(balanced))")
    }
}
