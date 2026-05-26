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
