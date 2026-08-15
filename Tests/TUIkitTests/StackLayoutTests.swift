//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StackLayoutTests.swift
//
//  `AnyLayout` shipped with nothing to erase: no concrete `Layout` value
//  existed, so the one line every SwiftUI adaptive-layout example is built from
//  did not compile. These pin that it now does, and that a switch between the
//  two arrangements really does rearrange.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Stack layouts as values")
struct StackLayoutTests {

    private func lines(_ view: some View, width: Int = 30, height: Int = 10) -> [String] {
        renderToBuffer(view, context: makeBareRenderContext(width: width, height: height))
            .lines
            .map {
                $0.stripped.replacingOccurrences(
                    of: " +$", with: "", options: .regularExpression)
            }
    }

    /// The canonical adaptive line. That it compiles at all is half the point.
    @Test("AnyLayout switches between the stacks")
    func anyLayoutSwitches() {
        for isWide in [true, false] {
            let layout = isWide ? AnyLayout(HStackLayout()) : AnyLayout(VStackLayout())
            let drawn = lines(
                layout {
                    Text(verbatim: "aa")
                    Text(verbatim: "bb")
                })
            let painted = drawn.filter { !$0.isEmpty }
            if isWide {
                #expect(painted.count == 1, "one row when horizontal: \(drawn)")
                #expect(painted.first?.contains("aa") == true)
                #expect(painted.first?.contains("bb") == true)
            } else {
                #expect(painted.count == 2, "two rows when vertical: \(drawn)")
            }
        }
    }

    @Test("VStackLayout stacks downward and honours spacing")
    func verticalSpacing() {
        let tight = lines(VStackLayout { Text(verbatim: "a"); Text(verbatim: "b") })
        #expect(tight[0].contains("a") && tight[1].contains("b"), "\(tight)")

        let loose = lines(VStackLayout(spacing: 2) { Text(verbatim: "a"); Text(verbatim: "b") })
        #expect(loose[0].contains("a"), "\(loose)")
        #expect(loose[1].isEmpty && loose[2].isEmpty, "two blank rows: \(loose)")
        #expect(loose[3].contains("b"), "\(loose)")
    }

    @Test("HStackLayout puts one cell between subviews by default")
    func horizontalSpacing() {
        let drawn = lines(HStackLayout { Text(verbatim: "ab"); Text(verbatim: "cd") })
        #expect(drawn[0].hasPrefix("ab cd"), "\(drawn)")

        let tight = lines(HStackLayout(spacing: 0) { Text(verbatim: "ab"); Text(verbatim: "cd") })
        #expect(tight[0].hasPrefix("abcd"), "\(tight)")
    }

    @Test("VStackLayout aligns across its width")
    func verticalAlignment() {
        let trailing = lines(
            VStackLayout(alignment: .trailing) {
                Text(verbatim: "long text")
                Text(verbatim: "x")
            }.frame(width: 12))
        // The short row is pushed right, under the end of the long one.
        let short = trailing.first { $0.contains("x") && !$0.contains("long") }
        #expect(short?.hasPrefix(" ") == true, "trailing-aligned: \(trailing)")
    }

    /// A layout is allowed to overlap its subviews, and this one does: the last
    /// written lands on top, which is what makes it a Z stack.
    @Test("ZStackLayout puts every subview at one origin")
    func overlay() {
        let drawn = lines(ZStackLayout { Text(verbatim: "....."); Text(verbatim: "AB") })
        let painted = drawn.filter { !$0.isEmpty }
        #expect(painted.count == 1, "one row, not two: \(drawn)")
        #expect(painted[0].hasPrefix("AB"), "the later view drew over the earlier: \(painted)")
    }

    /// The reason to reach for a layout value rather than a `ViewBuilder`
    /// branch: the subviews keep ONE identity, so they are not torn down and
    /// rebuilt when the arrangement changes. `.onAppear` firing exactly once
    /// across the switch is that, observably — two branches of an `if` would
    /// fire it again.
    @Test("switching layouts does not re-create the subviews")
    func identityIsStable() {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 30, availableHeight: 10, environment: environment, tuiContext: tui)
        let appearances = Appearances()

        func frame(wide: Bool) {
            let layout = wide ? AnyLayout(HStackLayout()) : AnyLayout(VStackLayout())
            tui.stateStorage.beginRenderPass()
            _ = renderToBuffer(
                layout {
                    Text(verbatim: "a").onAppear { appearances.count += 1 }
                },
                context: context)
            tui.stateStorage.endRenderPass()
        }
        frame(wide: false)
        let afterFirst = appearances.count
        frame(wide: true)

        #expect(afterFirst == 1, "it appeared once to begin with")
        #expect(
            appearances.count == afterFirst,
            "the subview survived the switch rather than being rebuilt")
    }

    /// A counter the render pass can write to from inside a closure.
    private final class Appearances: @unchecked Sendable {
        var count = 0
    }
}
