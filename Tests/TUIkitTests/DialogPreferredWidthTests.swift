//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DialogPreferredWidthTests.swift
//
//  A dialog prefers a comfortable reading width, and spends more of the screen
//  only when that actually buys it vertical room.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("A dialog prefers a comfortable width")
struct DialogPreferredWidthTests {

    /// One long unbroken paragraph — it wraps, so it gets shorter as it widens.
    private static let paragraph = String(
        repeating: "the quick brown fox jumps over the lazy dog ", count: 24)

    private func render(
        _ view: some View, width: Int, height: Int, preferred: Int? = nil
    ) -> [String] {
        let tui = TUIContext()
        let focus = FocusManager()
        var env = EnvironmentValues()
        env.focusManager = focus
        env.applyRuntimeServices(from: tui)
        if let preferred { env.dialogPreferredWidth = preferred }
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: env, tuiContext: tui)
        focus.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focus.endRenderPass()
        return buffer.lines.map(\.stripped)
    }

    /// The dialog's BODY width in cells — the rendered box less its two border
    /// columns, since the preferred width governs the content, not the chrome.
    private func width(of lines: [String]) -> Int {
        max(0, (lines.map(\.count).max() ?? 0) - 2)
    }

    @Test("Prose wraps at the preferred width rather than running the full terminal")
    func prosePrefersComfortableWidth() {
        // 200 cells offered, 100 preferred, and plenty of height: the paragraph
        // fits when wrapped at 100, so the dialog has no reason to go wider.
        let lines = render(
            Dialog(title: "About") { Text(Self.paragraph) }, width: 200, height: 60)
        let dialogWidth = width(of: lines)
        #expect(
            dialogWidth <= 100,
            "the dialog stays at the comfortable width, not the 200 on offer: \(dialogWidth)")
        #expect(
            !lines.contains { $0.contains("▼") },
            "and it does not scroll — it had the height to wrap into")
    }

    @Test("The preferred width is configurable")
    func preferredWidthIsConfigurable() {
        let narrow = width(
            of: render(
                Dialog(title: "About") { Text(Self.paragraph) },
                width: 200, height: 60, preferred: 60))
        let wide = width(
            of: render(
                Dialog(title: "About") { Text(Self.paragraph) },
                width: 200, height: 60, preferred: 140))
        #expect(narrow <= 60, "a 60-cell preference wraps at 60: \(narrow)")
        #expect(wide > 100, "a 140-cell preference is allowed to be wider: \(wide)")
    }

    @Test("Prose spends the extra width when that is what makes it fit")
    func proseWidensWhenItBuysHeight() {
        // Same paragraph, but far too short a terminal to wrap it at 100. Going
        // wider makes it shorter, so the dialog should take the space.
        let lines = render(
            Dialog(title: "About") { Text(Self.paragraph) }, width: 200, height: 14)
        let dialogWidth = width(of: lines)
        #expect(
            dialogWidth > 100,
            "with no vertical room it widens to fit more per line: \(dialogWidth)")
    }

    @Test("Content that gains nothing from the width stays slim")
    func fixedContentStaysSlim() {
        // Short, unwrappable rows: widening cannot reduce the row count, so the
        // dialog must not sprawl across the terminal just because it overflows.
        let lines = render(
            Dialog(title: "Items") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<40, id: \.self) { Text("item \($0)") }
                }
            },
            width: 200, height: 14)
        let dialogWidth = width(of: lines)
        #expect(
            dialogWidth < 40,
            "widening buys no height here, so it hugs its content: \(dialogWidth)")
        #expect(
            lines.contains { $0.contains("▼") },
            """
            and it scrolls instead — 40 rows genuinely cannot fit in 14, and no             width makes them:
            \(lines.joined(separator: "\n"))
            """)
    }

    /// Content that cannot re-flow — a fixed grid, like the colour picker's 256
    /// swatches with their numbers showing — must not be CLIPPED to the
    /// comfortable width. The preference is a ceiling on how wide a dialog
    /// should get for readability; a body with a definite natural width has no
    /// narrower form to fall back to, and clamping it just cut off every column
    /// past the ceiling.
    @Test("A body that cannot re-flow is given its natural width, not clipped")
    func rigidBodyKeepsItsNaturalWidth() {
        // 120 cells wide whatever it is offered — the 256 grid's own report.
        struct RigidGrid: View, Renderable, Layoutable {
            static let naturalWidth = 120
            var body: Never { fatalError("renders via Renderable") }
            func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
                ViewSize(
                    width: Self.naturalWidth, height: 4,
                    isWidthFlexible: false, isHeightFlexible: false)
            }
            func renderToBuffer(context: RenderContext) -> FrameBuffer {
                FrameBuffer(
                    lines: Array(
                        repeating: String(repeating: "#", count: Self.naturalWidth), count: 4))
            }
        }

        // 200 cells on offer, 100 preferred, a body that insists on 120.
        let lines = render(Dialog(title: "Colours") { RigidGrid() }, width: 200, height: 40)
        let hashRun = lines.map { $0.filter { $0 == "#" }.count }.max() ?? 0
        #expect(
            hashRun == RigidGrid.naturalWidth,
            """
            the grid must render all \(RigidGrid.naturalWidth) of its cells; \
            the comfortable width guillotined it to \(hashRun)
            """)
    }
}
