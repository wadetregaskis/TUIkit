//  🖥️ TUIkit — Terminal UI Kit for Swift
//  UserResizableMeasureTests.swift
//
//  `.userResizable` offers its content a bounded amount of space. It used to
//  make that offer only while RENDERING, so a flexible child measured as tall
//  as whatever canvas it was measured against and drew its ceiling — and an
//  enclosing stack placed every later sibling off the end of the canvas.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("A resizable view measures what it draws")
struct UserResizableMeasureTests {
    private func context(width: Int, height: Int) -> RenderContext {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        return RenderContext(
            availableWidth: width, availableHeight: height, environment: environment,
            tuiContext: tui)
    }

    /// A `ScrollView` is height-flexible, so it takes whatever it is offered —
    /// which is exactly the case the missing offer got wrong.
    @ViewBuilder
    private var resizableScroll: some View {
        ScrollView {
            VStack(alignment: .leading) {
                ForEach(0..<18, id: \.self) { index in Text("Line \(index)") }
            }
        }
        .border(.palette.border)
        .userResizable(height: 6...24)
    }

    /// The canvases a `ScrollView` measures its content against run to
    /// thousands of rows, and the measure has to answer the same at every one.
    @Test("the ceiling holds however tall the canvas is", arguments: [30, 60, 200, 4096])
    func measuredEqualsDrawn(canvas: Int) {
        let ctx = context(width: 80, height: canvas)
        let measured = measureChild(resizableScroll, proposal: .unspecified, context: ctx)
        let drawn = renderToBuffer(resizableScroll, context: context(width: 80, height: canvas))
        #expect(
            measured.height == drawn.height,
            "at canvas \(canvas): measured \(measured.height), drew \(drawn.height)")
        #expect(measured.width == drawn.width, "at canvas \(canvas)")
        #expect(drawn.height <= 24, "the ceiling: drew \(drawn.height)")
    }

    /// The bug as the reader met it: everything after the resizable view was
    /// gone. It is a placement failure, not a clipping one — the stack put the
    /// siblings past the end of the canvas because it was told the resizable
    /// view needed all of it.
    @Test("a sibling after a resizable view is still drawn", arguments: [40, 120, 4096])
    func siblingsAfterAreDrawn(canvas: Int) {
        let page = VStack(alignment: .leading, spacing: 1) {
            Text("BEFORE")
            resizableScroll
            Text("AFTER-ONE")
            Text("AFTER-TWO")
        }
        let buffer = renderToBuffer(page, context: context(width: 80, height: canvas))
        let text = buffer.lines.joined(separator: "\n").stripped
        #expect(text.contains("BEFORE"), "at canvas \(canvas)")
        #expect(text.contains("AFTER-ONE"), "at canvas \(canvas): drew \(buffer.height) rows")
        #expect(text.contains("AFTER-TWO"), "at canvas \(canvas): drew \(buffer.height) rows")
    }

    /// A view with no ceiling still takes what it is offered — the fix must not
    /// turn "resizable" into "shrink-wrapped".
    @Test("an unbounded axis is unchanged")
    func unboundedIsUnchanged() {
        let bare = ScrollView {
            VStack(alignment: .leading) {
                ForEach(0..<18, id: \.self) { index in Text("Line \(index)") }
            }
        }
        let plain = renderToBuffer(bare, context: context(width: 80, height: 30))
        let resizable = renderToBuffer(
            bare.userResizable(.vertical), context: context(width: 80, height: 30))
        #expect(resizable.height == plain.height)
    }
}
