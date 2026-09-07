//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContainerDisabledCascadeTests.swift
//
//  SwiftUI: "The higher views in a view hierarchy can override the value you
//  set on this view." Every control here already ORs `\.isEnabled` into its own
//  flag — except List, Table and ScrollView, which read neither. Their concrete
//  `disabled(_:) -> Self` overloads win overload resolution, so their OWN
//  .disabled(true) worked and hid the fact that an ancestor's did nothing at
//  all: a List inside a disabled subtree still took Tab, still scrolled, still
//  moved its selection.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("container disabled cascade")
struct ContainerDisabledCascadeTests {
    private struct Person: Identifiable, Hashable {
        let id: Int
        let name: String
    }

    private let people = [Person(id: 1, name: "Mei"), Person(id: 2, name: "Ada")]

    /// Renders `view` and reports whether anything in it became focusable.
    private func registersFocus<V: View>(_ view: V) -> Bool {
        let focusManager = FocusManager()
        let context = makeRenderContext(width: 40, height: 12) { environment, _ in
            environment.focusManager = focusManager
        }
        focusManager.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        focusManager.focusNext()
        return focusManager.currentFocusedID != nil
    }

    @Test("An ancestor's disabled(true) reaches a List")
    func listHonoursAncestor() {
        let list = List(selection: .constant(Int?.none)) {
            ForEach(people) { Text($0.name) }
        }
        #expect(registersFocus(VStack { list }), "the control case: it is focusable")
        #expect(!registersFocus(VStack { list }.disabled(true)), "an ancestor disables it")
        #expect(!registersFocus(VStack { list.disabled(true) }), "and so does its own")
    }

    @Test("An ancestor's disabled(true) reaches a Table")
    func tableHonoursAncestor() {
        let table = Table(people, selection: .constant(Int?.none)) {
            TableColumn("Name", value: \.name)
        }
        #expect(registersFocus(VStack { table }), "the control case: it is focusable")
        #expect(!registersFocus(VStack { table }.disabled(true)), "an ancestor disables it")
    }

    @Test("An ancestor's disabled(true) reaches a ScrollView")
    func scrollViewHonoursAncestor() {
        // Tall content, so the view overflows and would otherwise be a Tab stop.
        let scroll = ScrollView {
            VStack { ForEach(0..<40) { Text("row \($0)") } }
        }
        #expect(registersFocus(VStack { scroll }), "the control case: it is focusable")
        #expect(!registersFocus(VStack { scroll }.disabled(true)), "an ancestor disables it")
    }

    @Test("disabled(false) on an ancestor does not re-enable a disabled child")
    func disabledIsAdditive() {
        // SwiftUI is explicit that the outer value wins, so the inner
        // `.disabled(false)` escape hatch must not work.
        let list = List(selection: .constant(Int?.none)) {
            ForEach(people) { Text($0.name) }
        }
        #expect(!registersFocus(VStack { list.disabled(false) }.disabled(true)))
    }

    /// The other direction, and the half this suite was missing.
    ///
    /// Reading `\.isEnabled` fixed an ancestor's `.disabled(true)` reaching
    /// these three. It did not make their OWN `.disabled(true)` reach what is
    /// inside them: the concrete `disabled(_:) -> Self` sets a stored flag that
    /// governs the container's focusability and nothing else, so it never
    /// publishes `\.isEnabled` down. SwiftUI's `.disabled(_:)` is defined on
    /// the subtree — "disables interaction in this view and its child views" —
    /// so a `Button` inside a disabled `ScrollView` must be disabled, and here
    /// it stayed focusable, clickable and actionable.
    @Test("A container's own disabled(true) reaches the controls inside it")
    func containerDisablesItsOwnContent() {
        let scroll = ScrollView { Button("Save") {} }
        #expect(registersFocus(scroll), "the control case: the button is focusable")
        #expect(!registersFocus(scroll.disabled(true)), "the button inside is disabled too")

        let list = List(selection: .constant(Int?.none)) {
            Button("Save") {}
        }
        #expect(registersFocus(list), "the control case: the list is focusable")
        #expect(!registersFocus(list.disabled(true)), "and its rows go with it")

        let table = Table(people, selection: .constant(Int?.none)) {
            TableColumn("Name", value: \.name)
        }
        #expect(registersFocus(table), "the control case")
        #expect(!registersFocus(table.disabled(true)), "its own disable still holds")
    }
}
