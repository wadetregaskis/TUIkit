//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HeadlessAppTests.swift
//
//  `HeadlessApp` — the real render loop and input chain over an in-memory
//  terminal — does what a session relies on: keys reach the focused control,
//  a frame shows what they did, a resize lays the next frame out anew, and an
//  instance that clears its render cache every frame draws what one that keeps
//  it draws.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// A field and an echo of what was typed into it.
private struct TypingApp: App {
    init() {}

    var body: some Scene {
        WindowGroup { TypingPage() }
    }
}

private struct TypingPage: View {
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Name", text: $text)
            Text("echo: \(text)")
        }
    }
}

/// Whether some line of `screen`, with its styling stripped, contains `text`.
private func shows(_ text: String, on screen: [String]) -> Bool {
    screen.contains { $0.stripped.contains(text) }
}

@MainActor
@Suite("An app driven headless, frame by frame")
struct HeadlessAppTests {
    @Test("Keys typed into the focused field are drawn on the next frame")
    func keysReachTheFocusedField() {
        let app = HeadlessApp(TypingApp(), width: 40, height: 10)
        app.frame(atNanos: 0)
        #expect(shows("echo: ", on: app.screen), "precondition: the page is drawn")
        for character in "hello" { app.send(KeyEvent(key: .character(character))) }
        app.frame(atNanos: 16_666_667)
        #expect(shows("echo: hello", on: app.screen))
        #expect(app.bytesWritten > 0)
    }

    @Test("A resize lays the next frame out at the new size")
    func aResizeRelaysOut() {
        let app = HeadlessApp(TypingApp(), width: 40, height: 10)
        app.frame(atNanos: 0)
        let before = app.bytesWritten
        app.resize(width: 60, height: 12)
        app.frame(atNanos: 16_666_667)
        #expect(app.bytesWritten > before, "the resized frame rewrote nothing")
        #expect(app.screen.contains { $0.stripped.count >= 60 }, "no line spans the new width")
    }

    @Test("An instance with no render cache draws what one with a cache draws")
    func theCacheIsTransparent() {
        let warm = HeadlessApp(TypingApp(), width: 40, height: 10)
        let cold = HeadlessApp(TypingApp(), width: 40, height: 10)
        cold.clearsRenderCacheEachFrame = true
        for (step, character) in "typed".enumerated() {
            let now = Int64(step) * 16_666_667
            warm.frame(atNanos: now)
            cold.frame(atNanos: now)
            #expect(warm.screen == cold.screen, "step \(step)")
            warm.send(KeyEvent(key: .character(character)))
            cold.send(KeyEvent(key: .character(character)))
        }
    }
}
