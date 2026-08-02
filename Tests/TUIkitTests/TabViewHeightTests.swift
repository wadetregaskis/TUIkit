//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TabViewHeightTests.swift
//
//  The bordered TabView's height contract: the panel fits the height it is
//  given, and the part that gives way is the content INSIDE the border — never
//  the border itself. GitHub issue #13: a tab holding a height-flexible view
//  (the reporter's log ScrollView) made the panel one row too tall, and the
//  final clamp then cut the bottom `╰─╯` off, leaving stray blank rows above
//  the status bar.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("TabView height contract")
struct TabViewHeightTests {

    private func render(_ view: some View, width: Int = 40, height: Int) -> FrameBuffer {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        var context = RenderContext(
            availableWidth: width, availableHeight: height, environment: environment,
            tuiContext: tui)
        context.hasExplicitWidth = true
        context.hasExplicitHeight = true
        return renderToBuffer(view, context: context)
    }

    private func borderedTabs(@ViewBuilder first: () -> some View) -> some View {
        TabView(selection: .constant(0)) {
            Tab("One", value: 0) { first() }
            Tab("Two", value: 1) { Text("hi") }
        }
        .tabViewStyle(.bordered)
    }

    /// Issue #13's shape: a tab whose content is height-flexible (a ScrollView)
    /// measures its natural height against the FULL available height — chrome
    /// not yet subtracted — so the panel padded itself past what fits and the
    /// clamp cut the bottom border, not the content.
    @Test("A height-flexible tab keeps the bottom border on screen")
    func flexibleTabKeepsBottomBorder() {
        let buffer = render(
            borderedTabs {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<50, id: \.self) { Text("row \($0)") }
                    }
                }
            },
            height: 16)

        #expect(buffer.height <= 16, "the panel fits the height it was given")
        #expect(
            buffer.lines.last?.stripped.contains("╰") == true,
            """
            the last row is the panel's bottom border, not a padding row:
            \(buffer.lines.map(\.stripped).joined(separator: "\n"))
            """)
    }

    /// The stronger case: content genuinely taller than the terminal. What
    /// gives way is rows of content inside the border — a bordered panel with
    /// its bottom cut off reads as broken chrome, and every other bordered
    /// container here clips content inside its frame.
    @Test("A tab taller than the terminal clips inside the border")
    func overTallTabClipsInsideTheBorder() {
        let buffer = render(
            borderedTabs {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<30, id: \.self) { Text("line \($0)") }
                }
            },
            height: 12)

        #expect(buffer.height <= 12)
        let stripped = buffer.lines.map(\.stripped)
        #expect(
            stripped.last?.contains("╰") == true,
            "border survives, content clips:\n\(stripped.joined(separator: "\n"))")
        #expect(
            stripped.contains { $0.contains("line 0") },
            "and the content's top is what remains visible")
    }

    /// The control case: a short tab still hugs its content — the fix must cap
    /// the panel, not inflate short panels to the full height.
    @Test("A short tab still sizes to its content")
    func shortTabStillHugs() {
        let buffer = render(borderedTabs { Text("just one line") }, height: 14)
        #expect(buffer.height < 14, "short content leaves the rest of the screen alone")
        #expect(buffer.lines.last?.stripped.contains("╰") == true)
    }

    /// Both tabs short but uneven: the panel still sizes to the tallest tab
    /// (the stable-height contract), so switching tabs does not change the box.
    @Test("Panel still sizes to the tallest tab when everything fits")
    func tallestTabStillGoverns() {
        let tall = TabView(selection: .constant(0)) {
            Tab("One", value: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("a"); Text("b"); Text("c"); Text("d")
                }
            }
            Tab("Two", value: 1) { Text("short") }
        }
        .tabViewStyle(.bordered)
        let short = TabView(selection: .constant(1)) {
            Tab("One", value: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("a"); Text("b"); Text("c"); Text("d")
                }
            }
            Tab("Two", value: 1) { Text("short") }
        }
        .tabViewStyle(.bordered)

        let tallBuffer = render(tall, height: 20)
        let shortBuffer = render(short, height: 20)
        #expect(
            tallBuffer.height == shortBuffer.height,
            "switching tabs must not change the panel height: \(tallBuffer.height) vs \(shortBuffer.height)")
    }
}
