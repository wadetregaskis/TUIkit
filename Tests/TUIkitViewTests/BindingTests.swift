//  🖥️ TUIKit — Terminal UI Kit for Swift
//  BindingTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkitView

@MainActor
@Suite("Binding Tests")
struct BindingTests {

    @Test("Binding reads value via getter")
    func bindingGetter() {
        nonisolated(unsafe) var value = 42
        let binding = Binding(get: { value }, set: { value = $0 })
        #expect(binding.wrappedValue == 42)
    }

    @Test("Binding writes value via setter")
    func bindingSetter() {
        nonisolated(unsafe) var value = 0
        let binding = Binding(get: { value }, set: { value = $0 })
        binding.wrappedValue = 99
        #expect(value == 99)
    }

    @Test("Binding projectedValue returns self")
    func bindingProjectedValue() {
        nonisolated(unsafe) var value = "hello"
        let binding = Binding(get: { value }, set: { value = $0 })
        let projected = binding.projectedValue
        projected.wrappedValue = "world"
        #expect(value == "world")
    }

    @Test("Binding.constant always returns same value")
    func bindingConstant() {
        let binding = Binding.constant(42)
        #expect(binding.wrappedValue == 42)
        binding.wrappedValue = 99
        #expect(binding.wrappedValue == 42)
    }

    @Test("Binding reflects external changes")
    func bindingReflectsChanges() {
        nonisolated(unsafe) var value = 1
        let binding = Binding(get: { value }, set: { value = $0 })
        value = 5
        #expect(binding.wrappedValue == 5)
    }
}

/// `Binding.defaulted(to:)` — substituting a value for `nil` so a control that
/// wants a `Binding<T>` can be handed one derived from a `Binding<T?>`.
///
/// The motivating case is a dictionary: `$dict[key]` is a `Binding<Value?>`,
/// because a key that isn't there has no value, and `$dict[key, default: x]`
/// cannot be written at all (an autoclosure argument cannot form the key path
/// a dynamic-member subscript needs — equally true of SwiftUI). Raised as
/// TUIkit issue #15.
@MainActor
@Suite("Defaulted optional bindings")
struct BindingDefaultedTests {

    @Test("A missing dictionary entry reads as the fallback")
    func missingEntryReadsTheFallback() {
        nonisolated(unsafe) var flags: [String: Bool] = ["b": true]
        let root = Binding(get: { flags }, set: { flags = $0 })

        #expect(root["a"].defaulted(to: false).wrappedValue == false)
        #expect(root["a"].defaulted(to: true).wrappedValue == true, "the fallback, not a hardcoded false")
        #expect(root["b"].defaulted(to: false).wrappedValue == true, "a present entry wins over it")
    }

    @Test("Writing reaches the dictionary")
    func writingReachesTheDictionary() {
        nonisolated(unsafe) var flags: [String: Bool] = [:]
        let root = Binding(get: { flags }, set: { flags = $0 })

        root["a"].defaulted(to: false).wrappedValue = true
        #expect(flags == ["a": true])
    }

    /// The documented behaviour, pinned so it cannot be "tidied" into removing
    /// the key: a write of the fallback still inserts. A binding whose setter
    /// sometimes deletes the thing it is bound to would be the bigger surprise,
    /// and a `Set` is the better model for a collection that should hold only
    /// what was chosen.
    @Test("Writing the fallback still creates the entry")
    func writingTheFallbackStillCreatesTheEntry() {
        nonisolated(unsafe) var flags: [String: Bool] = [:]
        let root = Binding(get: { flags }, set: { flags = $0 })
        let entry = root["a"].defaulted(to: false)

        entry.wrappedValue = true
        entry.wrappedValue = false
        #expect(flags == ["a": false], "off is a value, not an absence: \(flags)")
    }

    /// A plain value, not an `@autoclosure` like `Dictionary`'s own
    /// `subscript(_:default:)`. A binding is read every frame by every render
    /// pass that touches its control, so an expression re-evaluated per read
    /// would be evaluated a great many times to no purpose.
    @Test("The fallback is evaluated once, not per read")
    func theFallbackIsEvaluatedOnce() {
        nonisolated(unsafe) var flags: [String: Bool] = [:]
        nonisolated(unsafe) var evaluations = 0
        func fallback() -> Bool {
            evaluations += 1
            return false
        }

        let root = Binding(get: { flags }, set: { flags = $0 })
        let entry = root["a"].defaulted(to: fallback())
        for _ in 0..<5 { _ = entry.wrappedValue }

        #expect(evaluations == 1, "re-evaluated per read — has it become an autoclosure?")
    }

    @Test("It tracks the storage rather than snapshotting it")
    func itTracksTheStorage() {
        nonisolated(unsafe) var flags: [String: Bool] = [:]
        let entry = Binding(get: { flags }, set: { flags = $0 })["a"].defaulted(to: false)

        #expect(entry.wrappedValue == false)
        flags["a"] = true
        #expect(entry.wrappedValue == true, "a binding made before the entry existed still sees it")
    }

    /// Nothing about this is dictionary-specific — it is the shape of any
    /// optional. That generality is why it is a method on `Binding<T?>` rather
    /// than a dictionary-flavoured convenience on a control.
    @Test("It works on any optional, not just a dictionary entry")
    func itWorksOnAnyOptional() {
        struct Profile { var nickname: String? }

        nonisolated(unsafe) var profile = Profile(nickname: nil)
        let root = Binding(get: { profile }, set: { profile = $0 })
        let nickname = root.nickname.defaulted(to: "anonymous")

        #expect(nickname.wrappedValue == "anonymous")
        nickname.wrappedValue = "ada"
        #expect(profile.nickname == "ada")
    }
}
