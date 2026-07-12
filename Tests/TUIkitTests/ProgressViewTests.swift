//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ProgressViewTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Test Helpers

/// Creates a default render context for testing.
private func testContext(width: Int = 30, height: Int = 24) -> RenderContext {
    RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIContext()).isolatingRenderCache()
}

// MARK: - ProgressView Rendering Tests

@MainActor
@Suite("ProgressView Tests")
struct ProgressViewTests {

    @Test("Progress bar renders single line without label")
    func barOnlyIsSingleLine() {
        let view = ProgressView(value: 0.5)
        let context = testContext()
        let buffer = renderToBuffer(view, context: context)

        #expect(buffer.height == 1)
        #expect(buffer.width == 30)
    }

    @Test("Progress bar with label renders two lines")
    func barWithLabelIsTwoLines() {
        let view = ProgressView("Loading", value: 0.5)
        let context = testContext()
        let buffer = renderToBuffer(view, context: context)

        #expect(buffer.height == 2)
        #expect(buffer.lines[0].contains("Loading"))
    }

    @Test("Progress bar with ViewBuilder label renders two lines")
    func barWithViewBuilderLabel() {
        let view = ProgressView(value: 0.7) {
            Text("Downloading")
        }
        let context = testContext()
        let buffer = renderToBuffer(view, context: context)

        #expect(buffer.height == 2)
        #expect(buffer.lines[0].contains("Downloading"))
    }

    @Test("Progress bar with label and currentValueLabel shows both")
    func barWithLabelAndValueLabel() {
        let view = ProgressView(value: 0.5) {
            Text("Task")
        } currentValueLabel: {
            Text("50%")
        }
        let context = testContext()
        let buffer = renderToBuffer(view, context: context)

        #expect(buffer.height == 2)
        #expect(buffer.lines[0].contains("Task"))
        #expect(buffer.lines[0].contains("50%"))
    }

    @Test("Default line style contains filled and empty block characters")
    func lineStyleContainsBlockCharacters() {
        let view = ProgressView(value: 0.5)
        let context = testContext()
        let buffer = renderToBuffer(view, context: context)

        let barLine = buffer.lines[0].stripped
        #expect(barLine.contains("█"))
        #expect(barLine.contains("░"))
    }

    @Test("0% progress shows all empty blocks")
    func zeroProgressAllEmpty() {
        let view = ProgressView(value: 0.0)
        let context = testContext()
        let buffer = renderToBuffer(view, context: context)

        let barLine = buffer.lines[0].stripped
        #expect(!barLine.contains("█"))
        #expect(barLine.contains("░"))
    }

    @Test("100% progress shows all filled blocks")
    func fullProgressAllFilled() {
        let view = ProgressView(value: 1.0)
        let context = testContext()
        let buffer = renderToBuffer(view, context: context)

        let barLine = buffer.lines[0].stripped
        #expect(barLine.contains("█"))
        #expect(!barLine.contains("░"))
    }

    @Test("Bar width equals available width")
    func barFillsAvailableWidth() {
        let view = ProgressView(value: 0.5)
        let context = testContext(width: 20)
        let buffer = renderToBuffer(view, context: context)

        let barLine = buffer.lines[0].stripped
        #expect(barLine.count == 20)
    }

    @Test("Filled count scales with fraction at 50%")
    func filledCountScalesWithFraction() {
        let view = ProgressView(value: 0.5)
        let context = testContext(width: 20)
        let buffer = renderToBuffer(view, context: context)

        let barLine = buffer.lines[0].stripped
        let filledCount = barLine.filter { $0 == "█" }.count
        let emptyCount = barLine.filter { $0 == "░" }.count

        #expect(filledCount == 10)
        #expect(emptyCount == 10)
    }
}

// MARK: - Style Tests

@MainActor
@Suite("ProgressView Style Tests")
struct ProgressViewStyleTests {

    @Test("Block style uses only █ and ░ characters")
    func blockStyleWholeBlocks() {
        let view = ProgressView(value: 0.33).progressViewStyle(.block)
        let context = testContext(width: 10)
        let buffer = renderToBuffer(view, context: context)

        let barLine = buffer.lines[0].stripped
        let allExpected = barLine.allSatisfy { $0 == "█" || $0 == "░" }
        #expect(allExpected)
    }

    @Test("BlockFine style uses fractional blocks for sub-character precision")
    func blockFineStyleFractionalBlocks() {
        // 33% of 10 = 3.3 cells → 3 full + fractional
        let view = ProgressView(value: 0.33).progressViewStyle(.blockFine)
        let context = testContext(width: 10)
        let buffer = renderToBuffer(view, context: context)

        let barLine = buffer.lines[0].stripped
        let fractionalChars: Set<Character> = ["▏", "▎", "▍", "▌", "▋", "▊", "▉"]
        let hasFractional = barLine.contains { fractionalChars.contains($0) }
        #expect(hasFractional)
    }

    @Test("Shade style uses ▓ and ░ characters")
    func shadeStyleCharacters() {
        let view = ProgressView(value: 0.5).progressViewStyle(.shade)
        let context = testContext(width: 20)
        let buffer = renderToBuffer(view, context: context)

        let barLine = buffer.lines[0].stripped
        #expect(barLine.contains("▓"))
        #expect(barLine.contains("░"))
    }

    @Test("BlockFine fills the unfilled region with a solid background, not ░ blocks")
    func blockFineUnfilledIsBackground() {
        // #2: the unfilled portion is a consistent background colour (rendered
        // as spaces) rather than ░ glyphs, so the boundary cell's remainder and
        // the empty run read as one solid bar.
        let view = ProgressView(value: 0.4).progressViewStyle(.blockFine)
        let barLine = renderToBuffer(view, context: testContext(width: 20)).lines[0].stripped
        #expect(!barLine.contains("░"), "blockFine no longer draws ░ for the unfilled region: '\(barLine)'")
        #expect(barLine.hasSuffix(" "), "the unfilled remainder is trailing spaces: '\(barLine)'")
        #expect(barLine.count == 20)
    }

    @Test("BlockFine paints the whole track on the empty colour as a background")
    func blockFinePaintsBackground() {
        // Rendering the fill family directly lets us inspect the raw ANSI. Under
        // basic-16, using the empty colour (red) as a BACKGROUND emits SGR 41;
        // `.block` uses the same colour only as a foreground (SGR 31 via ░).
        withColorDepth(.basic16) {
            let blockFine = TrackRenderer.render(
                fraction: 0.4, width: 10, style: .blockFine,
                filledColor: .green, emptyColor: .red, accentColor: .blue)
            let block = TrackRenderer.render(
                fraction: 0.4, width: 10, style: .block,
                filledColor: .green, emptyColor: .red, accentColor: .blue)
            #expect(blockFine.contains("41"), "blockFine paints a background: \(blockFine.debugDescription)")
            #expect(!block.contains("41"), "block keeps the unfilled colour a foreground: \(block.debugDescription)")
        }
    }

    @Test("BlockFine full cells carry the FILL colour as their background (no bleed)")
    func blockFineFullCellsFillBackground() {
        // Terminal.app doesn't paint the whole cell with █ (a few pixel rows
        // above the glyph and hairline seams between cells stay background).
        // Painting the empty colour behind the FILLED cells showed through as
        // a bleed above the fill — so full cells now use their own fill
        // colour as the background (glyph == background ⇒ unpainted pixels
        // invisible), while the partial boundary cell keeps the empty colour
        // behind its genuinely-unfilled remainder. Under basic-16: green
        // bg = 42 (full cells), red bg = 41 (partial + empty region).
        withColorDepth(.basic16) {
            // 0.45 × 10 cells × 8 eighths = 36 steps → 4 full cells + a ▌.
            let bar = TrackRenderer.render(
                fraction: 0.45, width: 10, style: .blockFine,
                filledColor: .green, emptyColor: .red, accentColor: .blue)
            #expect(bar.contains("42"), "full cells sit on the fill colour: \(bar.debugDescription)")
            let partialCell = bar.split(separator: "▌").first.map(String.init) ?? ""
            #expect(
                !partialCell.isEmpty && bar.contains("▌"),
                "the boundary cell renders its partial glyph: \(bar.debugDescription)")
            #expect(
                bar.contains("41"),
                "the partial cell + empty remainder keep the empty colour behind them: \(bar.debugDescription)")
        }
    }

    @Test("shadeRamp uses · for empty, distinct from shade's ░")
    func shadeRampVsShade() {
        // #3: `.shade` (▓ on ░) reads close to `.block`; `.shadeRamp` is the
        // visibly graded style — the demos point here. Confirm they differ.
        let ramp = renderToBuffer(
            ProgressView(value: 0.5).progressViewStyle(.shadeRamp()),
            context: testContext(width: 20)).lines[0].stripped
        let shade = renderToBuffer(
            ProgressView(value: 0.5).progressViewStyle(.shade),
            context: testContext(width: 20)).lines[0].stripped
        #expect(ramp.contains("·"), "shadeRamp uses · dots for empty: '\(ramp)'")
        #expect(!ramp.contains("░"), "shadeRamp does not use ░ for empty: '\(ramp)'")
        #expect(shade.contains("░"), "plain shade still uses ░ for empty: '\(shade)'")
    }

    @Test("A custom TrackConfiguration mixes any fill glyph with any unfilled treatment")
    func customConfigurationFlexibility() {
        // #4: the whole point of the config — a shade-ramp fill but with ░
        // blocks for the empty region (not · dots), a combination no named
        // preset provides, and the same fill with a solid background instead.
        let dotsForEmpty = TrackConfiguration(
            fullGlyph: "█", partialRamp: ["░", "▒", "▓"], emptyStyle: .glyph("░"))
        let bgForEmpty = TrackConfiguration(
            fullGlyph: "█", partialRamp: ["░", "▒", "▓"], emptyStyle: .background)

        let dotsBar = renderToBuffer(
            ProgressView(value: 0.3).progressViewStyle(.custom(dotsForEmpty)),
            context: testContext(width: 20)).lines[0].stripped
        let bgBar = renderToBuffer(
            ProgressView(value: 0.3).progressViewStyle(.custom(bgForEmpty)),
            context: testContext(width: 20)).lines[0].stripped

        #expect(dotsBar.contains("░"), "custom .glyph(\"░\") empty draws ░: '\(dotsBar)'")
        #expect(!bgBar.contains("░"), "custom .background empty draws spaces: '\(bgBar)'")
        #expect(dotsBar.count == 20 && bgBar.count == 20)
    }

    @Test("Bar style uses ▌ and ─ characters")
    func barStyleCharacters() {
        let view = ProgressView(value: 0.5).progressViewStyle(.bar)
        let context = testContext(width: 20)
        let buffer = renderToBuffer(view, context: context)

        let barLine = buffer.lines[0].stripped
        #expect(barLine.contains("▌"))
        #expect(barLine.contains("─"))
    }

    @Test("Dot style uses ▬, ● head, and ─ characters")
    func dotStyleCharacters() {
        let view = ProgressView(value: 0.5).progressViewStyle(.dot)
        let context = testContext(width: 20)
        let buffer = renderToBuffer(view, context: context)

        let barLine = buffer.lines[0].stripped
        #expect(barLine.contains("▬"))
        #expect(barLine.contains("●"))
        #expect(barLine.contains("─"))
    }

    @Test("Style modifier returns correct style")
    func styleModifierWorks() {
        let view = ProgressView(value: 0.5).progressViewStyle(.shade)
        #expect(view.style == .shade)
    }

    @Test("All styles render correct width")
    func allStylesCorrectWidth() {
        let styles: [TrackStyle] = [.block, .blockFine, .shade, .bar, .dot]
        let context = testContext(width: 20)

        for style in styles {
            let view = ProgressView(value: 0.5).progressViewStyle(style)
            let buffer = renderToBuffer(view, context: context)
            let barLine = buffer.lines[0].stripped
            #expect(barLine.count == 20, "Style \(style) should render width 20, got \(barLine.count)")
        }
    }

    @Test("Dot style at 0% shows the head at the start of an empty track")
    func dotStyleZeroPercent() {
        let view = ProgressView(value: 0.0).progressViewStyle(.dot)
        let context = testContext(width: 10)
        let buffer = renderToBuffer(view, context: context)

        // The head marker never disappears: at 0% it sits on the first cell
        // with no fill behind it.
        let barLine = buffer.lines[0].stripped
        #expect(barLine.first == "●", "head leads the track: |\(barLine)|")
        #expect(!barLine.contains("▬"), "no fill behind the head at 0%")
        #expect(barLine.contains("─"))
    }

    @Test("Dot style at 100% shows head at end")
    func dotStyleFullPercent() {
        let view = ProgressView(value: 1.0).progressViewStyle(.dot)
        let context = testContext(width: 10)
        let buffer = renderToBuffer(view, context: context)

        let barLine = buffer.lines[0].stripped
        #expect(barLine.contains("●"))
        #expect(barLine.contains("▬"))
        #expect(!barLine.contains("─"))
    }
}

// MARK: - Edge Case Tests

@MainActor
@Suite("ProgressView Edge Cases")
struct ProgressViewEdgeCaseTests {

    @Test("Value greater than total clamps to 100%")
    func valueExceedsTotalClamped() {
        let view = ProgressView(value: 2.0, total: 1.0)
        let context = testContext(width: 10)
        let buffer = renderToBuffer(view, context: context)

        let barLine = buffer.lines[0].stripped
        let filledCount = barLine.filter { $0 == "█" }.count
        #expect(filledCount == 10)
    }

    @Test("Negative value clamps to 0%")
    func negativeValueClamped() {
        let view = ProgressView(value: -0.5)
        let context = testContext(width: 10)
        let buffer = renderToBuffer(view, context: context)

        let barLine = buffer.lines[0].stripped
        let filledCount = barLine.filter { $0 == "█" }.count
        #expect(filledCount == 0)
    }

    @Test("Zero total produces 0% bar")
    func zeroTotalShowsEmpty() {
        let view = ProgressView(value: 5.0, total: 0.0)
        let context = testContext(width: 10)
        let buffer = renderToBuffer(view, context: context)

        let barLine = buffer.lines[0].stripped
        let filledCount = barLine.filter { $0 == "█" }.count
        #expect(filledCount == 0)
    }

    @Test("nil value renders an animated indeterminate bar")
    func nilValueRendersIndeterminateBar() {
        let view = ProgressView<EmptyView, EmptyView>(value: Optional<Double>.none)
        let context = testContext(width: 10)
        let buffer = renderToBuffer(view, context: context)

        let barLine = buffer.lines[0].stripped
        // An indeterminate bar shows a sweeping highlighted segment — it is
        // never empty — and still fills exactly the available width.
        let filledCount = barLine.filter { $0 == "█" }.count
        #expect(filledCount > 0, "Indeterminate bar must show a highlighted segment")
        #expect(barLine.strippedLength == 10)
    }

    @Test("Custom total works correctly")
    func customTotal() {
        let view = ProgressView(value: 3.0, total: 10.0)
        let context = testContext(width: 10)
        let buffer = renderToBuffer(view, context: context)

        let barLine = buffer.lines[0].stripped
        let filledCount = barLine.filter { $0 == "█" }.count
        #expect(filledCount == 3)  // 30% of 10
    }

    @Test("Float value works via BinaryFloatingPoint generic")
    func floatValueWorks() {
        let view = ProgressView(value: Float(0.5))
        let context = testContext()
        let buffer = renderToBuffer(view, context: context)

        #expect(buffer.height == 1)
        #expect(buffer.lines[0].contains("█"))
    }

    @Test("Width of 1 renders single character")
    func singleCharWidth() {
        let view = ProgressView(value: 1.0)
        let context = testContext(width: 1)
        let buffer = renderToBuffer(view, context: context)

        let barLine = buffer.lines[0].stripped
        #expect(barLine == "█")
    }
}

// MARK: - TrackRenderer Defensive Clamping

@MainActor
@Suite("TrackRenderer Clamping Tests")
struct TrackRendererClampingTests {

    @Test("TrackRenderer clamps fraction above 1.0 to prevent overflow")
    func clampsFractionAboveOne() {
        // Fraction > 1.0 should not produce a track wider than the requested width
        let track = TrackRenderer.render(
            fraction: 1.5,
            width: 10,
            style: .block,
            filledColor: .white,
            emptyColor: .white,
            accentColor: .cyan
        )
        #expect(
            track.strippedLength == 10,
            "Track with fraction > 1.0 should clamp to width 10, got \(track.strippedLength)"
        )
    }

    @Test("TrackRenderer clamps negative fraction to prevent underflow")
    func clampsNegativeFraction() {
        let track = TrackRenderer.render(
            fraction: -0.5,
            width: 10,
            style: .block,
            filledColor: .white,
            emptyColor: .white,
            accentColor: .cyan
        )
        #expect(
            track.strippedLength == 10,
            "Track with negative fraction should clamp to width 10, got \(track.strippedLength)"
        )
    }

    @Test("TrackRenderer all styles handle out-of-range fraction safely")
    func allStylesHandleOutOfRange() {
        let styles: [TrackStyle] = [.block, .blockFine, .shade, .bar, .dot]

        for style in styles {
            let overTrack = TrackRenderer.render(
                fraction: 2.0,
                width: 10,
                style: style,
                filledColor: .white,
                emptyColor: .white,
                accentColor: .cyan
            )
            #expect(
                overTrack.strippedLength == 10,
                "Style \(style) with fraction 2.0 should render width 10, got \(overTrack.strippedLength)"
            )

            let underTrack = TrackRenderer.render(
                fraction: -1.0,
                width: 10,
                style: style,
                filledColor: .white,
                emptyColor: .white,
                accentColor: .cyan
            )
            #expect(
                underTrack.strippedLength == 10,
                "Style \(style) with fraction -1.0 should render width 10, got \(underTrack.strippedLength)"
            )
        }
    }
}

// MARK: - Indeterminate ProgressView Tests

@MainActor
@Suite("Indeterminate ProgressView Tests")
struct IndeterminateProgressViewTests {

    @Test("ProgressView() is indeterminate")
    func noArgInitIsIndeterminate() {
        #expect(ProgressView().fractionCompleted == nil)
    }

    @Test("ProgressView(_:) is indeterminate with a label")
    func titleInitIsIndeterminate() {
        let view = ProgressView("Loading")
        #expect(view.fractionCompleted == nil)
        let buffer = renderToBuffer(view, context: testContext())
        #expect(buffer.height == 2, "A titled indeterminate view has a label line and a bar")
        #expect(buffer.lines[0].stripped.contains("Loading"))
    }

    @Test("Indeterminate bar fills the width with a highlighted segment")
    func indeterminateBarRenders() {
        let buffer = renderToBuffer(ProgressView(), context: testContext(width: 30))
        #expect(buffer.height == 1)
        #expect(buffer.lines[0].strippedLength == 30, "The bar fills the available width")
        #expect(buffer.lines[0].contains("█"), "The sweeping segment is always present")
        #expect(buffer.lines[0].contains("░"), "The remainder of the track is visible")
    }
}
