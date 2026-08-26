//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StyleCascadeResetTests.swift
//
//  SwiftUI's `.fontWeight(nil)` "removes the effect of any font weight modifier
//  applied higher in the view hierarchy", and `.textCase(nil)` writes nil into
//  an environment value of type `Text.Case?`, which overrides an ancestor the
//  same way. Both were silent no-ops here: nil produced empty attributes, and
//  the cascade drops an empty entry, so an inherited transform could not be
//  escaped from anywhere in the subtree.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("style cascade reset")
struct StyleCascadeResetTests {
    private func render<V: View>(_ view: V) -> String {
        let context = makeRenderContext(width: 30, height: 4)
        return renderToBuffer(view, context: context).lines[0]
    }

    private func plain<V: View>(_ view: V) -> String {
        render(view).stripped.trimmingCharacters(in: .whitespaces)
    }

    /// SGR 1 is bold. Reading the escape is the only way to see a weight.
    private func isBold<V: View>(_ view: V) -> Bool {
        render(view).contains("\u{1B}[1;") || render(view).contains("\u{1B}[1m")
    }

    @Test("textCase(nil) escapes an inherited transform")
    func textCaseNilResets() {
        #expect(plain(VStack { Text(verbatim: "Hello") }.textCase(.uppercase)) == "HELLO")
        #expect(
            plain(VStack { Text(verbatim: "Hello").textCase(nil) }.textCase(.uppercase)) == "Hello",
            "nil clears the ancestor's transform")
        // And still says nothing when nothing was inherited, rather than
        // becoming a transform of its own.
        #expect(plain(VStack { Text(verbatim: "Hello").textCase(nil) }) == "Hello")
        // A nearer statement still wins over a nil further in? No — nil IS the
        // nearer statement here, and proximity is the rule.
        #expect(
            plain(VStack { Text(verbatim: "Hello").textCase(nil) }.textCase(.lowercase)) == "Hello")
    }

    @Test("View.fontWeight(nil) escapes an inherited weight")
    func fontWeightNilResets() {
        // The receiver must not be a `Text`: `Text.fontWeight(_:)` is a
        // separate overload, and SwiftUI documents no reset for that one, so
        // TUIkit's leaving an inherited weight alone there is correct. This is
        // about the View spelling, whose doc DOES promise the reset.
        #expect(isBold(VStack { Text("Hi") }.fontWeight(.bold)), "the ancestor's weight applies")
        #expect(
            !isBold(VStack { VStack { Text("Hi") }.fontWeight(nil) }.fontWeight(.bold)),
            "nil removes it, as SwiftUI documents")
        #expect(
            !isBold(VStack { VStack { Text("Hi") }.fontWeight(.regular) }.fontWeight(.bold)),
            "and .regular, which nil resolves to, does the same")
        #expect(
            isBold(VStack { VStack { Text("Hi") }.fontWeight(.bold) }),
            "a stated weight still reaches the text")
    }

    @Test("A stated case still reaches the text")
    func statedCaseStillApplies() {
        // The control: a fix that made every textCase entry look empty would
        // pass the reset tests and break this one.
        #expect(plain(VStack { Text(verbatim: "Hello") }.textCase(.lowercase)) == "hello")
        #expect(plain(Text(verbatim: "Hello").textCase(.uppercase)) == "HELLO")
    }
}
