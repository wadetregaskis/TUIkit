//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalGraphicsQueryTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// The handshake. This is the one terminal capability in the project that is
/// asked rather than looked up, so what it asks and how it reads the answer
/// are the whole of the detection.
@MainActor
@Suite("Kitty graphics handshake")
struct TerminalGraphicsQueryTests {

    @Test("The transmit is silent and the placement is not")
    func onlyThePlacementSpeaks() {
        let request = TerminalGraphicsQuery.request
        // Three commands go out, and if all three spoke the reply would have
        // to be counted rather than read: every acknowledgement has the same
        // `ESC _ G i=…;` shape.
        #expect(request.contains("a=t,q=2"), "the transmit is quiet")
        #expect(request.contains("a=d,d=I,q=2"), "and so is the delete")
        #expect(request.contains("a=p,U=1,q=0"), "the placement is the question")
        #expect(request.hasSuffix("\u{1B}[6n"), "fenced, so silence is an answer")
    }

    /// The fence test used to look at the LAST byte only: a keystroke landing
    /// behind the reply held the read open for the whole timeout, and a bare
    /// `ESC R` typed before the reply ended it early with pictures off. One
    /// scan now, shared with the mode query.
    @Test("The fence is found wherever it lands, and a bare ESC R is not one")
    func fenceIsScanned() {
        #expect(TerminalGraphicsQuery.sawFence(Array("\u{1B}[1;1R".utf8)))
        #expect(TerminalGraphicsQuery.sawFence(Array("\u{1B}[1;1Rx".utf8)), "a byte behind the reply")
        #expect(TerminalGraphicsQuery.sawFence(Array("\u{1B}_Gi=1;OK\u{1B}\\\u{1B}[24;80R".utf8)))
        #expect(!TerminalGraphicsQuery.sawFence(Array("\u{1B}R".utf8)), "not a CSI")
        #expect(!TerminalGraphicsQuery.sawFence(Array("\u{1B}_Gi=1;OK\u{1B}\\".utf8)), "no fence yet")
        #expect(TerminalGraphicsQuery.sawFence(Array("\u{1B}[1;1Rx".utf8)) == TerminalModeQuery.sawFence(Array("\u{1B}[1;1Rx".utf8)))
    }

    /// Apple Terminal prints an APC payload instead of consuming it, and it is
    /// not necessarily the only terminal that does. The request cleans up
    /// after itself so an unmeasured host with the same parser gap does not
    /// start the app with base64 on screen.
    @Test("The request erases whatever a non-parsing terminal printed")
    func requestTidiesUpAfterItself() {
        let request = TerminalGraphicsQuery.request
        #expect(request.hasPrefix("\u{1B}[s"), "the cursor is saved first")
        #expect(request.contains("\u{1B}[u\u{1B}[J"), "…restored, and the screen wiped from there")
        // Small enough that what a printing host shows fits in a row or two:
        // one pixel, not one image.
        #expect(request.count < 200, "the payload is one pixel, and stays one pixel")
    }

    @Test("Only an acknowledged placement counts as support")
    func onlyOKCounts() {
        func answered(_ reply: String) -> Bool {
            TerminalGraphicsQuery.parse(Array(reply.utf8))
        }
        #expect(answered("\u{1B}_Gi=16777215;OK\u{1B}\\"))
        // Ghostty's answer for an image it does not have — the terminal got as
        // far as the lookup, but this exchange transmits first, so reaching
        // ENOENT means something else went wrong. Not support.
        #expect(!answered("\u{1B}_Gi=16777215;ENOENT: image not found\u{1B}\\"))
        // Warp's, verbatim: the protocol is there and the feature is not.
        #expect(
            !answered(
                "\u{1B}_Gi=16777215;InvalidKittyAction(InvalidControlData"
                    + "(UnicodePlaceholderUnsupported))\u{1B}\\"))
        #expect(!answered(""), "silence is a terminal with no protocol at all")
        #expect(!answered("\u{1B}[24;1R"), "the fence alone is silence")
    }

    /// A reply that merely CONTAINS `OK` is not an acknowledgement — the body
    /// after the semicolon has to be exactly that. Warp's refusal does not
    /// contain the letters, but a future error text could, and a substring
    /// search would read it as success.
    @Test("An error that happens to spell OK is still an error")
    func okMustBeTheWholeBody() {
        #expect(!TerminalGraphicsQuery.parse(Array("\u{1B}_Gi=1;ENOTOKEN\u{1B}\\".utf8)))
        #expect(!TerminalGraphicsQuery.parse(Array("\u{1B}_Gi=1;OK is not what I said\u{1B}\\".utf8)))
    }

    /// A reply can arrive with the DSR fence, a stray keystroke, or both
    /// around it, so the scan has to find the APC rather than assume the
    /// buffer is one.
    @Test("The answer is found among whatever else arrived")
    func answerIsFoundInASharedBuffer() {
        let buffer = "q\u{1B}_Gi=16777215;OK\u{1B}\\\u{1B}[24;1R"
        #expect(TerminalGraphicsQuery.parse(Array(buffer.utf8)))
        #expect(TerminalGraphicsQuery.sawFence(Array(buffer.utf8)))
        #expect(!TerminalGraphicsQuery.sawFence(Array("\u{1B}_Gi=1;OK\u{1B}\\".utf8)))
    }
}
