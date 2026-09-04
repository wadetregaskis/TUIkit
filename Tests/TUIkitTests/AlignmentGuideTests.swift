//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AlignmentGuideTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

/// A custom guide one third of the way across, to prove the model is genuinely
/// extensible rather than three built-ins in a trench coat.
private enum OneThird: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> Double {
        Double(context.width) / 3
    }
}

extension HorizontalAlignment {
    fileprivate static let oneThird = Self(OneThird.self)
}

/// A guide whose rule produces a value that is not a coordinate. Nobody writes
/// `.infinity` on purpose; dividing by a dimension that is legitimately zero —
/// `childOffset` measures on ONE axis, so the other is always zero — is how an
/// app arrives at one by accident.
private enum ZeroDivideID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> Double {
        Double(context.width) / Double(context.height)
    }
}

extension HorizontalAlignment {
    fileprivate static let zeroDivide = Self(ZeroDivideID.self)
}

extension VerticalAlignment {
    fileprivate static let zeroDivide = Self(ZeroDivideID.self)
}

/// `HorizontalAlignment` and `VerticalAlignment` are SwiftUI-shaped structs over
/// ``AlignmentID`` rather than closed enums, so apps can define their own
/// guides.
///
/// The property that made this safe to do at all: a guide value is **fractional
/// even though every size and position is a whole cell**. Guides are only ever
/// subtracted from one another and floored, and flooring does not distribute
/// over subtraction — whole-cell guides would have silently moved 190 of 820
/// centring cases by a cell.
@Suite("Alignment guides")
struct AlignmentGuideTests {

    @Test("Guide subtraction reproduces the previous centring rule exactly")
    func centringIsUnchanged() {
        // The rule TUIkit used before guides existed, checked exhaustively
        // rather than at a few sample points — this is the whole reason guide
        // values are fractional.
        for total in 0...40 {
            for child in 0...total {
                #expect(
                    HorizontalAlignment.center.childOffset(childWidth: child, in: total)
                        == (total - child) / 2)
                #expect(
                    VerticalAlignment.center.childOffset(childHeight: child, in: total)
                        == (total - child) / 2)
            }
        }
    }

    @Test("Whole-cell guides would NOT have reproduced it")
    func wholeCellGuidesWouldDiverge() {
        // Pins the reason rather than the result: if someone later "simplifies"
        // the guide type to Int, this is the case that catches it.
        let total = 10, child = 3
        #expect(total / 2 - child / 2 != (total - child) / 2)
        #expect(HorizontalAlignment.center.childOffset(childWidth: child, in: total) == 3)
    }

    @Test("Leading and trailing place flush, and clamp on an oversized child")
    func edgesAndClamping() {
        #expect(HorizontalAlignment.leading.childOffset(childWidth: 3, in: 10) == 0)
        #expect(HorizontalAlignment.trailing.childOffset(childWidth: 3, in: 10) == 7)
        // A child wider than its region cannot be pushed off the leading edge.
        #expect(HorizontalAlignment.trailing.childOffset(childWidth: 20, in: 10) == 0)
        #expect(VerticalAlignment.bottom.childOffset(childHeight: 20, in: 10) == 0)
    }

    @Test("A custom AlignmentID places children by its own rule")
    func customGuidePlaces() {
        // Region guide 12/3 = 4, child guide 3/3 = 1 → offset 3.
        #expect(HorizontalAlignment.oneThird.childOffset(childWidth: 3, in: 12) == 3)
        // And it is a distinct guide, not equal to any built-in.
        #expect(HorizontalAlignment.oneThird != .center)
        #expect(HorizontalAlignment.oneThird != .leading)
    }

    @Test("Alignments compare by their defining AlignmentID")
    func equalityIsByIdentity() {
        // Two separately constructed values over the same AlignmentID must be
        // equal — the property a closed enum gave for free and a struct does not.
        #expect(HorizontalAlignment(OneThird.self) == HorizontalAlignment.oneThird)
        let rebuilt = VerticalAlignment(OneThird.self)
        #expect(rebuilt == VerticalAlignment(OneThird.self))
        #expect(VerticalAlignment.top != VerticalAlignment.bottom)
    }

    @Test("ViewDimensions reports guide positions")
    func viewDimensionsSubscripts() {
        let dimensions = ViewDimensions(width: 10, height: 5)
        #expect(dimensions.width == 10)
        #expect(dimensions.height == 5)
        #expect(dimensions[HorizontalAlignment.leading] == 0)
        #expect(dimensions[HorizontalAlignment.center] == 5)
        #expect(dimensions[HorizontalAlignment.trailing] == 10)
        #expect(dimensions[VerticalAlignment.top] == 0)
        #expect(dimensions[VerticalAlignment.bottom] == 5)

        // Fractional where the cell count is odd — the value that never
        // survives to a coordinate.
        #expect(ViewDimensions(width: 3, height: 0)[HorizontalAlignment.center] == 1.5)
    }

    @Test("Text baselines are the first and last rows")
    func textBaselines() {
        // A terminal cell has no interior baseline, so a line's baseline is the
        // line. `.lastTextBaseline` on an empty view must not go negative.
        let threeLines = ViewDimensions(width: 0, height: 3)
        #expect(threeLines[VerticalAlignment.firstTextBaseline] == 0)
        #expect(threeLines[VerticalAlignment.lastTextBaseline] == 2)
        #expect(ViewDimensions(width: 0, height: 0)[VerticalAlignment.lastTextBaseline] == 0)
    }

    /// The six `Alignment` presets that pair an edge with a baseline. They are
    /// pure combinations, so what is worth pinning is that each pairs the two
    /// alignments its NAME claims — a transposed pair would compile, and would
    /// then quietly align a label to the wrong end of the paragraph.
    @Test("Baseline Alignment presets pair the alignments they are named for")
    func baselineAlignmentPresets() {
        let cases: [(Alignment, HorizontalAlignment, VerticalAlignment)] = [
            (.leadingFirstTextBaseline, .leading, .firstTextBaseline),
            (.centerFirstTextBaseline, .center, .firstTextBaseline),
            (.trailingFirstTextBaseline, .trailing, .firstTextBaseline),
            (.leadingLastTextBaseline, .leading, .lastTextBaseline),
            (.centerLastTextBaseline, .center, .lastTextBaseline),
            (.trailingLastTextBaseline, .trailing, .lastTextBaseline),
        ]
        for (alignment, horizontal, vertical) in cases {
            #expect(alignment.horizontal == horizontal)
            #expect(alignment.vertical == vertical)
        }
        // And that they are genuinely distinct from the box-edge presets they
        // sit beside: `.leading` centres vertically, this one does not.
        #expect(Alignment.leadingFirstTextBaseline != Alignment.leading)
    }

    @Test("No guide set explicitly reads back as nil")
    func explicitGuidesAbsentByDefault() {
        let dimensions = ViewDimensions(width: 10, height: 5)
        #expect(dimensions[explicit: HorizontalAlignment.center] == nil)
        #expect(dimensions[explicit: VerticalAlignment.top] == nil)
    }

    // MARK: - Values that are not coordinates

    /// A guide is caller arithmetic, so it can be anything a `Double` holds.
    /// Resolving one used to reach `Int(_: Double)`, which traps on NaN, on
    /// either infinity and on any magnitude past `Int`'s range — and it fired
    /// on the child that SET the guide, whose own base is `merged - guide`,
    /// i.e. `∞ - ∞`.
    @Test(
        "A guide that is not a coordinate resolves instead of trapping",
        arguments: [
            [Double.infinity, 0], [-.infinity, 0], [0, .infinity], [.nan, 0], [0, .nan],
            [1e300, 0], [-1e300, 0],
        ])
    func nonCoordinateGuideResolves(resolved: [Double]) {
        let run = AlignmentGuideRun.resolve(
            resolved: resolved, sizes: [3, 3], fixedExtent: nil, minimumExtent: 0
        ) { Double($0) / 2 }
        #expect(run.offsets.count == 2)
        // Bounded by the CHILDREN'S geometry, not merely finite and not a
        // magic constant: a guide is a coordinate within its own view, so the
        // furthest one places a child is its own extent (with overshoot), and
        // the region a content-sized run grows to follows from the real sizes.
        // Here sizes are 3, so the extent cannot pass ~3× a child; an `Int.max`
        // from a saturating conversion would instead pad a buffer that wide.
        #expect((0...12).contains(run.extent), "extent \(run.extent)")
        #expect(
            run.offsets.allSatisfy { (0...run.extent).contains($0) },
            "offsets \(run.offsets) within 0...\(run.extent)")
    }

    @Test("The single-child placement path resolves one too")
    func nonCoordinateGuidePlacement() {
        // `.frame(alignment:)` / `.overlay(alignment:)`: one guide in a region
        // whose extent is already decided. `merged` IS the guide there, so
        // `merged - guide` is `∞ - ∞` for every non-finite value.
        for guide in [Double.infinity, -.infinity, .nan, 1e300] {
            let run = AlignmentGuideRun.resolve(
                resolved: [guide], sizes: [4], fixedExtent: 10, minimumExtent: 10
            ) { Double($0) / 2 }
            #expect(run.extent == 10, "guide \(guide) must not move a fixed extent")
            #expect((0...6).contains(run.offsets[0]), "guide \(guide) -> \(run.offsets[0])")
        }
    }

    @Test("A custom AlignmentID that answers with NaN or infinity still places")
    func nonCoordinateCustomAlignmentID() {
        // No `.alignmentGuide` involved: `childOffset` subtracts two
        // caller-supplied defaults and converted the difference the same way.
        #expect((0...7).contains(HorizontalAlignment.zeroDivide.childOffset(childWidth: 3, in: 10)))
        #expect((0...10).contains(HorizontalAlignment.zeroDivide.childOffset(childWidth: 0, in: 10)))
        #expect((0...7).contains(VerticalAlignment.zeroDivide.childOffset(childHeight: 3, in: 10)))
    }

    @Test("An explicit guide overrides the default")
    func explicitGuideOverrides() {
        let dimensions = ViewDimensions(
            width: 10, height: 5,
            explicitGuides: [HorizontalAlignment.center.key: 2])
        #expect(dimensions[HorizontalAlignment.center] == 2)
        #expect(dimensions[explicit: HorizontalAlignment.center] == 2)
        // Untouched guides still answer their default.
        #expect(dimensions[HorizontalAlignment.leading] == 0)
    }
}
