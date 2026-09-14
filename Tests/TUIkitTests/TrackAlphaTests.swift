//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TrackAlphaTests.swift
//
//  Row 8 of §16.1: `TrackConfiguration(emptyColor:)` (now `backgroundColor:`), `SegmentColoring`, and every
//  other colour a track paints. Nineteen emit sites, all of which already counted
//  cells and none of which said where a run began.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A translucent track")
struct TrackAlphaTests {

    private func palette() -> any Palette { SystemPalette.default }

    private func drawn(
        _ style: TrackStyle, fraction: Double = 0.5, width: Int = 10,
        filled: Color = .rgb(200, 40, 40), empty: Color = .rgb(40, 40, 40),
        accent: Color = .rgb(40, 200, 40)
    ) -> ClaimingRow {
        TrackRenderer.render(
            fraction: fraction, width: width, style: style, filledColor: filled,
            emptyColor: empty, accentColor: accent, palette: palette())
    }

    private var half: Double { 128.0 / 255 }

    // MARK: - The pairing

    @Test("An opaque track claims nothing at all")
    func opaqueTrackClaimsNothing() {
        for style in [TrackStyle.block, .blockFine, .shade, .bar, .braille, .dot, .knob, .marker] {
            #expect(drawn(style).claims.isEmpty, "\(style)")
        }
    }

    @Test("A faded fill claims the lit cells and states the opaque colour in the bytes")
    func fadedFillClaims() throws {
        let row = drawn(.block, filled: Color.rgb(200, 40, 40).opacity(0.5))
        #expect(!row.claims.isEmpty)
        for claim in row.claims where claim.inkOpacity < 1 {
            #expect(claim.inkOpacity == half, "\(claim)")
        }
        #expect(
            row.text.contains("38;2;200;40;40"),
            "the bytes must state the opaque spelling: \(row.text.debugDescription)")
    }

    /// **The cell the two channels exist for.**
    ///
    /// `.blockFine`'s fractional boundary cell is the one place in the framework whose
    /// ink and field come from different sources: the ramp glyph is the fill's colour
    /// and the rest of the cell shows the empty colour through it. An opaque fill with
    /// a translucent `TrackConfiguration.backgroundColor` must resolve `inkOpacity == 1`
    /// and `fieldOpacity < 1`. One alpha per cell gets it wrong in both directions.
    @Test("The boundary cell takes its ink from the fill and its field from the background colour")
    func boundaryCellSplitsItsChannels() throws {
        var config = TrackConfiguration.blockFine
        config.backgroundColor = Color.rgb(40, 40, 40).opacity(0.5)
        // A fraction that lands mid-cell, so a boundary cell is drawn at all.
        let row = drawn(.custom(config), fraction: 0.55, width: 10)
        let split = try #require(
            row.claims.first { $0.inkOpacity == 1 && $0.fieldOpacity == half },
            "no ink-opaque/field-faded cell: \(row.claims)")
        #expect(split.width == 1)
    }

    // MARK: - The public entry points row 8 names

    @Test("TrackConfiguration(backgroundColor:) claims the background")
    func configuredBackgroundColorClaims() throws {
        var config = TrackConfiguration.block
        config.backgroundColor = Color.rgb(40, 40, 40).opacity(0.5)
        let row = drawn(.custom(config), fraction: 0.4)
        let claim = try #require(
            row.claims.first { $0.fieldOpacity == half }, "\(row.claims)")
        #expect(claim.offsetX == 4, "the unfilled part starts where the fill stops")
        #expect(claim.width == 6)
    }

    @Test("SegmentColoring.solid claims the lit region")
    func segmentSolidClaims() throws {
        let row = drawn(
            .threeSegment(
                leading: "[", middle: "=", trailing: "]", backgroundPattern: "·",
                coloring: .solid(Color.rgb(200, 40, 40).opacity(0.5))),
            fraction: 0.6)
        let claim = try #require(row.claims.first { $0.inkOpacity == half }, "\(row.claims)")
        #expect(claim.offsetX == 0)
    }

    @Test("SegmentColoring.perSegment claims each segment separately, measured in cells")
    func segmentPerSegmentClaims() {
        let faded = Color.rgb(200, 40, 40).opacity(0.5)
        let row = drawn(
            .threeSegment(
                leading: "🌑", middle: "=", trailing: "🌖", backgroundPattern: "·",
                coloring: .perSegment(leading: faded, middle: .rgb(0, 0, 255), trailing: faded)),
            fraction: 1.0, width: 10)
        // Two claims, and the second must start past the wide leading glyph's TWO
        // cells — a character count would put it at column 1.
        let fadedEnds = row.claims.filter { $0.inkOpacity == half }
        #expect(fadedEnds.count == 2, "\(row.claims)")
        #expect(fadedEnds.first?.offsetX == 0)
        #expect(fadedEnds.first?.width == 2, "🌑 is two cells: \(row.claims)")
        #expect((fadedEnds.last?.offsetX ?? 0) > 2, "\(row.claims)")
    }

    /// A translucent gradient stop is honourable on a track: it is ONE row, so a
    /// per-cell alpha is a run of rectangles rather than a grid.
    ///
    /// Asserted per COLUMN rather than per rectangle. `ClaimingRow` merges adjacent
    /// runs that owe the same alpha, so how many rectangles a row needs is an
    /// implementation detail — this pinned `count >= 8` and width 1, and both changed
    /// the moment the merge arrived without anything about the alpha changing. What
    /// the track owes is an alpha per column, and that is what this reads.
    @Test("SegmentColoring.gradient states an alpha for every cell it painted")
    func segmentGradientClaims() {
        // Two alphas rather than one, so the ramp genuinely varies along the row and
        // the merge cannot collapse it to a single rectangle by accident.
        let row = drawn(
            .threeSegment(
                leading: "[", middle: "=", trailing: "]", backgroundPattern: "·",
                coloring: .gradient(
                    Gradient(colors: [
                        Color.rgb(200, 40, 40).opacity(0.25), Color.rgb(40, 40, 200).opacity(1.0),
                    ]))),
            fraction: 1.0, width: 8)
        #expect(row.claims.count > 1, "the alpha varies along it: \(row.claims)")
        let covered = row.claims.reduce(into: Set<Int>()) { set, claim in
            set.formUnion(claim.offsetX..<(claim.offsetX + claim.width))
        }
        // Every cell the track drew, and the alphas rise from the dim stop to the
        // bright one without ever going backwards.
        #expect(covered.count < row.cells, "the opaque end owes no claim: \(row.claims)")
        let ordered = row.claims.sorted { $0.offsetX < $1.offsetX }
        #expect(ordered.first?.offsetX == 0, "\(ordered)")
        #expect(
            zip(ordered, ordered.dropFirst()).allSatisfy { $0.inkOpacity <= $1.inkOpacity },
            "\(ordered.map(\.inkOpacity))")
    }

    // MARK: - The two indicator styles

    /// `.knob` takes filledColor AND headColor from the accent, so the lit rail and
    /// the head are both claimed and the unlit remainder — the control's own colour —
    /// is not. They arrive as ONE rectangle rather than two, because they owe the same
    /// alpha and `ClaimingRow` merges runs that do; what matters is which columns are
    /// covered, which is what this reads.
    @Test("A knob's rail and its head are both claimed, and the unlit remainder is not")
    func knobClaims() {
        let faded = Color.rgb(40, 200, 40).opacity(0.5)
        let row = drawn(.knob, fraction: 0.5, width: 9, accent: faded)
        let fadedClaims = row.claims.filter { $0.inkOpacity == half }
        #expect(fadedClaims.count == 1, "rail and head owe one alpha: \(row.claims)")
        #expect(fadedClaims.first?.offsetX == 0, "\(row.claims)")
        // Four rail cells and the head on the fifth, out of nine — so the claim
        // reaches the head and stops, leaving the unlit tail to the control's colour.
        #expect(fadedClaims.first?.width == 5, "\(row.claims)")
        #expect(row.cells == 9)
    }

    @Test("A marker's dot claims alone, leaving an opaque rail opaque")
    func markerClaimsOnlyTheDot() throws {
        let row = drawn(.marker, fraction: 0.5, width: 9, accent: Color.rgb(40, 200, 40).opacity(0.5))
        #expect(row.claims.count == 1, "\(row.claims)")
        let claim = try #require(row.claims.first)
        #expect(claim.width == 1, "only the dot: \(claim)")
        #expect(claim.inkOpacity == half)
    }

    // MARK: - The coarse path

    /// A wide fill glyph forces the coarse path, where a character-counted claim
    /// would be wrong by a cell per glyph.
    ///
    /// The three lit emoji arrive as one rectangle of SIX cells, not three of two:
    /// they owe the same alpha and adjacent runs that do are merged. Six is the number
    /// that carries the test — a character count would have said three.
    @Test("The coarse path claims each glyph at its real cell width")
    func coarsePathClaimsInCells() {
        var config = TrackConfiguration.block
        config.fill = "😃"
        let row = drawn(.custom(config), fraction: 0.5, width: 10, filled: Color.rgb(200, 40, 40).opacity(0.5))
        let lit = row.claims.filter { $0.inkOpacity == half }
        #expect(!lit.isEmpty, "\(row.claims)")
        let cells = lit.reduce(0) { $0 + $1.width }
        #expect(cells.isMultiple(of: 2), "whole emoji only: \(row.claims)")
        #expect(cells == 6, "three emoji at two cells each: \(row.claims)")
        #expect(lit.allSatisfy { $0.offsetX.isMultiple(of: 2) }, "and they tile: \(row.claims)")
    }

    // MARK: - The picture path declines

    /// A picture has no alpha channel to send, and a terminal would composite it
    /// against its own background rather than against what TUIkit drew behind the
    /// cell. So a translucent track declines that path and takes the cell one — which
    /// matters because `.block` is `ProgressView`'s default, and without the decline
    /// the gap would be terminal-distributed.
    @Test("A translucent track refuses the picture path and claims instead")
    func translucentTrackDeclinesThePicture() {
        let context = makeRenderContext(width: 20, height: 2)
        let graphics = context.gradientGraphics(token: "track-test")
        guard let graphics else { return }  // no graphics on this host: nothing to decline
        let row = TrackRenderer.render(
            fraction: 0.5, width: 10, style: .block,
            filledColor: Color.rgb(200, 40, 40).opacity(0.5), emptyColor: .rgb(40, 40, 40),
            accentColor: .rgb(40, 200, 40), palette: palette(), graphics: graphics)
        #expect(!row.claims.isEmpty, "declined to a claiming cell path: \(row.claims)")
        #expect(
            !row.text.unicodeScalars.contains(.terminalImagePlaceholder),
            "still drew a picture: \(row.text.debugDescription)")
    }

    // MARK: - The three consumers

    @Test("A Slider's track claims land two cells in, past ◀ and its gap")
    func sliderTrackClaimsShiftPastTheArrow() throws {
        let context = RenderContext(availableWidth: 24, availableHeight: 1, tuiContext: TUIContext())
            .isolatingRenderCache()
        let drawn = renderToBuffer(
            Slider(value: .constant(0.5), in: 0...1).tint(Color.red.opacity(0.5)), context: context)
        let claims = drawn.opacityRegions.filter { $0.inkOpacity == half }
        #expect(!claims.isEmpty, "\(drawn.opacityRegions)")
        #expect(
            claims.allSatisfy { $0.offsetX >= sliderTrackLeft },
            "a claim landed on the arrow: \(claims)")
    }

    @Test("A disabled Slider claims nothing — its alpha was already spent")
    func disabledSliderClaimsNothing() {
        let context = RenderContext(availableWidth: 24, availableHeight: 1, tuiContext: TUIContext())
            .isolatingRenderCache()
        let drawn = renderToBuffer(
            Slider(value: .constant(0.5), in: 0...1).tint(Color.red.opacity(0.5)).disabled(true),
            context: context)
        // `forState` composites every colour through `opacity(_:over: palette.background)`,
        // which consumes the alpha and stamps the result opaque. One colour, two
        // answers, decided by `isEnabled` — recorded in §31.3 rather than left as a
        // surprise.
        #expect(drawn.opacityRegions.isEmpty, "\(drawn.opacityRegions)")
    }

    @Test("A Gauge's bar claims past its minimum label")
    func gaugeClaimsPastTheMinimumLabel() {
        let context = RenderContext(availableWidth: 30, availableHeight: 3, tuiContext: TUIContext())
            .isolatingRenderCache()
        let drawn = renderToBuffer(
            Gauge(value: 0.5) { Text("L") } currentValueLabel: { Text("") }
                minimumValueLabel: { Text("mn") } maximumValueLabel: { Text("mx") }
                .gaugeStyle(.accessoryLinear)
                .tint(Color.red.opacity(0.5)),
            context: context)
        let claims = drawn.opacityRegions.filter { $0.inkOpacity == half }
        #expect(!claims.isEmpty, "\(drawn.opacityRegions)")
        #expect(claims.allSatisfy { $0.offsetX >= 3 }, "past \"mn \": \(claims)")
    }

    @Test("A determinate ProgressView's bar claims on the bar's own row")
    func progressViewClaimsOnItsBarRow() {
        let context = RenderContext(availableWidth: 20, availableHeight: 3, tuiContext: TUIContext())
            .isolatingRenderCache()
        // `.knob`, not the default `.block`: a `ProgressView`'s fill colour is
        // `palette.foregroundSecondary`, so `.tint` never reaches the default bar at
        // all. The styles that take the accent are `.dot`, `.knob` and `.marker`.
        let drawn = renderToBuffer(
            ProgressView(value: 0.5) { Text("Loading") }
                .progressViewStyle(.knob)
                .tint(Color.red.opacity(0.5)),
            context: context)
        // The bar is below the label, so a claim on row 0 would fade the label instead
        // — and `allSatisfy` on an empty array is vacuously true, so the count comes
        // first.
        #expect(!drawn.opacityRegions.isEmpty, "nothing claimed at all")
        #expect(drawn.lines.count > 1, "the label and the bar are two rows")
        #expect(
            drawn.opacityRegions.allSatisfy { $0.offsetY == drawn.lines.count - 1 },
            "\(drawn.opacityRegions) over \(drawn.lines.count) lines")
    }
}

/// `_SliderCore.trackLeft` is private to its generic type; this is the same number,
/// stated once for the test that asserts claims do not land on the arrow.
private let sliderTrackLeft = 2
