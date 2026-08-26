//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SecureFieldClipboardTests.swift
//
//  SwiftUI's SecureField documents that it "prevents anyone from cutting or
//  copying the field's contents", and NSSecureTextField does the same. TUIkit
//  reuses TextFieldHandler for both fields because the key handling really is
//  identical everywhere else — so masking, which happens at render time, was
//  the only thing standing between Ctrl-C and the user's password reaching
//  the system pasteboard in clear text. It stood nowhere near it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@Suite("secure field clipboard refusal")
struct SecureFieldClipboardTests {
    /// Records what a field hands the clipboard, and answers reads from the
    /// same store. Per handler, so these run in parallel with everything else
    /// without a shared pasteboard to race over.
    private final class FakeClipboard: @unchecked Sendable {
        var contents: String?
        var writes: [String] = []

        var access: ClipboardAccess {
            ClipboardAccess(
                write: { [self] in
                    writes.append($0)
                    contents = $0
                },
                read: { [self] in contents }
            )
        }
    }

    private final class TextBox: @unchecked Sendable {
        var text: String
        init(_ text: String) { self.text = text }
    }

    private func makeHandler(
        _ initial: String, secure: Bool, clipboard: FakeClipboard
    ) -> (TextFieldHandler, TextBox) {
        let box = TextBox(initial)
        let binding = Binding(get: { box.text }, set: { box.text = $0 })
        let handler = TextFieldHandler(
            focusID: "field", text: binding, cursorPosition: initial.count)
        handler.isSecure = secure
        handler.clipboard = clipboard.access
        handler.selectionAnchor = 0  // select the whole string
        return (handler, box)
    }

    @Test("Ctrl-C in a secure field puts nothing on the clipboard")
    func secureCopyIsRefused() {
        let board = FakeClipboard()
        let (handler, box) = makeHandler("hunter2", secure: true, clipboard: board)

        #expect(handler.handleKeyEvent(KeyEvent(key: .character("c"), ctrl: true)) == true)
        #expect(board.writes.isEmpty, "nothing was written: \(board.writes)")
        #expect(box.text == "hunter2", "and the field is untouched")

        // The control case, so the assertion above is about `isSecure` rather
        // than about the key going unhandled or the selection being empty.
        let plainBoard = FakeClipboard()
        let (plain, _) = makeHandler("hunter2", secure: false, clipboard: plainBoard)
        #expect(plain.handleKeyEvent(KeyEvent(key: .character("c"), ctrl: true)) == true)
        #expect(plainBoard.writes == ["hunter2"], "a plain field still copies")
    }

    @Test("Ctrl-X in a secure field neither copies nor deletes")
    func secureCutIsRefused() {
        let board = FakeClipboard()
        let (handler, box) = makeHandler("hunter2", secure: true, clipboard: board)

        #expect(handler.handleKeyEvent(KeyEvent(key: .character("x"), ctrl: true)) == true)
        #expect(board.writes.isEmpty, "nothing was written: \(board.writes)")
        #expect(box.text == "hunter2", "the cut is refused outright, not degraded to a delete")
        #expect(handler.hasSelection, "and the selection survives, as nothing happened")

        let plainBoard = FakeClipboard()
        let (plain, plainBox) = makeHandler("hunter2", secure: false, clipboard: plainBoard)
        #expect(plain.handleKeyEvent(KeyEvent(key: .character("x"), ctrl: true)) == true)
        #expect(plainBox.text.isEmpty, "a plain field cuts the selection")
        #expect(plainBoard.writes == ["hunter2"])
    }

    /// The unit tests above set `isSecure` themselves, so they say nothing
    /// about whether `_SecureFieldCore` sets it. This one renders the real
    /// views and drives real keys, so deleting `handler.isSecure = true` from
    /// the field's sync block fails here — which is the line that stands
    /// between a password and `pbcopy`.
    @MainActor
    @Test("A rendered SecureField refuses the cut; a rendered TextField performs it")
    func wiringFromTheViewDown() {
        func cutAll(secure: Bool) -> String {
            let box = StateBox("hunter2")
            let binding = Binding(get: { box.value }, set: { box.value = $0 })
            let focusManager = FocusManager()
            let context = makeRenderContext { environment, _ in
                environment.focusManager = focusManager
            }
            let view = AnyView(
                secure
                    ? AnyView(SecureField("secret", text: binding))
                    : AnyView(TextField("secret", text: binding)))

            focusManager.beginRenderPass()
            _ = renderToBuffer(view, context: context)
            focusManager.endRenderPass()

            // Select the whole value with Shift+Left, then cut it.
            for _ in 0..<"hunter2".count {
                _ = focusManager.dispatchKeyEvent(KeyEvent(key: .left, shift: true))
            }
            _ = focusManager.dispatchKeyEvent(KeyEvent(key: .character("x"), ctrl: true))
            return box.value
        }

        #expect(cutAll(secure: true) == "hunter2", "a SecureField refuses the cut")
        #expect(cutAll(secure: false).isEmpty, "a TextField performs it, so the keys did arrive")
    }

    @Test("Pasting INTO a secure field still works")
    func securePasteIsAllowed() {
        // The promise is one-directional: SwiftUI's list bars cutting and
        // copying and says nothing about paste, which is how a password
        // manager fills the field.
        let board = FakeClipboard()
        board.contents = "from-clipboard"
        let (handler, box) = makeHandler("", secure: true, clipboard: board)
        handler.clearSelection()

        #expect(handler.handleKeyEvent(KeyEvent(key: .character("v"), ctrl: true)) == true)
        #expect(box.text == "from-clipboard", "paste is not part of the refusal")
    }
}
