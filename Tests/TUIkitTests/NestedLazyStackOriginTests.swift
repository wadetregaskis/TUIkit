//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NestedLazyStackOriginTests.swift
//
//  A lazy stack reached from a scroll view's content by SINGLE-CHILD steps —
//  alone in an outer lazy stack, or the body of a custom view there — can
//  still be below the content's origin: the outer stack consumed the scroll
//  window itself. Reading the steps alone, such a stack took itself for the
//  one the window bands: it estimated its height and was drawn whole into the
//  estimate. These drive the whole app and hold each shape to the same rows in
//  an eager `VStack`, which has no window to misread.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

/// Where the lazy stack sits in the scroll view's content.
enum LazyStackOriginShape: CaseIterable, CustomTestStringConvertible {
    /// `LazyVStack { LazyVStack { rows } }`.
    case aloneInAnOuterLazyStack
    /// `LazyVStack { Rows() }`, `Rows` a view whose body is the lazy stack.
    case customBodyInAnOuterLazyStack

    var testDescription: String { "\(self)" }
}

/// Three hundred rows, the first sixteen one line and the rest two — so the
/// sixteen-row estimate UNDER-reports the stack by 284 lines.
@MainActor
private func originRows() -> some View {
    ForEach(0..<300, id: \.self) { index in
        Text(index < 16 ? "row \(index)" : "row \(index)\nsecond line")
    }
}

/// The rows in a stack of their own: lazy, or the eager twin.
private struct OriginRowStack: View {
    let lazy: Bool

    var body: some View {
        if lazy {
            LazyVStack(alignment: .leading, spacing: 0) { originRows() }
        } else {
            VStack(alignment: .leading, spacing: 0) { originRows() }
        }
    }
}

private struct OriginApp: App {
    let shape: LazyStackOriginShape
    let lazy: Bool
    let bottomAnchored: Bool

    init() { self.init(shape: .aloneInAnOuterLazyStack, lazy: true, bottomAnchored: false) }
    init(shape: LazyStackOriginShape, lazy: Bool, bottomAnchored: Bool) {
        self.shape = shape
        self.lazy = lazy
        self.bottomAnchored = bottomAnchored
    }

    var body: some Scene {
        WindowGroup {
            OriginPage(shape: shape, lazy: lazy)
                .defaultScrollAnchor(bottomAnchored ? .bottom : nil)
        }
    }
}

private struct OriginPage: View {
    let shape: LazyStackOriginShape
    let lazy: Bool

    var body: some View {
        ScrollView {
            switch shape {
            case .aloneInAnOuterLazyStack:
                // Spelled out rather than through `OriginRowStack`, whose body
                // would make this the custom-body case.
                if lazy {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        LazyVStack(alignment: .leading, spacing: 0) { originRows() }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 0) { originRows() }
                    }
                }
            case .customBodyInAnOuterLazyStack:
                if lazy {
                    LazyVStack(alignment: .leading, spacing: 0) { OriginRowStack(lazy: true) }
                } else {
                    VStack(alignment: .leading, spacing: 0) { OriginRowStack(lazy: false) }
                }
            }
        }
    }
}

/// The row numbers drawn on `screen`.
private func originRowsDrawn(on screen: [String]) -> Set<Int> {
    var rows = Set<Int>()
    for line in screen {
        for match in line.matches(of: /row (\d+)/) {
            if let number = Int(match.1) { rows.insert(number) }
        }
    }
    return rows
}

@MainActor
@Suite("A lazy stack below the scroll content's origin, reached by single-child steps")
struct NestedLazyStackOriginTests {
    private static let frame: Int64 = 16_666_667

    @Test(
        "Bottom-anchored: the last of 300 rows is drawn when the stack is alone in an outer lazy stack",
        arguments: [LazyStackOriginShape.aloneInAnOuterLazyStack, .customBodyInAnOuterLazyStack])
    func bottomAnchoredDrawsTheLastRow(shape: LazyStackOriginShape) {
        // The outer stack consumes the window and draws its one row whole, into
        // the height it measured for it. Reading its single-child steps, the
        // inner stack took itself for the one the window bands and ESTIMATED
        // that height: 300 lines for the sixteen-row sample, of which the rows
        // filled 0–157, and the bottom of the scroll view was row 157.
        let app = HeadlessApp(
            OriginApp(shape: shape, lazy: true, bottomAnchored: true), width: 30, height: 10)
        app.frame(atNanos: 0)
        app.frame(atNanos: Self.frame)
        let screen = app.screen.map(\.stripped)
        let rows = originRowsDrawn(on: screen)
        #expect(rows.contains(299), "the tail is drawn: \(screen)")
        #expect(!rows.contains(157), "not stopped at the estimate's end: \(screen)")
    }

    @Test(
        "A lazy stack draws what the same rows in a VStack draw, scrolled end to end",
        arguments: LazyStackOriginShape.allCases)
    func drawsWhatItsEagerTwinDraws(shape: LazyStackOriginShape) {
        // The eager twin has no window to misread, so every screen it draws is
        // the one the lazy stack owes. Compared without the scrollbar column,
        // whose thumb a windowed stack places from an estimate by design; with
        // both measure-memo verifiers armed, since the stack now answers its
        // measures by walking where it estimated.
        //
        // Before: alone in an outer lazy stack, or a view's body there, End
        // stopped at row 157.
        let wasVerifyingMeasures = RenderCache.verifiesMeasureMemo
        let wasVerifyingRenders = RenderCache.verifiesRenderMemo
        RenderCache.verifiesMeasureMemo = true
        RenderCache.verifiesRenderMemo = true
        defer {
            RenderCache.verifiesMeasureMemo = wasVerifyingMeasures
            RenderCache.verifiesRenderMemo = wasVerifyingRenders
        }
        let lazy = HeadlessApp(OriginApp(shape: shape, lazy: true, bottomAnchored: false), width: 30, height: 12)
        let eager = HeadlessApp(OriginApp(shape: shape, lazy: false, bottomAnchored: false), width: 30, height: 12)
        var script: [KeyEvent?] = [nil, nil]
        script += Array(repeating: KeyEvent(key: .pageDown), count: 4)
        script += [KeyEvent(key: .end), nil, KeyEvent(key: .pageUp), KeyEvent(key: .up), KeyEvent(key: .home)]
        // The status bar's three lines go too: they are the app's, not the scroll view's.
        let content = { (app: HeadlessApp<OriginApp>) in
            app.screen.dropLast(3).map { String($0.stripped.dropLast()) }
        }
        var diverged: [String] = []
        for (step, event) in script.enumerated() {
            if let event {
                lazy.send(event)
                eager.send(event)
            }
            lazy.frame(atNanos: Int64(step) * Self.frame)
            eager.frame(atNanos: Int64(step) * Self.frame)
            if content(lazy) != content(eager) {
                diverged.append("step \(step): lazy \(content(lazy)) eager \(content(eager))")
            }
        }
        #expect(diverged.isEmpty, "\(diverged.count) screens differ: \(diverged.prefix(1))")
        #expect(lazy.renderCache.measureMemoMismatches.isEmpty, "\(lazy.renderCache.measureMemoMismatches)")
        #expect(lazy.renderCache.renderMemoMismatches.isEmpty, "\(lazy.renderCache.renderMemoMismatches)")
    }
}
