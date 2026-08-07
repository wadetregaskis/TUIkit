//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ForEachBindingTests.swift
//
//  `ForEach($items) { $item in … }` — a row of editable controls needs a
//  binding per element, not a value per element.
//
//  Raised as TUIkit issue #15, which reported it as `Toggle` being unaware of
//  `ForEach`. It is not: `Toggle` takes a `Binding<Bool>` exactly as SwiftUI's
//  does, and works in a `ForEach` given one. The snippet in that report fails
//  to compile against real SwiftUI too, with the identical diagnostic — the
//  missing piece was this initializer.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("ForEach over a binding")
struct ForEachBindingTests {

    private struct Option: Identifiable {
        let id: String
        var enabled: Bool
    }

    /// Editing through a row's binding must reach the array the ForEach was
    /// given — the whole point of the overload.
    @Test("A row's binding writes back to the collection")
    func rowBindingWritesThrough() {
        var options = [
            Option(id: "verbose", enabled: false),
            Option(id: "colour", enabled: true),
        ]
        let binding = Binding(get: { options }, set: { options = $0 })
        let rows = ForEach<[Binding<Option>], String, EmptyView>.elementBindings(binding)

        #expect(rows.count == 2)
        rows[0].wrappedValue.enabled = true
        rows[1].wrappedValue.enabled = false
        #expect(options.map(\.enabled) == [true, false], "edits reached the array: \(options)")
    }

    /// A row's binding outlives the frame that made it. If the collection
    /// shrinks first, reading must not trap — an unguarded subscript would.
    @Test("A binding for a row that has gone reads and writes safely")
    func staleRowBindingDoesNotTrap() {
        var options = [
            Option(id: "a", enabled: true),
            Option(id: "b", enabled: false),
        ]
        let binding = Binding(get: { options }, set: { options = $0 })
        let rows = ForEach<[Binding<Option>], String, EmptyView>.elementBindings(binding)

        options.removeLast()
        // Reads fall back to what the row last held…
        #expect(rows[1].wrappedValue.id == "b")
        // …and writes past the end are dropped rather than trapping or growing.
        rows[1].wrappedValue.enabled = true
        #expect(options.count == 1, "the collection is unchanged: \(options)")
    }

    /// The identity key path names a property of the ELEMENT, as in SwiftUI —
    /// callers never write `\.wrappedValue.name`.
    @Test("The id key path is the element's, not the binding's")
    func idKeyPathIsRebased() {
        var names = ["alpha", "beta"]
        let binding = Binding(get: { names }, set: { names = $0 })
        let forEach = ForEach(binding, id: \.self) { (name: Binding<String>) in
            Text(name.wrappedValue)
        }
        let ids = forEach.data.map { $0[keyPath: forEach.idKeyPath] }
        #expect(ids == ["alpha", "beta"], "ids read through to the elements: \(ids)")
    }

    /// The rows render, and each row's own state reaches its own control.
    @Test("A ForEach of Toggles renders one row per element")
    func togglesRenderPerElement() {
        var options = [
            Option(id: "one", enabled: true),
            Option(id: "two", enabled: false),
        ]
        let binding = Binding(get: { options }, set: { options = $0 })
        let tui = TUIContext()
        var env = EnvironmentValues()
        env.focusManager = FocusManager()
        env.applyRuntimeServices(from: tui)
        let view = VStack {
            ForEach(binding) { option in
                Toggle(option.wrappedValue.id, isOn: option.enabled)
            }
        }
        let context = RenderContext(
            availableWidth: 30, availableHeight: 10, environment: env, tuiContext: tui)
        let buffer = renderToBuffer(view, context: context)
        let text = buffer.lines.map(\.stripped).joined(separator: "\n")
        #expect(text.contains("one"), "first row drawn: \(text)")
        #expect(text.contains("two"), "second row drawn: \(text)")
    }
}
