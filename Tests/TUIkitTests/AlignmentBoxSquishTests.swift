//  🖥️ TUIKit — Terminal UI Kit for Swift
//  AlignmentBoxSquishTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
private func renderRow(width: Int) -> (lines: [String], height: Int) {
    // Mirrors the "Content Alignment" demo in ContainersPage.swift: three
    // bordered VStacks share a row evenly via `.frame(maxWidth: .infinity)`.
    let view = HStack(spacing: 1) {
        VStack(alignment: .leading) {
            Text("Leading align")
            Text("short")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .border()

        VStack(alignment: .center) {
            Text("Center align")
            Text("short")
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .border()

        VStack(alignment: .trailing) {
            Text("Trailing align")
            Text("short")
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .border()
    }

    var environment = EnvironmentValues()
    environment.focusManager = FocusManager()
    let context = RenderContext(
        availableWidth: width,
        availableHeight: 12,
        environment: environment,
        tuiContext: TUIContext()
    )
    let buffer = renderToBuffer(view, context: context)
    return (buffer.lines, buffer.height)
}

@MainActor
@Suite("Content-alignment row keeps both Texts visible when squeezed")
struct AlignmentBoxSquishTests {

    /// Strips ANSI escape sequences so the assertions can compare against the
    /// visible content rather than the styled string.
    private func stripANSI(_ s: String) -> String {
        var result = ""
        var inEsc = false
        for ch in s {
            if ch == "\u{1B}" { inEsc = true; continue }
            if inEsc {
                if ch.isLetter { inEsc = false }
                continue
            }
            result.append(ch)
        }
        return result
    }

    @Test("At moderate squeeze 'short' stays fully visible in each box")
    func shortVisibleAtModerateSqueeze() {
        // 40 cells across three flexible boxes gives ~13 cells each — narrow
        // enough that the longer label wraps, but wide enough that "short"
        // still fits unbroken on its own line.
        let (lines, height) = renderRow(width: 40)
        let joined = lines.map(stripANSI).joined(separator: "\n")
        let occurrences = joined.components(separatedBy: "short").count - 1
        #expect(occurrences == 3, """
            Expected 'short' to appear in all three boxes at width 40:
            \(joined)
            """)
        #expect(height >= 5, "row should grow vertically to fit the wrapped label + 'short' + borders; got height \(height)")
    }

    @Test("Nested alignment row keeps 'short' visible across the wrap range")
    func nestedAlignmentRowShortVisible() {
        // The demo's two demo sections sit side by side; the trailing
        // section can end up squeezed to a width where the trailing
        // box's longest label wraps to two lines. Before HStack.sizeThatFits
        // also did a Pass 1.5 height re-measure, the wrapped box would
        // size to a 4-line natural height (2 inner + 2 border) and
        // PASS 2 would render the trailing wrapped text on lines 2/3 of
        // the box and clip "short" off the bottom. The fix mirrors the
        // renderer's width distribution during measurement, so the row's
        // reported height accounts for any child that wraps. This test
        // pins that the demo's failing widths now all keep "short" visible
        // in all three boxes.
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()

        func makeRow() -> AnyView {
            let panel = VStack(alignment: .leading) {
                Text("Panel (Header + Footer)").bold().underline()
                VStack(alignment: .leading) {
                    Text("Primary text (foreground)")
                    Text("Secondary text (foregroundSecondary)")
                    Text("Tertiary text (foregroundTertiary)")
                }
                .border()
            }
            let alignment = VStack(alignment: .leading) {
                Text("Content Alignment").bold().underline()
                HStack(spacing: 1) {
                    VStack(alignment: .leading) {
                        Text("Leading align")
                        Text("short")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .border()

                    VStack(alignment: .center) {
                        Text("Center align")
                        Text("short")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .border()

                    VStack(alignment: .trailing) {
                        Text("Trailing align")
                        Text("short")
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .border()
                }
            }
            return AnyView(HStack(spacing: 2) {
                panel
                alignment
            })
        }

        for width in [97, 90, 80] {
            let context = RenderContext(
                availableWidth: width,
                availableHeight: 24,
                environment: environment,
                tuiContext: TUIContext()
            )
            let buffer = renderToBuffer(makeRow(), context: context)
            let joined = buffer.lines.map(ansiStripped).joined(separator: "\n")
            let occurrences = joined.components(separatedBy: "short").count - 1
            // Widths 80+ should leave room for 'short' unbroken in every
            // box: at 80 each box is wide enough to fit the 5-char word
            // even after border + padding.
            #expect(occurrences == 3, """
                width \(width): expected 'short' in all three boxes, got \(occurrences):
                \(joined)
                """)
        }
    }

    @Test("Print squeezed Content Alignment row mirroring the FULL demo nesting")
    func printNestedAlignmentRowWithDemoSection() {
        // DemoSection adds a title row above its content. The two sections
        // sit beside each other in an HStack, so the row's children are the
        // section title + content blocks.
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()

        func makeRow() -> AnyView {
            let panel = VStack(alignment: .leading) {
                Text("Panel (Header + Footer)").bold().underline()
                VStack(alignment: .leading) {
                    Text("Primary text (foreground)")
                    Text("Secondary text (foregroundSecondary)")
                    Text("Tertiary text (foregroundTertiary)")
                }
                .border()
            }

            let alignment = VStack(alignment: .leading) {
                Text("Content Alignment").bold().underline()
                HStack(spacing: 1) {
                    VStack(alignment: .leading) {
                        Text("Leading align")
                        Text("short")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .border()

                    VStack(alignment: .center) {
                        Text("Center align")
                        Text("short")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .border()

                    VStack(alignment: .trailing) {
                        Text("Trailing align")
                        Text("short")
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .border()
                }
            }

            return AnyView(HStack(spacing: 2) {
                panel
                alignment
            })
        }

        for width in [120, 110, 100, 97, 90, 80, 70, 60, 50] {
            let context = RenderContext(
                availableWidth: width,
                availableHeight: 24,
                environment: environment,
                tuiContext: TUIContext()
            )
            let buffer = renderToBuffer(makeRow(), context: context)
            print("---- terminal width \(width) ----")
            for line in buffer.lines {
                print("|\(ansiStripped(line))|")
            }
        }
    }

    @Test("Print squeezed Content Alignment row mirroring the demo nesting")
    func printNestedAlignmentRow() {
        // Wraps the alignment row inside the same outer HStack as the demo
        // page (it sits beside a Panel column), so we exercise the
        // two-level flexible-width sharing instead of measuring the row
        // in isolation.
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()

        let alignmentRow = HStack(spacing: 1) {
            VStack(alignment: .leading) {
                Text("Leading align")
                Text("short")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .border()

            VStack(alignment: .center) {
                Text("Center align")
                Text("short")
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .border()

            VStack(alignment: .trailing) {
                Text("Trailing align")
                Text("short")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .border()
        }

        let pageRow = HStack(spacing: 2) {
            // Stand-in for the Panel column (a few lines of text)
            VStack(alignment: .leading) {
                Text("Primary text (foreground)")
                Text("Secondary text (foregroundSecondary)")
                Text("Tertiary text (foregroundTertiary)")
            }
            .border()

            alignmentRow
        }

        for width in [100, 90, 80, 70, 60, 50, 40] {
            let context = RenderContext(
                availableWidth: width,
                availableHeight: 20,
                environment: environment,
                tuiContext: TUIContext()
            )
            let buffer = renderToBuffer(pageRow, context: context)
            print("---- terminal width \(width) ----")
            for line in buffer.lines {
                let stripped = ansiStripped(line)
                print("|\(stripped)|")
            }
        }
    }

    private func ansiStripped(_ s: String) -> String {
        var result = ""
        var inEsc = false
        for ch in s {
            if ch == "\u{1B}" { inEsc = true; continue }
            if inEsc {
                if ch.isLetter { inEsc = false }
                continue
            }
            result.append(ch)
        }
        return result
    }

    @Test("Inner alignment HStack grows vertically when one child wraps")
    func innerHStackVerticalGrowth() {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()

        // The HStack alone, with availableWidth chosen so that the 18+18+17
        // split forces just the trailing box to wrap (it gets the smaller
        // 17 cells; inner = 17 - 2 - 2 = 13 < "Trailing align".count = 14).
        let row = HStack(spacing: 1) {
            VStack(alignment: .leading) {
                Text("Leading align")
                Text("short")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .border()

            VStack(alignment: .center) {
                Text("Center align")
                Text("short")
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .border()

            VStack(alignment: .trailing) {
                Text("Trailing align")
                Text("short")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .border()
        }

        // 53 cells of content + 2 spacings = 55 cells total. Distributing
        // 53 cells across 3 children gives [18, 18, 17].
        let context = RenderContext(
            availableWidth: 55,
            availableHeight: 24,
            environment: environment,
            tuiContext: TUIContext()
        )
        let buffer = renderToBuffer(row, context: context)
        for line in buffer.lines {
            print("|\(ansiStripped(line))|")
        }

        // All three boxes should be tall enough to host the trailing box's
        // wrapped label + "short", i.e. 5 lines total.
        #expect(buffer.height == 5, "expected row to be 5 lines tall, got \(buffer.height)")
        let allLines = buffer.lines.map(ansiStripped).joined(separator: "\n")
        let shortOccurrences = allLines.components(separatedBy: "short").count - 1
        #expect(shortOccurrences == 3,
                "expected 'short' to appear in all three boxes; got \(shortOccurrences)\n\(allLines)")
    }

    @Test("Single alignment box at narrow width reports wrapped height")
    func singleBoxWrappedHeight() {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()

        let trailing = VStack(alignment: .trailing) {
            Text("Trailing align")
            Text("short")
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .border()

        // Width 17 ← inner is 17 - 2 border - 2 padding = 13. "Trailing
        // align" is 14 chars so it must wrap, and the whole box should
        // therefore measure 5 lines tall (border + 3 inner + border).
        let context = RenderContext(
            availableWidth: 17,
            availableHeight: 24,
            environment: environment,
            tuiContext: TUIContext()
        )
        let buffer = renderToBuffer(trailing, context: context)
        for line in buffer.lines {
            print("|\(ansiStripped(line))|")
        }
        #expect(buffer.height == 5, "expected wrapped box to be 5 lines tall, got \(buffer.height)")
    }

    @Test("At extreme squeeze all three boxes still render")
    func allThreeBoxesPresentAtExtremeSqueeze() {
        // The flexible-width sharing should keep all three boxes visible even
        // when no single one can host the labels in full. The boxes truncate
        // their content rather than the row dropping a child entirely.
        let (lines, _) = renderRow(width: 22)
        let joined = lines.map(stripANSI).joined(separator: "\n")
        let topBorder = lines.first.map(stripANSI) ?? ""
        let openCount = topBorder.components(separatedBy: "╭").count - 1
        #expect(openCount == 3, """
            Expected three bordered boxes on the top edge at width 22:
            \(joined)
            """)
    }
}
