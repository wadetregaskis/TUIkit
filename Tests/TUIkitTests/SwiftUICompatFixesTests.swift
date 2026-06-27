//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SwiftUICompatFixesTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitView

/// Regression coverage for the SwiftUI-parity fixes from
/// `Documentation/SwiftUI-compatibility.md` §3 (Binding dynamic-member lookup,
/// `@State.init(initialValue:)`, generic `Stepper`, data-driven `List`,
/// `task(id:)`, `sheet(onDismiss:)` / `sheet(item:)`, `navigationTitle`
/// overloads). Each test locks in the new public signature so it can't silently
/// regress.
@MainActor
@Suite("SwiftUI compatibility fixes (§3)")
struct SwiftUICompatFixesTests {

    // MARK: - §3.2 Binding dynamic-member lookup + init(projectedValue:)

    @Test("Binding derives a binding to a sub-property via dynamic-member lookup")
    func bindingDynamicMember() {
        struct Model { var name: String; var count: Int }
        var model = Model(name: "a", count: 1)
        let root = Binding(get: { model }, set: { model = $0 })

        let name = root.name        // $model.name
        name.wrappedValue = "z"     // write-through
        let count = root.count.wrappedValue
        #expect(model.name == "z")
        #expect(model.count == 1)   // sibling untouched
        #expect(count == 1)
    }

    @Test("Binding(projectedValue:) wraps an existing binding")
    func bindingProjectedValue() {
        let inner = Binding.constant(42)
        let outer = Binding(projectedValue: inner)
        #expect(outer.wrappedValue == 42)
    }

    // MARK: - §3.7 @State init(initialValue:)

    @Test("@State has an init(initialValue:) alias")
    func stateInitialValue() {
        let state = State(initialValue: 99)
        #expect(state.wrappedValue == 99)
    }

    // MARK: - §3.1 Stepper generic over the value type

    @Test("Stepper is generic over a Strideable value (Double)")
    func stepperOverDouble() {
        let view = Stepper("Temp", value: .constant(2.5), in: 0...10, step: 0.5)
        let buffer = renderToBuffer(view, context: makeBareRenderContext())
        let text = buffer.lines.map { $0.stripped }.joined()
        #expect(buffer.height == 1)
        #expect(text.contains("2.5"), "shows the Double value: \(text)")
    }

    @Test("Stepper still accepts Int values")
    func stepperOverInt() {
        let buffer = renderToBuffer(
            Stepper("Qty", value: .constant(7), in: 0...10), context: makeBareRenderContext())
        let text = buffer.lines.map { $0.stripped }.joined()
        #expect(text.contains("7"))
    }

    // MARK: - §3.4 Data-driven List initializers

    @Test("List has data-driven initializers (Identifiable + id:, all selection modes)")
    func dataDrivenList() {
        struct Row: Identifiable { let id: Int; let name: String }
        struct Plain { let key: String; let label: String }
        let rows = [Row(id: 1, name: "Alpha"), Row(id: 2, name: "Beta")]
        let items = [Plain(key: "a", label: "AAA"), Plain(key: "b", label: "BBB")]
        let ctx = makeRenderContext(width: 30, height: 10)
        func text(_ view: some View) -> String {
            renderToBuffer(view, context: ctx).lines.map { $0.stripped }.joined(separator: "\n")
        }

        // Identifiable: no selection / single / multi.
        let plain = text(List(rows) { Text($0.name) })
        let single = text(List(rows, selection: .constant(Int?.none)) { Text($0.name) })
        let multi = text(List(rows, selection: .constant(Set<Int>())) { Text($0.name) })
        // Explicit id: key path, no selection / single.
        let keyed = text(List(items, id: \.key) { Text($0.label) })
        let keyedSel = text(List(items, id: \.key, selection: .constant(String?.none)) { Text($0.label) })

        #expect(plain.contains("Alpha"))
        #expect(single.contains("Beta"))
        #expect(multi.contains("Alpha"))
        #expect(keyed.contains("AAA"))
        #expect(keyedSel.contains("BBB"))
    }

    // MARK: - §3.8 / §3.5 / §3.10 signature regression guards

    @Test("task(id:), sheet(onDismiss:)/sheet(item:), navigationTitle overloads resolve")
    func newModifierSignatures() {
        struct Item: Identifiable { let id: Int }

        // Compile-time guard: every new overload must keep resolving.
        func build() -> some View {
            Text("base")
                .task(id: 7) {}
                .task(id: "query", priority: .high) {}
                .sheet(isPresented: .constant(false), onDismiss: {}, content: { Text("sheet") })
                .sheet(item: .constant(Item?.none)) { item in Text("\(item.id)") }
        }
        _ = build()

        // navigationTitle: Substring (StringProtocol) / Text both resolve and
        // still render their content.
        let titled = Text("body")
            .navigationTitle("Home".dropFirst())   // Substring
            .navigationTitle(Text("Title"))
        let text = renderToBuffer(titled, context: makeBareRenderContext()).lines
            .map { $0.stripped }.joined()
        #expect(text.contains("body"))
    }
}
