//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContentWidthFreshChallengeTests.swift
//
//  The challenge measures the row the kept all-rows width names as its widest
//  (`StackContentWidth.swift`), and forgets that row's memoized sizes first so
//  it is measured rather than remembered. It does NOT forget a memo deeper
//  inside the row — an `.equatable()` view whose value compares equal while
//  what its body reads has moved — and does not need to: the size memo drops,
//  at the end of every frame, the entries of a row that frame did not draw, so
//  what a challenge finds inside the widest row was measured this frame. This
//  pins that: it fails the day a measure-only entry starts outliving its frame.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// A model a row holds and reads in its body.
@Observable
@MainActor
private final class LabelModel {
    var cells: Int
    init(cells: Int) { self.cells = cells }
}

/// A label whose value is its model's IDENTITY — equal across frames however
/// the model's cells move, as SwiftUI allows of a view that reads an
/// `@Observable` — so `.equatable()`'s memo, keyed on that value, would serve
/// the old size if it had one to serve.
private struct ModelLabel: View, @MainActor Equatable {
    let model: LabelModel
    let digit: Int

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.model === rhs.model && lhs.digit == rhs.digit }

    var body: some View { Text(String(repeating: "\(digit)", count: model.cells)) }
}

/// Row 200's label reads `wide`, row 100 is the runner-up at 60, the rest are
/// eight; each `.equatable()` inside an `HStack` — a memo one level below the
/// row's own, which the challenge forgets.
private struct DeepRow: View {
    let index: Int
    let wide: LabelModel
    let plain: LabelModel

    var body: some View {
        HStack(spacing: 0) {
            ModelLabel(model: index == 200 ? wide : plain, digit: index % 10).equatable()
        }
    }
}

@MainActor
@Suite("A challenge measured afresh all the way down")
struct ContentWidthFreshChallengeTests {
    /// Row 200 — the widest, and never drawn: the viewport is at the top, so
    /// its label is read only by measures, untracked — shrinks from 120 cells
    /// to 10 with nothing clearing it, then something else is written. The
    /// challenge re-measures row 200, which must reach its label: the extent
    /// falls to row 100's 60, as for content that had row 200 at ten cells from
    /// the start.
    @Test("A shrunk label inside the widest row is measured, not remembered")
    func aShrunkLabelIsMeasured() {
        let wide = LabelModel(cells: 120)
        let tuiContext = TUIContext()
        func rows(_ wide: LabelModel, _ tuiContext: TUIContext) -> () -> String {
            let plain = LabelModel(cells: 8)
            let runnerUp = LabelModel(cells: 60)
            return twoAxisFrames(tuiContext: tuiContext) { index in
                DeepRow(index: index, wide: wide, plain: index == 100 ? runnerUp : plain)
            }
        }
        let frame = rows(wide, tuiContext)
        _ = frame()
        _ = frame()

        wide.cells = 10
        // A write that clears nothing of row 200's: the shape of an untracked
        // read, which a row measured but never drawn makes.
        tuiContext.renderCache.clearAffected(by: ViewIdentity(path: "elsewhere"))
        let control = rows(LabelModel(cells: 10), TUIContext())
        _ = control()
        #expect(frame() == control(), "the challenge was served the label's old width")
    }
}
