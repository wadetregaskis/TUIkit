//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollContentWindowEqualityTests.swift
//
//  `ScrollContentWindow` carries a per-render reply mailbox. Synthesised
//  `Hashable` folded that reference into equality, so two windows describing
//  the *same* visible slice compared and hashed differently on every frame —
//  the mailbox is freshly allocated each pass. Anything keyed on the window
//  (or on an environment containing it) therefore saw a change every frame.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Scroll content window equality")
struct ScrollContentWindowEqualityTests {
    private func window(reply: ScrollContentReply?, offset: Int = 3) -> ScrollContentWindow {
        ScrollContentWindow(
            offset: offset, viewportHeight: 20, contentIdentity: nil,
            reply: reply, edgeInset: 1, reportsIDAt: nil, seek: nil)
    }

    @Test("Two windows describing the same slice are equal whatever mailbox is attached")
    func replyIsNotIdentity() {
        let first = window(reply: ScrollContentReply())
        let second = window(reply: ScrollContentReply())
        #expect(first == second, "a fresh reply slot must not make it a different window")
        #expect(first.hashValue == second.hashValue)
    }

    @Test("A nil mailbox and a present one still describe the same slice")
    func nilReplyMatches() {
        #expect(window(reply: nil) == window(reply: ScrollContentReply()))
    }

    @Test("What the window actually describes still separates it")
    func describedSliceStillCounts() {
        let reply = ScrollContentReply()
        #expect(window(reply: reply, offset: 3) != window(reply: reply, offset: 4))

        var taller = window(reply: reply)
        taller.viewportHeight += 1
        #expect(taller != window(reply: reply))

        var inset = window(reply: reply)
        inset.edgeInset += 1
        #expect(inset != window(reply: reply))
    }

    @Test("The mailbox itself still compares by identity")
    func replyKeepsReferenceSemantics() {
        let reply = ScrollContentReply()
        let sameObject = reply
        #expect(reply == sameObject)
        #expect(reply != ScrollContentReply())
    }
}
