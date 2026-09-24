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

/// A marker that a button moves ten cells across inside `withAnimation`.
private struct SlidingApp: App {
    init() {}

    var body: some Scene {
        WindowGroup { SlidingPage() }
    }
}

private struct SlidingPage: View {
    @State private var isAcross = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("go") {
                withAnimation(.linear(duration: 1)) { isAcross.toggle() }
            }
            Text("@").padding(.leading, isAcross ? 10 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    /// The harness exists to watch what an app draws, and what an app draws
    /// under `withAnimation` is every frame between the two values. Without a
    /// scheduler fencing the frame nothing could animate, and the marker
    /// arrived at its end on the frame after the key.
    @Test("A change made inside withAnimation is drawn part-way on the frames between")
    func animatedChangesPlayOut() {
        let app = HeadlessApp(SlidingApp(), width: 40, height: 10)
        app.frame(atNanos: 0)
        func column() -> Int? {
            for line in app.screen.map(\.stripped) {
                if let range = line.range(of: "@") {
                    return line.distance(from: line.startIndex, to: range.lowerBound)
                }
            }
            return nil
        }
        let start = column()
        #expect(start != nil, "precondition: the marker is drawn")
        guard let start else { return }

        #expect(app.send(KeyEvent(key: .enter)), "precondition: the button took the key")
        app.frame(atNanos: 16_666_667)
        #expect(column() == start, "the change did not start from where it was")
        app.frame(atNanos: 516_666_667)
        #expect(column() == start + 5, "not half-way across half-way through")
        app.frame(atNanos: 1_100_000_000)
        #expect(column() == start + 10)
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
