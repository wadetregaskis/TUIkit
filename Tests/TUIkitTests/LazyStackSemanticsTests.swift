//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LazyStackSemanticsTests.swift
//
//  Pins the documented lazy-stack semantics and their deviations from
//  SwiftUI (see §2.8 of Documentation/SwiftUI-compatibility.md, grounded in
//  the LazyVStack docs and WWDC26's "Dive into lazy stacks and scrolling").
//  If viewport-driven laziness inside ScrollView is ever implemented, the
//  ScrollView cases here change intentionally.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Lazy stack semantics vs SwiftUI")
struct LazyStackSemanticsTests {
    @Test("Overflow policy: VStack clips mid-child, LazyVStack stops at a child boundary")
    func overflowPolicies() {
        let tall = { (label: String) in
            VStack(spacing: 0) { Text("\(label)1"); Text("\(label)2"); Text("\(label)3") }
        }
        let context = makeBareRenderContext(width: 20, height: 5)

        // Eager: distributes 5 lines across two 3-line children — the second
        // is cut mid-child at the cell.
        let eager = renderToBuffer(VStack(spacing: 0) { tall("a"); tall("b") }, context: context)
        #expect(eager.height == 5, "eager clips at the cell: \(eager.lines.map(\.stripped))")
        #expect(eager.lines.last?.stripped.contains("b2") == true, "second child partially visible")

        // Lazy: the second whole child would overflow, so the window ends at
        // the first child's boundary.
        let lazy = renderToBuffer(LazyVStack(spacing: 0) { tall("a"); tall("b") }, context: context)
        #expect(lazy.height == 3, "lazy stops at the child boundary: \(lazy.lines.map(\.stripped))")
    }

    @Test("In a scroll-content context the full extent materialises (exact, not estimated)")
    func fullExtentInScrollContext() {
        // ScrollView measures its content with a generous height budget; the
        // window then admits everything, so scrolling can reach every item.
        let size = measureChild(
            LazyVStack { ForEach(0..<100) { Text("Item \($0)") } },
            proposal: .unspecified,
            context: makeRenderContext(width: 30, height: 4096))
        #expect(size.height == 100, "the extent is the real content height")
    }

    @Test("The measure budget caps both stack kinds alike")
    func budgetCapsBothKinds() {
        let budget = makeRenderContext(width: 30, height: 4096)
        let lazy = measureChild(
            LazyVStack { ForEach(0..<6000) { Text("Item \($0)") } },
            proposal: .unspecified, context: budget)
        let eager = measureChild(
            VStack { ForEach(0..<6000) { Text("Item \($0)") } },
            proposal: .unspecified, context: budget)
        #expect(lazy.height == 4096 && eager.height == 4096,
                "content past the budget is unreachable for BOTH; List is the big-data container")
    }

    @Test("Cross-axis width hugs the widest placed child (documented SwiftUI deviation)")
    func crossAxisHugsWidest() {
        // SwiftUI's LazyVStack ideal width is its FIRST subview's (it hasn't
        // created the rest); TUIkit has rendered every visible child, so it
        // hugs the real widest — child order must not matter.
        func width<V: View>(_ view: V) -> Int {
            measureChild(
                view, proposal: .unspecified,
                context: makeRenderContext(width: 60, height: 20)
            ).width
        }
        let wide = "a much longer line"
        #expect(width(LazyVStack { Text("hi"); Text(wide) }) == wide.count)
        #expect(width(LazyVStack { Text(wide); Text("hi") }) == wide.count)
        #expect(width(VStack { Text("hi"); Text(wide) }) == wide.count, "identical to the eager stack")
    }

    @Test("Standalone laziness: lifecycle never fires past the fold; in ScrollView it fires for all")
    func lifecycleSemantics() {
        nonisolated(unsafe) var standaloneAppeared: [Int] = []
        nonisolated(unsafe) var scrollAppeared: [Int] = []

        func render(_ view: some View, height: Int) {
            let tuiContext = TUIContext()
            var environment = EnvironmentValues()
            environment.focusManager = FocusManager()
            environment.applyRuntimeServices(from: tuiContext)
            let context = RenderContext(
                availableWidth: 30, availableHeight: height,
                environment: environment, tuiContext: tuiContext)
            tuiContext.lifecycle.beginRenderPass()
            _ = renderToBuffer(view, context: context)
            tuiContext.lifecycle.endRenderPass()
        }

        // Standalone: children past the fold are never rendered, so their
        // onAppear correctly never fires — matching SwiftUI's laziness.
        render(
            LazyVStack {
                ForEach(0..<50) { index in
                    Text("Row \(index)").onAppear { standaloneAppeared.append(index) }
                }
            },
            height: 8)
        #expect(standaloneAppeared.count == 8, "exactly the windowed rows appear: \(standaloneAppeared)")

        // In a ScrollView the whole extent materialises, so every row's
        // onAppear fires at once. SwiftUI fires on visibility instead — this
        // pins the DOCUMENTED deviation (§2.8); it changes intentionally if
        // viewport-driven laziness lands.
        render(
            ScrollView {
                LazyVStack {
                    ForEach(0..<50) { index in
                        Text("Row \(index)").onAppear { scrollAppeared.append(index) }
                    }
                }
            },
            height: 8)
        #expect(scrollAppeared.count == 50, "all rows materialise in scroll content today")
    }
}
