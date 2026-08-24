//  🖥️ TUIKit — Terminal UI Kit for Swift
//  PaddingStarvationTests.swift
//
//  Padding is decoration, and decoration loses to the thing it decorates.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Padding in a space too small for it")
struct PaddingStarvationTests {

    private func render(_ view: some View, width: Int = 40, height: Int = 12) -> FrameBuffer {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        return renderToBuffer(
            view,
            context: RenderContext(
                availableWidth: width, availableHeight: height, environment: environment,
                tuiContext: tui))
    }

    /// The reported case, from the Example's transition demo: a padded,
    /// bordered panel given three rows for its five.
    ///
    /// The height was propagated straight through — border took two, padding
    /// took two more — so the text was offered −1 lines, which clamped to none,
    /// which rendered nothing. A view with no content has no width to report,
    /// so the box came out an empty 6×3 frame: a height constraint deciding a
    /// width.
    @Test("A height too small for the padding does not decide the width")
    func heightDoesNotCollapseWidth() {
        let panel = Text("Here I am.").padding(1).border(.palette.accent)
        let natural = render(panel).width
        // From three rows up: at one or two the box is nothing but border, so
        // there is no content row for a width to be derived from and the
        // collapse is the honest answer rather than this bug.
        for height in 3...6 {
            let squeezed = render(panel.frame(height: height, alignment: .top))
            #expect(
                squeezed.width == natural,
                "\(height) rows gave width \(squeezed.width), natural is \(natural)")
        }
    }

    /// The same rule horizontally, which nothing was asking for and which would
    /// have gone wrong the same way.
    @Test("A width too small for the padding leaves a cell for the content")
    func widthLeavesRoomForContent() {
        for width in 1...4 {
            let squeezed = render(Text("abcdefgh").padding(2).frame(width: width), width: width)
            #expect(squeezed.height >= 1, "\(width) columns rendered nothing")
        }
    }

    /// With room to spare, nothing changes: padding takes exactly what it asked
    /// for, and the content is measured in what is left.
    @Test("Padding still takes its full inset where there is room")
    func normalCaseUnchanged() {
        let padded = render(Text("hi").padding(2))
        #expect(padded.lines.count == 5, "\(padded.lines.map(\.stripped))")
        #expect(padded.width == 6, "two columns each side of two")
    }
}
