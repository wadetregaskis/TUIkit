//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ConditionalFlatteningTests.swift
//
//  `if` / `if-else` content flattens into the enclosing stack (SwiftUI
//  semantics): a ForEach under a conditional contributes its rows, a `nil`
//  branch contributes nothing (no phantom spacing slot), and children
//  flattened from different providers keep DISTINCT identities (no state or
//  focus collisions between same-typed views under sibling conditionals).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

@MainActor
@Suite("Conditional child flattening")
struct ConditionalFlatteningTests {

    @Test("A ForEach under if/else renders its rows in a stack")
    func forEachUnderIfElse() {
        @MainActor
        @ViewBuilder func tree(_ hasRows: Bool) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("HEAD")
                if hasRows {
                    ForEach(["one", "two", "three"], id: \.self) { Text($0) }
                } else {
                    Text("none")
                }
            }
        }
        let with = renderToBuffer(tree(true), context: makeRenderContext(width: 20, height: 10))
        let lines = with.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
        #expect(lines == ["HEAD", "one", "two", "three"], "\(lines)")

        let without = renderToBuffer(tree(false), context: makeRenderContext(width: 20, height: 10))
        #expect(without.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) } == ["HEAD", "none"])
    }

    @Test("A ForEach under a lone `if` renders; nil contributes nothing")
    func forEachUnderOptional() {
        @MainActor
        @ViewBuilder func tree(_ hasRows: Bool) -> some View {
            VStack(alignment: .leading, spacing: 1) {
                Text("HEAD")
                if hasRows {
                    ForEach(["one", "two"], id: \.self) { Text($0) }
                }
                Text("TAIL")
            }
        }
        let with = renderToBuffer(tree(true), context: makeRenderContext(width: 20, height: 10))
        #expect(
            with.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
                == ["HEAD", "", "one", "", "two", "", "TAIL"])

        // The absent branch leaves no phantom slot — HEAD and TAIL sit one
        // spacing apart, not two.
        let without = renderToBuffer(tree(false), context: makeRenderContext(width: 20, height: 10))
        #expect(
            without.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
                == ["HEAD", "", "TAIL"])
    }

    @Test("Same-typed children under sibling conditionals keep distinct identities")
    func siblingConditionalsDontCollide() {
        // Two TextFields under two separate `if`s: their auto-generated
        // focus ids derive from their identity paths, so a collision would
        // register one focusable instead of two (the second silently adopts
        // the first's state slots — the ColorPickerPanel hex-field bug).
        var first = ""
        var second = ""
        let tree = HStack(spacing: 1) {
            if true {
                TextField("a", text: Binding(get: { first }, set: { first = $0 }))
                    .frame(width: 8)
            }
            if true {
                TextField("b", text: Binding(get: { second }, set: { second = $0 }))
                    .frame(width: 8)
            }
        }
        let focus = FocusManager()
        let context = makeRenderContext(width: 30, height: 4) { env, _ in
            env.focusManager = focus
        }
        func render() {
            focus.beginRenderPass()
            _ = renderToBuffer(tree, context: context)
            focus.endRenderPass()
        }
        render()
        var seen: Set<String> = []
        for _ in 0..<2 {
            if let id = focus.currentFocusedID { seen.insert(id) }
            _ = focus.dispatchKeyEvent(KeyEvent(key: .tab))
            render()
        }
        #expect(seen.count == 2, "two distinct focusables in the ring: \(seen)")
    }
}
