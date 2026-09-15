//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EnvironmentTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

/// Custom environment key for testing.
private struct TestStringKey: EnvironmentKey {
    static let defaultValue: String = "default"
}

/// Another custom key for independence tests.
private struct TestIntKey: EnvironmentKey {
    static let defaultValue: Int = 0
}

extension EnvironmentValues {
    fileprivate var testString: String {
        get { self[TestStringKey.self] }
        set { self[TestStringKey.self] = newValue }
    }

    fileprivate var testInt: Int {
        get { self[TestIntKey.self] }
        set { self[TestIntKey.self] = newValue }
    }
}

// MARK: - EnvironmentValues Tests

@MainActor
@Suite("EnvironmentValues Tests")
struct EnvironmentValuesTests {

    @Test("Empty environment returns default values")
    func emptyDefaults() {
        let env = EnvironmentValues()
        #expect(env[TestStringKey.self] == "default")
        #expect(env[TestIntKey.self] == 0)
    }

    @Test("Set and get value via subscript")
    func setAndGet() {
        var env = EnvironmentValues()
        env[TestStringKey.self] = "custom"
        #expect(env[TestStringKey.self] == "custom")
    }

    @Test("Different keys are independent")
    func independentKeys() {
        var env = EnvironmentValues()
        env[TestStringKey.self] = "hello"
        env[TestIntKey.self] = 42
        #expect(env[TestStringKey.self] == "hello")
        #expect(env[TestIntKey.self] == 42)
    }

    @Test("setting() returns new copy with modified value")
    func settingCopy() {
        let original = EnvironmentValues()
        let modified = original.setting(\.testString, to: "changed")
        #expect(modified.testString == "changed")
        #expect(original.testString == "default")  // original unchanged
    }

    @Test("setting() preserves other values")
    func settingPreservesOthers() {
        var env = EnvironmentValues()
        env.testInt = 99
        let modified = env.setting(\.testString, to: "new")
        #expect(modified.testString == "new")
        #expect(modified.testInt == 99)  // preserved
    }
}

// MARK: - EnvironmentModifier Tests

@MainActor
@Suite("EnvironmentModifier Tests")
struct EnvironmentModifierTests {

    @Test("EnvironmentModifier propagates value to child")
    func propagatesToChild() {
        // Create a view that reads the environment and renders it
        let view = EnvironmentReaderView()
            .environment(\.testString, "injected")

        let context = RenderContext(
            availableWidth: 80,
            availableHeight: 24,
            environment: EnvironmentValues(),
            tuiContext: TUIContext()
        ).isolatingRenderCache()

        let buffer = renderToBuffer(view, context: context)
        let content = buffer.lines.joined()

        #expect(content.contains("injected"))
    }

    @Test("Environment value inherits through nested views")
    func inheritsThroughNesting() {
        // Wrapper -> Inner -> Reader
        let view = WrapperView {
            InnerView {
                EnvironmentReaderView()
            }
        }
        .environment(\.testString, "nested-value")

        let context = RenderContext(
            availableWidth: 80,
            availableHeight: 24,
            environment: EnvironmentValues(),
            tuiContext: TUIContext()
        ).isolatingRenderCache()

        let buffer = renderToBuffer(view, context: context)
        let content = buffer.lines.joined()

        #expect(content.contains("nested-value"))
    }

    @Test("Child can override parent environment value")
    func childOverridesParent() {
        let view = WrapperView {
            EnvironmentReaderView()
                .environment(\.testString, "child-value")
        }
        .environment(\.testString, "parent-value")

        let context = RenderContext(
            availableWidth: 80,
            availableHeight: 24,
            environment: EnvironmentValues(),
            tuiContext: TUIContext()
        ).isolatingRenderCache()

        let buffer = renderToBuffer(view, context: context)
        let content = buffer.lines.joined()

        #expect(content.contains("child-value"))
        #expect(!content.contains("parent-value"))
    }
}

// MARK: - Test Helper Views

/// A view with real body that reads an environment value.
private struct EnvironmentReaderView: View, Renderable {
    var body: Never { fatalError("EnvironmentReaderView renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let value = context.environment.testString
        return FrameBuffer(lines: ["Value: \(value)"])
    }
}

/// A simple wrapper view with real body.
private struct WrapperView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
    }
}

/// Another wrapper to test nesting.
private struct InnerView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
    }
}

// MARK: - ForegroundStyle Propagation Tests

@MainActor
@Suite("ForegroundStyle Propagation Tests")
struct ForegroundStylePropagationTests {

    @Test("foregroundStyle on parent affects Text child")
    func parentStyleAffectsTextChild() {
        // VStack with foregroundStyle should affect Text inside
        let view = VStack {
            Text("Hello")
        }
        .foregroundStyle(.red)

        let context = RenderContext(
            availableWidth: 80,
            availableHeight: 24,
            environment: EnvironmentValues(),
            tuiContext: TUIContext()
        ).isolatingRenderCache()

        let buffer = renderToBuffer(view, context: context)
        let content = buffer.lines.joined()

        // Check that red's foreground code is present, in this build's colour depth
        let red = "\u{1B}[" + Color.red.foregroundCodes().joined(separator: ";") + "m"
        #expect(content.contains(red), "\(content.debugDescription)")
    }

    @Test("foregroundStyle propagates through multiple levels")
    func stylePropagatesThroughLevels() {
        let view = VStack {
            HStack {
                Text("Nested")
            }
        }
        .foregroundStyle(.green)

        let context = RenderContext(
            availableWidth: 80,
            availableHeight: 24,
            environment: EnvironmentValues(),
            tuiContext: TUIContext()
        ).isolatingRenderCache()

        let buffer = renderToBuffer(view, context: context)
        let content = buffer.lines.joined()

        let green = "\u{1B}[" + Color.green.foregroundCodes().joined(separator: ";") + "m"
        #expect(content.contains(green), "\(content.debugDescription)")
    }

    @Test("explicit Text foregroundStyle overrides parent")
    func explicitStyleOverridesParent() {
        let view = VStack {
            Text("Override").foregroundStyle(.blue)
        }
        .foregroundStyle(.red)

        let context = RenderContext(
            availableWidth: 80,
            availableHeight: 24,
            environment: EnvironmentValues(),
            tuiContext: TUIContext()
        ).isolatingRenderCache()

        let buffer = renderToBuffer(view, context: context)
        let content = buffer.lines.joined()

        // Should have blue, not red
        let blue = "\u{1B}[" + Color.blue.foregroundCodes().joined(separator: ";") + "m"
        let red = "\u{1B}[" + Color.red.foregroundCodes().joined(separator: ";") + "m"
        #expect(content.contains(blue), "\(content.debugDescription)")
        #expect(!content.contains(red), "\(content.debugDescription)")
    }

    @Test("without foregroundStyle, Text uses default")
    func withoutStyleUsesDefault() {
        let view = Text("Plain")

        let context = RenderContext(
            availableWidth: 80,
            availableHeight: 24,
            environment: EnvironmentValues(),
            tuiContext: TUIContext()
        ).isolatingRenderCache()

        let buffer = renderToBuffer(view, context: context)
        let content = buffer.lines.joined()

        // Should just be "Plain" without color codes (or with reset)
        #expect(content.contains("Plain"))
    }
}

// MARK: - transformEnvironment

/// A view whose content AND width both come from `\.testInt`, so a transform
/// that reached only one of the two walks shows up as a disagreement rather
/// than as nothing at all.
private struct IntProbe: View {
    @Environment(\.testInt) private var value

    var body: some View {
        Text(String(repeating: "x", count: max(0, value)))
    }
}

@MainActor
@Suite("transformEnvironment")
struct TransformEnvironmentTests {

    private func context() -> RenderContext {
        RenderContext(
            availableWidth: 80, availableHeight: 24,
            environment: EnvironmentValues(), tuiContext: TUIContext()
        ).isolatingRenderCache()
    }

    /// What the probe drew, as a count — its whole output is that many `x`.
    private func drawn(_ view: some View) -> Int {
        renderToBuffer(view, context: context()).lines.joined().stripped
            .filter { $0 == "x" }.count
    }

    @Test("The closure is handed the INHERITED value")
    func transformsWhatItInherits() {
        // The entire reason this modifier exists: five is not written anywhere
        // near the doubling, and could not be — an ancestor set it.
        #expect(
            drawn(
                IntProbe()
                    .transformEnvironment(\.testInt) { $0 *= 2 }
                    .environment(\.testInt, 5)) == 10)
    }

    @Test("With no ancestor, it transforms the key's default")
    func transformsTheDefault() {
        #expect(drawn(IntProbe().transformEnvironment(\.testInt) { $0 += 3 }) == 3)
    }

    @Test("Nested transforms compose, innermost last")
    func transformsCompose() {
        // (2 + 1) * 10 — and NOT 2 * 10 + 1, which is what an implementation
        // reading the outermost value rather than the inherited one would give.
        #expect(
            drawn(
                IntProbe()
                    .transformEnvironment(\.testInt) { $0 *= 10 }
                    .transformEnvironment(\.testInt) { $0 += 1 }
                    .environment(\.testInt, 2)) == 20 + 10)
    }

    @Test("The measured width is the width that gets drawn")
    func measuresWhatItRenders() {
        // The trap this guards is specific: `Layoutable` is a SEPARATE walk,
        // and one that forgot to transform would measure the inherited value
        // and then draw the transformed one — a control laid out at one width
        // and painted at another. Nothing about the rendered output alone
        // would show it.
        let view = IntProbe()
            .transformEnvironment(\.testInt) { $0 += 6 }
            .environment(\.testInt, 1)
        let measured = measureChild(view, proposal: .unspecified, context: context())
        #expect(drawn(view) == 7)
        #expect(measured.width == 7, "measured \(measured.width), drew 7")
    }

    @Test("A transform touching one field leaves the rest of the value alone")
    func transformsInPlace() {
        // The shape the documentation teaches, and the one `.environment` cannot
        // express: change a field, inherit everything else. If the modifier
        // constructed a fresh value instead of mutating the inherited one, the
        // identifier would come back Gregorian.
        var seen: Calendar?
        struct CalendarProbe: View {
            let report: (Calendar) -> Void
            @Environment(\.calendar) private var calendar
            var body: some View {
                report(calendar)
                return Text("")
            }
        }
        _ = renderToBuffer(
            CalendarProbe { seen = $0 }
                .transformEnvironment(\.calendar) { $0.firstWeekday = 3 }
                .environment(\.calendar, Calendar(identifier: .buddhist)),
            context: context())
        #expect(seen?.firstWeekday == 3, "the field the closure set")
        #expect(seen?.identifier == .buddhist, "and everything it did not")
    }
}
