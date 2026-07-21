//  🖥️ TUIKit — Terminal UI Kit for Swift
//  BindableTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Observation
import Testing

@testable import TUIkitView

@Observable
private final class BindableModel {
    var name = "a"
    var count = 0
}

@Suite("Bindable")
struct BindableTests {
    @Test("A derived binding reads and writes through the wrapped object")
    func derivedBindingRoundTrips() {
        let model = BindableModel()
        let bindable = Bindable(model)

        let name: Binding<String> = bindable.name
        #expect(name.wrappedValue == "a")
        name.wrappedValue = "z"
        #expect(model.name == "z", "writing the binding mutates the wrapped object in place")
        #expect(name.wrappedValue == "z", "the binding reflects the live object")
    }

    @Test("Distinct properties derive independent bindings")
    func independentBindings() {
        let model = BindableModel()
        let bindable = Bindable(model)
        bindable.count.wrappedValue = 7
        #expect(model.count == 7)
        #expect(model.name == "a", "writing one property leaves the others untouched")
    }

    @Test("projectedValue round-trips through init(projectedValue:)")
    func projectedValueRoundTrip() {
        let model = BindableModel()
        let rewrapped = Bindable(projectedValue: Bindable(model).projectedValue)
        rewrapped.name.wrappedValue = "q"
        #expect(model.name == "q")
    }
}
