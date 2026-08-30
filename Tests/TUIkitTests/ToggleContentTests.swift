//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToggleContentTests.swift
//
//  A toggle that governs settings draws them under itself. The reason it is an
//  API rather than two lines at the call site is the indent: it is the
//  INDICATOR's width, and the indicator is a `ToggleCharacterSet` resolved
//  against the terminal, so a hardcoded number is wrong on two of the three.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Toggle content")
struct ToggleContentTests {

    /// A toggle with a button under it, at `characterSet`.
    private func rendered(
        isOn: Bool, characterSet: ToggleCharacterSet = .unicode, context: RenderContext
    ) -> FrameBuffer {
        let view = Toggle("Edge lines", isOn: .constant(isOn))
            .toggleContent { Button("threshold") {} }
            .toggleCharacterSet(characterSet)
        _ = renderToBuffer(view, context: context)
        return renderToBuffer(view, context: context)
    }

    @Test("Content sits under the toggle, indented to its LABEL not its box")
    func contentIndentsToTheLabel() {
        var indents: [Int] = []
        for (characterSet, name) in [
            (ToggleCharacterSet.unicode, "unicode"), (.emoji, "emoji"), (.ascii, "ascii"),
        ] {
            let context = makeRenderContext(width: 40, height: 10)
            let lines = rendered(isOn: true, characterSet: characterSet, context: context)
                .lines.map(\.stripped)
            #expect(lines.count == 2, "\(name): \(lines)")
            // The label starts after the indicator and one space; so does the
            // content. `■` is one cell, `⬛︎` two, `[x]` three — which is the
            // whole reason this is not a constant.
            // In CELLS, not characters: the indicator is one Character in every
            // set and one, two or three cells depending which set it is, so
            // counting Characters here would measure the wrong thing and agree
            // with the wrong answer.
            guard let range = lines[0].firstRange(of: "Edge lines") else {
                Issue.record("\(name): no label: \(lines)")
                continue
            }
            let labelColumn = String(lines[0][lines[0].startIndex..<range.lowerBound])
                .strippedLength
            let contentColumn = lines[1].prefix { $0 == " " }.count
            #expect(
                contentColumn == labelColumn,
                "\(name): content at \(contentColumn), label at \(labelColumn)")
            indents.append(contentColumn)
        }
        // And the three are not all the same, or the test above would pass on a
        // hardcoded constant — which is exactly the bug this API exists to stop.
        #expect(Set(indents).count > 1, "every character set indented alike: \(indents)")
    }

    @Test("Content is live only while the toggle is on")
    func contentFollowsTheToggle() {
        for isOn in [true, false] {
            let context = makeRenderContext(width: 40, height: 10)
            _ = rendered(isOn: isOn, context: context)
            let focusable = context.environment.focusManager!.focusableIDsInActiveSection()
            // The toggle always; its button only when the toggle is on.
            #expect(
                focusable.count == (isOn ? 2 : 1),
                "isOn=\(isOn) gave \(focusable)")
        }
    }

    @Test("The rows the toggle occupies do not move when it is flipped")
    func layoutIsStableAcrossStates() {
        func shape(_ isOn: Bool) -> [Int] {
            rendered(isOn: isOn, context: makeRenderContext(width: 40, height: 10))
                .lines.map { $0.stripped.count }
        }
        #expect(shape(true) == shape(false))
    }

    @Test("Clicking the content does not flip the toggle")
    func clickingContentDoesNotFlip() {
        let context = makeRenderContext(width: 40, height: 10)
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(MouseSupport.full)

        var isOn = true
        let view = Toggle("Edge lines", isOn: Binding(get: { isOn }, set: { isOn = $0 }))
            .toggleContent { Button("threshold") {} }
            .toggleCharacterSet(.unicode)
        _ = renderToBuffer(view, context: context)
        dispatcher.setRegions(renderToBuffer(view, context: context).hitTestRegions)

        // Row 1 is the control's, not the toggle's. A region that spanned the
        // whole thing would answer here and flip the switch out from under the
        // control being clicked.
        for phase in [MousePhase.pressed, .released] {
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: phase, x: 3, y: 1))
        }
        #expect(isOn, "clicking the content flipped the toggle")

        // The toggle's own row still flips it, so it did not simply stop
        // answering the pointer.
        for phase in [MousePhase.pressed, .released] {
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: phase, x: 3, y: 0))
        }
        #expect(!isOn, "the toggle row stopped answering")
    }

    @Test("A toggle carrying nothing is unchanged")
    func plainToggleIsUnaffected() {
        let context = makeRenderContext(width: 40, height: 10)
        let plain = Toggle("Edge lines", isOn: .constant(true)).toggleCharacterSet(.unicode)
        _ = renderToBuffer(plain, context: context)
        let lines = renderToBuffer(plain, context: context).lines.map(\.stripped)
        #expect(lines.count == 1)
        #expect(lines[0].hasSuffix("Edge lines"))
    }
}
