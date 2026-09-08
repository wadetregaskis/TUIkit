//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListRowBuildDeferralTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// Pins the List row pipeline's steady-state cost model: once a row's buffer
/// is in the render cache, a later frame must serve it WITHOUT invoking the
/// `ForEach` content closure at all. The closure is the app's row builder —
/// views, string interpolation, localization lookups — and running it per
/// visible row per frame just to discard the result against a cache hit was
/// measured at a fifth of a `List` frame. The badge peek is the subtlety: it
/// needs a BUILT view, so only a row whose static type can carry a badge
/// (`.badge(_:)` outermost) may still build for it.
@MainActor
@Suite("List row build deferral")
struct ListRowBuildDeferralTests {

    private func context(width: Int = 40, height: Int = 12) -> RenderContext {
        let focusManager = FocusManager()
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        return RenderContext(
            availableWidth: width,
            availableHeight: height,
            environment: environment,
            tuiContext: TUIContext()
        ).isolatingRenderCache()
    }

    @Test("A steady-state frame builds no row views")
    func steadyStateBuildsNothing() {
        // A class box, not @State: the builder must observe mutation across
        // renders without invalidating the rows (which would defeat the memo
        // this test measures).
        final class Counter { var builds = 0 }
        let counter = Counter()
        func makeRow(_ i: Int) -> Text {
            counter.builds += 1
            return Text("row \(i)")
        }

        let view = List {
            ForEach(0..<50, id: \.self) { makeRow($0) }
        }
        let renderContext = context()
        _ = renderToBuffer(view, context: renderContext)
        let firstFrameBuilds = counter.builds
        #expect(firstFrameBuilds > 0, "frame 1 must build the visible rows")

        let warm = renderToBuffer(view, context: renderContext)
        let secondFrameBuilds = counter.builds - firstFrameBuilds
        // The rows that DREW are the ones that could hit, and under the memo
        // verifier each hit costs one build (see `verifierRenders(hits:)`).
        // Counted off the frame rather than written down, because the visible
        // window is a function of the List's chrome and is not what this pins.
        let servedRows = warm.lines.filter { $0.stripped.contains("row ") }.count
        #expect(
            secondFrameBuilds == verifierRenders(hits: servedRows),
            "a warm frame built \(secondFrameBuilds) row views for \(servedRows) visible rows, then discarded them against its cache hits")
    }

    @Test("A badged row still renders its badge through the deferral")
    func badgedRowsKeepTheirBadges() {
        let view = List {
            ForEach(0..<20, id: \.self) { i in
                Text("row \(i)").badge(777)
            }
        }
        let renderContext = context()
        _ = renderToBuffer(view, context: renderContext)
        let second = renderToBuffer(view, context: renderContext)
        let joined = second.lines.map(\.stripped).joined(separator: "\n")
        #expect(joined.contains("777"), "badge value renders on a warm frame: \(joined)")
    }
}
