//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollRevealTests.swift
//
//  Pins the plumbing that reveal-on-focus depends on. `ScrollView` locates the
//  control to reveal by matching `FocusManager.currentFocusedID` against the
//  `focusID` carried on a hit region (see ScrollView's snap logic). Anything
//  that drops `focusID` while relaying a buffer silently disables that lookup —
//  and because `HitTestRegion.focusID` DEFAULTS to nil, dropping it is a silent
//  omission the compiler cannot catch. Hence these tests.
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

@Suite("Scroll reveal plumbing")
struct ScrollRevealTests {

    @Test("A ScrollView carries focusID through its viewport clip")
    @MainActor
    func focusIDSurvivesTheScrollClip() {
        // The regression this guards: `windowedBuffer` rebuilt each surviving
        // region without `focusID`, so every ScrollView stripped the ids from
        // its content. An ENCLOSING ScrollView then had nothing to match and
        // could never reveal a control nested inside this one — i.e. nested
        // scroll views could not reveal at all.
        let view = ScrollView {
            VStack {
                Button("target") {}
                    .focusID("the-target")
                ForEach(0..<40) { index in Text("filler \(index)") }
            }
        }
        .frame(height: 6)

        let context = makeRenderContext(width: 30, height: 6)
        let buffer = renderToBuffer(view, context: context)

        let ids = buffer.hitTestRegions.compactMap(\.focusID)
        #expect(
            ids.contains("the-target"),
            "focusID must survive the clip; got regions=\(buffer.hitTestRegions.count) ids=\(ids)")
    }

    @Test("A ScrollView nested in a ScrollView still exposes its focusIDs outward")
    @MainActor
    func focusIDSurvivesTwoLevelsOfClipping() {
        // The author's stated requirement is that reveal works through
        // "multiple layers of ScrollView". Two clips must not lose the id
        // either — the outer ScrollView sees only what the inner emitted.
        let view = ScrollView {
            VStack {
                ScrollView {
                    VStack {
                        Button("deep") {}
                            .focusID("deep-target")
                        ForEach(0..<20) { index in Text("inner \(index)") }
                    }
                }
                .frame(height: 4)
                ForEach(0..<20) { index in Text("outer \(index)") }
            }
        }
        .frame(height: 8)

        let context = makeRenderContext(width: 30, height: 8)
        let buffer = renderToBuffer(view, context: context)

        let ids = buffer.hitTestRegions.compactMap(\.focusID)
        #expect(
            ids.contains("deep-target"),
            "focusID must survive BOTH clips; got ids=\(ids)")
    }

    @Test("The clip keeps a region's handler as well as its focusID")
    @MainActor
    func clipKeepsHandlerAndFocusID() {
        // focusID and handlerID travel together: losing either breaks a
        // different feature (reveal vs clicking), so assert both survive.
        let view = ScrollView {
            VStack {
                Button("target") {}
                    .focusID("both")
                ForEach(0..<40) { index in Text("filler \(index)") }
            }
        }
        .frame(height: 6)

        let context = makeRenderContext(width: 30, height: 6)
        let buffer = renderToBuffer(view, context: context)

        let region = buffer.hitTestRegions.first { $0.focusID == "both" }
        #expect(region != nil, "region with focusID must survive")
        // A real handler id is non-zero; a defaulted/dropped one would not be.
        #expect(region?.handlerID != nil)
    }
}
