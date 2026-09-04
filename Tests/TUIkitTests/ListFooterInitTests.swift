//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListFooterInitTests.swift
//
//  `List` has nine `footer:` initializers — three selection shapes × three
//  title shapes — and every one of them assigns all eight stored properties by
//  hand; there is no shared designated init to drift against. Only the titled
//  single-selection pair had ever run.
//
//  The compiler catches a MISSING assignment. It cannot catch a wrong one:
//  `showFooterSeparator = false` in a footer init, or `multiSelection` left nil
//  in the multi-selection one, both compile and both silently change what the
//  app does — the second disables selection entirely for
//  `List(selection: $set) { … } footer: { … }`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("List footer initializers")
struct ListFooterInitTests {

    private static let rows = ["A", "B"]

    /// A sink for a selection binding, so the assertions can read back what a
    /// key press wrote.
    private final class Sink<Value>: @unchecked Sendable {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    private func context() -> RenderContext {
        makeRenderContext(width: 26, height: 10)
    }

    private func lines(_ view: some View, in context: RenderContext) -> [String] {
        renderToBuffer(view, context: context).lines.map(\.stripped)
    }

    /// The footer text sits below a `├───┤` rule, which is the whole visible
    /// difference between a `footer:` init and a `Footer == EmptyView` one.
    private func expectFooteredBox(
        _ lines: [String],
        title: String?,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            lines.contains { $0.hasPrefix("├") && $0.hasSuffix("┤") },
            "no footer separator rule: \(lines)", sourceLocation: sourceLocation)
        #expect(
            lines.contains { $0.contains("FOOT") },
            "no footer text: \(lines)", sourceLocation: sourceLocation)
        #expect(
            lines.contains { $0.contains("A") } && lines.contains { $0.contains("B") },
            "the rows went missing: \(lines)", sourceLocation: sourceLocation)
        if let title {
            #expect(
                lines.first?.contains(title) == true,
                "the title is not in the top border: \(lines)", sourceLocation: sourceLocation)
        } else {
            #expect(
                lines.first?.allSatisfy { $0 == "┌" || $0 == "─" || $0 == "╭" || $0 == "┐" || $0 == "╮" } == true,
                "an untitled list drew a title: \(lines)", sourceLocation: sourceLocation)
        }
    }

    // MARK: - Single selection

    @Test("The three single-selection footer initializers draw the footer and bind the selection")
    func singleSelectionFooterInits() {
        // A literal title (the LocalizedStringKey overload), a runtime title
        // (the `StringProtocol` twin it forwards to), and no title at all.
        let titled = Sink<String?>(nil)
        let asWritten = Sink<String?>(nil)
        let untitled = Sink<String?>(nil)
        let runtimeTitle = "Files" + ""

        func binding(_ sink: Sink<String?>) -> Binding<String?> {
            Binding(get: { sink.value }, set: { sink.value = $0 })
        }

        let cases: [(view: AnyView, title: String?, sink: Sink<String?>)] = [
            (
                AnyView(
                    List("Files", selection: binding(titled)) {
                        ForEach(Self.rows, id: \.self) { Text($0) }
                    } footer: {
                        Text(verbatim: "FOOT")
                    }), "Files", titled
            ),
            (
                AnyView(
                    List(runtimeTitle, selection: binding(asWritten)) {
                        ForEach(Self.rows, id: \.self) { Text($0) }
                    } footer: {
                        Text(verbatim: "FOOT")
                    }), "Files", asWritten
            ),
            (
                AnyView(
                    List(selection: binding(untitled)) {
                        ForEach(Self.rows, id: \.self) { Text($0) }
                    } footer: {
                        Text(verbatim: "FOOT")
                    }), nil, untitled
            ),
        ]

        for (view, title, sink) in cases {
            let context = self.context()
            expectFooteredBox(lines(view, in: context), title: title)
            // End to end, because a nil `singleSelection` renders identically:
            // Enter on the focused row must reach the binding.
            _ = context.environment.focusManager?.dispatchKeyEvent(KeyEvent(key: .enter))
            #expect(sink.value == "A", "the selection binding was not wired")
        }
    }

    // MARK: - Multi selection

    @Test("The three multi-selection footer initializers draw the footer and bind the Set")
    func multiSelectionFooterInits() {
        let titled = Sink<Set<String>>([])
        let asWritten = Sink<Set<String>>([])
        let untitled = Sink<Set<String>>([])
        let runtimeTitle = "Files" + ""

        func binding(_ sink: Sink<Set<String>>) -> Binding<Set<String>> {
            Binding(get: { sink.value }, set: { sink.value = $0 })
        }

        let cases: [(view: AnyView, title: String?, sink: Sink<Set<String>>)] = [
            (
                AnyView(
                    List("Files", selection: binding(titled)) {
                        ForEach(Self.rows, id: \.self) { Text($0) }
                    } footer: {
                        Text(verbatim: "FOOT")
                    }), "Files", titled
            ),
            (
                AnyView(
                    List(runtimeTitle, selection: binding(asWritten)) {
                        ForEach(Self.rows, id: \.self) { Text($0) }
                    } footer: {
                        Text(verbatim: "FOOT")
                    }), "Files", asWritten
            ),
            (
                AnyView(
                    List(selection: binding(untitled)) {
                        ForEach(Self.rows, id: \.self) { Text($0) }
                    } footer: {
                        Text(verbatim: "FOOT")
                    }), nil, untitled
            ),
        ]

        for (view, title, sink) in cases {
            let context = self.context()
            expectFooteredBox(lines(view, in: context), title: title)
            // The failure this catches: `multiSelection` left nil makes the
            // list single-selection, so Enter writes nothing to the Set.
            _ = context.environment.focusManager?.dispatchKeyEvent(KeyEvent(key: .enter))
            #expect(sink.value == ["A"], "the Set binding was not wired")
        }
    }

    // MARK: - No selection

    @Test("The three selectionless footer initializers draw the footer")
    func selectionlessFooterInits() {
        let runtimeTitle = "Files" + ""

        // `SelectionValue` is spelled out: the selectionless FOOTER
        // initializers live on the unconstrained extension, so unlike their
        // `Footer == EmptyView` siblings (which default it to `Int`) there is
        // nothing in the call to infer it from.
        expectFooteredBox(
            lines(
                List<Int, _, _>("Files") {
                    ForEach(Self.rows, id: \.self) { Text($0) }
                } footer: {
                    Text(verbatim: "FOOT")
                }, in: context()), title: "Files")

        expectFooteredBox(
            lines(
                List<Int, _, _>(runtimeTitle) {
                    ForEach(Self.rows, id: \.self) { Text($0) }
                } footer: {
                    Text(verbatim: "FOOT")
                }, in: context()), title: "Files")

        expectFooteredBox(
            lines(
                List<Int, _, _> {
                    ForEach(Self.rows, id: \.self) { Text($0) }
                } footer: {
                    Text(verbatim: "FOOT")
                }, in: context()), title: nil)
    }

    // MARK: - The other half of the same default

    /// Every `footer:` init sets `showFooterSeparator = true`; every
    /// `Footer == EmptyView` one sets it `false`. Without this half, an init
    /// that set the flag the wrong way round in the no-footer family would go
    /// unnoticed — there is no footer, but the rule would still be drawn.
    @Test("The selectionless initializers without a footer draw no rule")
    func selectionlessWithoutFooter() {
        let runtimeTitle = "Files" + ""
        let views: [AnyView] = [
            AnyView(List("Files") { ForEach(Self.rows, id: \.self) { Text($0) } }),
            AnyView(List(runtimeTitle) { ForEach(Self.rows, id: \.self) { Text($0) } }),
            AnyView(List { ForEach(Self.rows, id: \.self) { Text($0) } }),
        ]

        for view in views {
            let rendered = lines(view, in: context())
            #expect(
                !rendered.contains { $0.hasPrefix("├") },
                "a list with no footer drew a footer rule: \(rendered)")
            #expect(rendered.contains { $0.contains("A") }, "the rows went missing: \(rendered)")
        }
    }
}
