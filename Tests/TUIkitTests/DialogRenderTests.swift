//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DialogRenderTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Test Helpers

/// Creates a render context with a fresh FocusManager for isolated testing.
@MainActor
private func createTestContext(width: Int = 30, height: Int = 8) -> RenderContext {
    makeRenderContext(width: width, height: height)
}

@MainActor
private func strippedLines<V: View>(_ view: V, width: Int = 30, height: Int = 8) -> [String] {
    renderToBuffer(view, context: createTestContext(width: width, height: height))
        .lines.map { $0.stripped }
}

// MARK: - Dialog Rendering Tests

@MainActor
@Suite("Dialog rendering")
struct DialogRenderTests {

    // MARK: Title in top border

    @Test("Simple dialog renders the title in the top border with padded body")
    func dialogSimple() {
        // Default padding is horizontal 2, vertical 1.
        let lines = strippedLines(Dialog(title: "Settings") { Text("Opt 1") })

        #expect(lines.count == 5)
        #expect(lines[0] == "╭─ Settings ─╮")
        #expect(lines[1] == "│            │")
        #expect(lines[2] == "│  Opt 1     │")
        #expect(lines[3] == "│            │")
        #expect(lines[4] == "╰────────────╯")
    }

    @Test("Dialog horizontal padding indents the body by two cells")
    func dialogHorizontalPadding() {
        let lines = strippedLines(Dialog(title: "Settings") { Text("Opt 1") })
        // "  Opt 1" — two leading spaces from horizontal:2 padding, inside the
        // left border.
        let body = lines[2]
        #expect(body.hasPrefix("│  Opt 1"))
    }

    @Test("All dialog rows share one width")
    func dialogUniformWidth() {
        let buffer = renderToBuffer(Dialog(title: "Settings") { Text("Opt 1") }, context: createTestContext())
        let widths = Set(buffer.lines.map { $0.stripped.count })
        #expect(widths.count == 1)
    }

    // MARK: Footer

    @Test("Footer sits below a T-junction divider")
    func dialogFooterSeparator() {
        let lines = strippedLines(Dialog(title: "Confirm") {
            Text("Sure?")
        } footer: {
            Text("[Yes]")
        }, width: 30, height: 10)

        #expect(lines[0].hasPrefix("╭─ Confirm "))
        #expect(lines[0].hasSuffix("╮"))
        // The divider row uses ├ ┤ junctions.
        let dividerRow = lines.first { $0.hasPrefix("├") }
        #expect(dividerRow != nil)
        #expect(dividerRow!.hasSuffix("┤"))
        // The divider is solid horizontal between the junctions (no gaps).
        #expect(dividerRow!.dropFirst().dropLast().allSatisfy { $0 == "─" })
        // Footer content appears after the divider, before the bottom border.
        let dividerIndex = lines.firstIndex { $0.hasPrefix("├") }!
        let footerIndex = lines.firstIndex { $0.contains("[Yes]") }!
        #expect(footerIndex > dividerIndex)
        #expect(lines.last!.hasPrefix("╰"))
        #expect(lines.last!.hasSuffix("╯"))
    }

    @Test("Footer defaults to leading alignment")
    func dialogFooterLeadingByDefault() {
        let lines = strippedLines(Dialog(title: "T") {
            Text(String(repeating: "x", count: 24))  // a wide body sets the box width
        } footer: {
            Text("[OK]")
        }, width: 40, height: 10)
        let footer = lines.first { $0.contains("[OK]") }!
        let inner = String(footer.dropFirst().dropLast())  // strip the two side borders
        let lead = inner.prefix { $0 == " " }.count
        #expect(lead <= 1, "footer sits at the leading edge by default, lead=\(lead)")
    }

    @Test("footerAlignment .center centres the footer and keeps it clickable")
    func dialogFooterCentred() {
        var clicked = false
        let tui = TUIContext()
        let fm = FocusManager()
        var env = EnvironmentValues()
        env.focusManager = fm
        env.mouseEventDispatcher = tui.mouseEventDispatcher
        let ctx = RenderContext(availableWidth: 40, availableHeight: 10, environment: env, tuiContext: tui)
            .isolatingRenderCache()
        let view = Dialog(title: "T", footerAlignment: .center) {
            Text(String(repeating: "x", count: 24))
        } footer: {
            Button("OK") { clicked = true }
        }
        fm.beginRenderPass()
        let buffer = renderToBuffer(view, context: ctx)
        fm.endRenderPass()

        let footer = buffer.lines.map { $0.stripped }.first { $0.contains("OK") }!
        let inner = Array(String(footer.dropFirst().dropLast()))
        let lead = inner.prefix { $0 == " " }.count
        let trail = inner.reversed().prefix { $0 == " " }.count
        #expect(lead > 1, "footer is centred, not at the leading edge (lead=\(lead))")
        #expect(abs(lead - trail) <= 1, "footer is centred: lead=\(lead) trail=\(trail)")

        // The button's hit region (the lowest, in the footer) tracks the centred
        // glyph, so a click on it still fires.
        guard let r = buffer.hitTestRegions.max(by: { $0.offsetY < $1.offsetY }) else {
            Issue.record("no footer hit region")
            return
        }
        tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
        let x = r.offsetX + r.width / 2
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: r.offsetY))
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: r.offsetY))
        #expect(clicked, "the centred footer button is clickable")
    }

    @Test("Footer-bearing dialog keeps a continuous rectangle (uniform width)")
    func dialogFooterUniformWidth() {
        let buffer = renderToBuffer(
            Dialog(title: "Confirm") { Text("Sure?") } footer: { Text("[Yes]") },
            context: createTestContext(width: 30, height: 10))
        let widths = Set(buffer.lines.map { $0.stripped.count })
        #expect(widths.count == 1)
    }

    // MARK: Border styles

    @Test("doubleLine convenience produces a double-line bordered dialog")
    func dialogDoubleLineConvenience() {
        let dialog = Dialog<Text, EmptyView>.doubleLine(title: "DL") { Text("x") }
        let lines = strippedLines(dialog)

        #expect(lines.count == 5)
        #expect(lines[0] == "╔═ DL ═╗")
        #expect(lines[2] == "║  x   ║")
        #expect(lines[4] == "╚══════╝")
    }

    @Test("heavy convenience produces a heavy bordered dialog")
    func dialogHeavyConvenience() {
        let dialog = Dialog<Text, EmptyView>.heavy(title: "H") { Text("x") }
        let lines = strippedLines(dialog)
        #expect(lines.first!.hasPrefix("┏"))
        #expect(lines.first!.hasSuffix("┓"))
        #expect(lines.last!.hasPrefix("┗"))
        #expect(lines.last!.hasSuffix("┛"))
    }

    // MARK: Multi-line content

    @Test("Multi-line body renders each line in order with no gaps")
    func dialogMultiline() {
        let lines = strippedLines(Dialog(title: "List") {
            Text("Opt 1")
            Text("Opt 2")
        }, width: 30, height: 10)

        let bodyRows = lines.filter { $0.contains("Opt") }
        #expect(bodyRows.count == 2)
        #expect(bodyRows[0].contains("Opt 1"))
        #expect(bodyRows[1].contains("Opt 2"))
    }

    // MARK: Narrow / truncation

    @Test("Narrow dialog truncates the title but closes the top border")
    func dialogNarrowTitleTruncates() {
        let lines = strippedLines(Dialog(title: "LongTitleName") {
            Text("body text wide")
        }, width: 12, height: 6)

        #expect(lines[0] == "╭─ LongTit ╮")
        #expect(lines.first!.hasSuffix("╮"))
        #expect(lines.last! == "╰──────────╯")
        #expect(lines.allSatisfy { $0.count == 12 })
    }

    @Test("Narrow dialog ellipsises over-long body text rather than overflowing")
    func dialogNarrowBodyEllipsis() {
        let buffer = renderToBuffer(
            Dialog(title: "LongTitleName") { Text("body text wide") },
            context: createTestContext(width: 12, height: 6))
        let lines = buffer.lines.map { $0.stripped }
        #expect(lines.contains { $0.contains("…") })
        #expect(lines.allSatisfy { $0.count <= 12 })
    }

    // MARK: Wide

    @Test("Wide context: dialog hugs its content rather than filling the width")
    func dialogWideStaysContentSized() {
        let buffer = renderToBuffer(Dialog(title: "Hi") { Text("short") }, context: createTestContext(width: 60, height: 8))
        #expect(buffer.width < 60)
        let widths = Set(buffer.lines.map { $0.stripped.count })
        #expect(widths.count == 1)
    }
}
