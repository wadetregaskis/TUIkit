//  🖥️ TUIkit — Terminal UI Kit for Swift
//  WindowedEstimateMeasureMemoTests.swift
//
//  A windowed stack's measure answers from the running pitch its own render
//  refines, so a render that moves it changes what the stack measures in the
//  middle of a pass. The pass's measure memo used to serve the answer from
//  before the render to a measure asked after it: a stack of 300 rows, the
//  first sixteen one line tall and the rest two, measured 300 lines from its
//  sample and 600 once its render had touched two-line rows — and a chat of
//  257 messages 1,284 lines where a fresh measure said 1,027. The memo
//  verifier, which re-measures every served size, is the oracle.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

private struct EstimateApp: App {
    let anchor: UnitPoint?
    init() { anchor = nil }
    init(anchor: UnitPoint?) { self.anchor = anchor }
    var body: some Scene { WindowGroup { EstimatePage(anchor: anchor) } }
}

/// A header over a scroll view of a lazy stack past the windowing threshold
/// whose sample (its first sixteen rows) is a line shorter per row than the
/// rows after it.
private struct EstimatePage: View {
    let anchor: UnitPoint?
    @State private var tick = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("tick \(tick)")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<300, id: \.self) { index in
                        Text(index < 16 ? "row \(index)" : "row \(index)\nsecond line")
                    }
                }
            }
            .defaultScrollAnchor(anchor)
        }
        .onKeyPress(.character("t")) { tick += 1 }
    }
}

@MainActor
@Suite("A windowed stack's estimate and the pass's measure memo")
struct WindowedEstimateMeasureMemoTests {
    @Test(
        "No size the pass memoized before a render moved the estimate is served after it",
        arguments: [UnitPoint?.none, .bottom])
    func servedSizesMatchAFreshMeasure(anchor: UnitPoint?) {
        let verified = RenderCache.verifiesMeasureMemo
        RenderCache.verifiesMeasureMemo = true
        defer { RenderCache.verifiesMeasureMemo = verified }
        let app = HeadlessApp(EstimateApp(anchor: anchor), width: 30, height: 10)
        let script: [KeyEvent?] = [
            nil, KeyEvent(key: .character("t")), KeyEvent(key: .pageUp), KeyEvent(key: .end),
            KeyEvent(key: .character("t")), nil,
        ]
        for (step, event) in script.enumerated() {
            if let event { _ = app.send(event) }
            app.frame(atNanos: Int64(step + 1) * 16_666_667)
        }
        let mismatches = app.renderCache.measureMemoMismatches
        #expect(mismatches.isEmpty, "\(mismatches.count) served sizes differed: \(mismatches.first ?? "")")
    }
}
