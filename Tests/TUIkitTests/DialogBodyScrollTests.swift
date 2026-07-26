//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DialogBodyScrollTests.swift
//
//  A `Dialog` too tall for the terminal scrolls its BODY, with the title and
//  the footer pinned. Those two are the parts that must survive a short
//  terminal: the title says what you are looking at, the footer holds
//  Done/Cancel.
//
//  The two alternatives both fail a requirement, which is why the body is the
//  thing that scrolls:
//    - Clipping the dialog (the old behaviour) drops the footer entirely.
//    - Scrolling the WHOLE dialog puts the footer at the bottom of scrollable
//      content, so a short terminal opens the dialog with no buttons visible.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Dialog body scrolling")
struct DialogBodyScrollTests {

    private func render<V: View>(_ view: V, width: Int, height: Int) -> [String] {
        let tui = TUIContext()
        var env = EnvironmentValues()
        env.focusManager = FocusManager()
        env.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: env, tuiContext: tui)
        tui.preferences.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
        return buffer.lines.map { $0.stripped }
    }

    private func tallDialog(rows: Int) -> some View {
        Dialog(title: "SETTINGS") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<rows, id: \.self) { Text("row \($0)") }
            }
        } footer: {
            Text("DONE")
        }
    }

    /// The core requirement.
    @Test("A too-tall dialog keeps its title and footer, and scrolls the body")
    func titleAndFooterSurviveOverflow() {
        let lines = render(tallDialog(rows: 40), width: 40, height: 14)
        let text = lines.joined(separator: "\n")

        #expect(lines.count <= 14, "the dialog fits the space it was given: \(lines.count)")
        #expect(text.contains("SETTINGS"), "the title survives:\n\(text)")
        #expect(text.contains("DONE"), "the footer survives:\n\(text)")
        #expect(text.contains("row 0"), "the body starts at its first row:\n\(text)")

        // THE load-bearing assertion, and the only one that separates scrolling
        // from the old behaviour. Clipping also kept the title and footer — they
        // are assembled outside the body — so asserting those alone passes
        // either way. What clipping did NOT do was make the overflow REACHABLE:
        // rows past the fold were simply gone, with nothing on screen to say so.
        // The scroll indicator is the proof that the rest can be got at.
        #expect(
            text.contains("more") || text.contains("\u{25BC}"),
            "the body's overflow is reachable, not silently dropped:\n\(text)")
    }

    /// The regression the always-on wrapper could have caused: a `ScrollView`
    /// swallows any definite proposed height, so a naive wrap inflates every
    /// short dialog to fill its whole container. The wrapper pins its frame to
    /// the body's natural height while it fits, which must leave a short dialog
    /// exactly the size it was.
    @Test("A dialog that fits is not inflated by the scrolling machinery")
    func shortDialogKeepsItsNaturalHeight() {
        let lines = render(tallDialog(rows: 3), width: 40, height: 40)
        let text = lines.joined(separator: "\n")

        // 3 body rows + 1 vertical padding each side + separator + footer +
        // 2 border rows — comfortably under 12, and nowhere near the 40 offered.
        #expect(
            lines.count <= 12,
            "a short dialog stays its natural size, got \(lines.count):\n\(text)")
        #expect(text.contains("row 0") && text.contains("row 2"), "all rows shown:\n\(text)")
        #expect(text.contains("DONE"), "footer shown:\n\(text)")
        // Nothing to scroll, so no scroll chrome leaks into a dialog that fits.
        #expect(!text.contains("more"), "no scroll indicator when it fits:\n\(text)")
    }

    /// An ordinary bordered container must NOT gain scrolling: that would add a
    /// focus stop and chrome to every `.border()` in the app. Only `Dialog` opts
    /// in.
    @Test("A plain bordered container still clips rather than scrolling")
    func plainContainerDoesNotScroll() {
        let boxed = VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<40, id: \.self) { Text("row \($0)") }
        }
        .border()

        let text = render(boxed, width: 40, height: 14).joined(separator: "\n")
        #expect(!text.contains("more"), "no scroll chrome on an ordinary border:\n\(text)")
    }
}
