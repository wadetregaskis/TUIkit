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

/// A line with help text, and a line that counts the double clicks on it.
private struct PointerApp: App {
    init() {}

    var body: some Scene {
        WindowGroup { PointerPage() }
            // Motion reporting, for the hover; a headless app applies only what
            // the scene says.
            .mouseSupport(.full)
    }
}

private struct PointerPage: View {
    @State private var doubleClicks = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("explained").help("about it")
            Text("double clicks: \(doubleClicks)").onTapGesture(count: 2) { doubleClicks += 1 }
        }
    }
}

/// A pop-up menu and a line that says what it last ran — under an app header,
/// or not.
private struct MenuApp: App {
    let headed: Bool

    init() { headed = false }

    init(headed: Bool) { self.headed = headed }

    var body: some Scene {
        WindowGroup {
            if headed {
                MenuPage().appHeader { Text("A header over the page") }
            } else {
                MenuPage()
            }
        }
    }
}

private struct MenuPage: View {
    @State private var ran = "nothing"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Menu("Actions") {
                Button("First") { ran = "first" }
                Button("Second") { ran = "second" }
            }
            Text("ran \(ran)")
        }
    }
}

/// Whether some line of `screen`, with its styling stripped, contains `text`.
private func shows(_ text: String, on screen: [String]) -> Bool {
    screen.contains { $0.stripped.contains(text) }
}

/// Where `text` first appears on `screen`: column and row.
private func position(of text: String, on screen: [String]) -> (x: Int, y: Int)? {
    for (row, line) in screen.map(\.stripped).enumerated() {
        if let range = line.range(of: text) {
            return (line.distance(from: line.startIndex, to: range.lowerBound), row)
        }
    }
    return nil
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

    /// Time is the caller's, events included: the pointer arrives at the
    /// instant of the frame before it, so the tooltip's delay counts from
    /// there. Read off the machine's clock, the wake fell wherever the machine
    /// had got to — however long the frames before it took to draw — and two
    /// instances fed one script asked for it at two instants.
    @Test("A pointer arriving between frames arrives at the caller's time, and the tooltip's wake counts from it")
    func aHoverArrivesAtTheCallersTime() throws {
        let app = HeadlessApp(PointerApp(), width: 40, height: 10)
        app.frame(atNanos: 16_666_667)
        let (x, y) = try #require(position(of: "explained", on: app.screen), "precondition: the line is drawn")
        app.send(MouseEvent(button: .none, phase: .moved, x: x + 1, y: y))
        app.frame(atNanos: 33_333_334)
        // `tooltipDelay`'s default, 0.6 s, after the frame the pointer arrived behind.
        let wake = app.nextWake(after: 33_333_334)
        #expect(wake == 616_666_667, "the tooltip's wake is at \(String(describing: wake))")
    }

    /// The other thing counted from an arrival: two presses make a double click
    /// when they land within the window of each other on the caller's clock,
    /// not on the machine's, where a script's clicks are all microseconds apart.
    @Test("Two clicks a second apart on the caller's clock are two clicks, and two a frame apart are a double click")
    func clicksAreTimedOnTheCallersClock() throws {
        let app = HeadlessApp(PointerApp(), width: 40, height: 10)
        var now: Int64 = 16_666_667
        app.frame(atNanos: now)
        let (x, y) = try #require(position(of: "double clicks", on: app.screen), "precondition: the line is drawn")
        func click(after nanos: Int64) {
            app.send(MouseEvent(button: .left, phase: .pressed, x: x + 1, y: y))
            app.send(MouseEvent(button: .left, phase: .released, x: x + 1, y: y))
            now += nanos
            app.frame(atNanos: now)
        }
        click(after: 1_000_000_000)
        click(after: 16_666_667)
        #expect(shows("double clicks: 0", on: app.screen), "two clicks a second apart made a double click")
        click(after: 16_666_667)
        #expect(shows("double clicks: 1", on: app.screen), "two clicks a frame apart made no double click")
    }

    /// A script aims at what it SEES: a position on the screen, the header's
    /// lines included. The app's event funnel takes the header's height off
    /// every mouse event before it dispatches, because hit regions are laid out
    /// in the content's coordinates; a harness that dispatched the screen's row
    /// as it stood pressed whatever was drawn that many rows further down.
    @Test("A click lands on what the screen draws there, under an app header")
    func aClickUnderAHeaderLandsWhereItIsDrawn() throws {
        let app = HeadlessApp(MenuApp(headed: true), width: 40, height: 12)
        app.frame(atNanos: 16_666_667)
        #expect(shows("A header over the page", on: app.screen), "precondition: the header is drawn")
        let (x, y) = try #require(position(of: "Actions", on: app.screen), "precondition: the menu is drawn")
        app.send(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        app.send(MouseEvent(button: .left, phase: .released, x: x, y: y))
        app.frame(atNanos: 33_333_334)
        #expect(shows("Second", on: app.screen), "the click did not open the menu drawn where it landed")
    }

    /// Which device opened a menu decides what it highlights: the pointer
    /// nothing, the keyboard its first item. The app's event funnel records the
    /// device before it dispatches; a harness that skipped the record opened
    /// every menu as the keyboard does, whatever opened it. Down then Return
    /// tells the two apart: from nothing, Down lands on the first item; from
    /// the first, on the second.
    @Test("A menu opened by a click highlights nothing, as the pointer opens one in the app")
    func aClickOpensAMenuAsThePointer() throws {
        // No header, so the click lands wherever the header's height is taken.
        let app = HeadlessApp(MenuApp(headed: false), width: 40, height: 12)
        app.frame(atNanos: 16_666_667)
        let (x, y) = try #require(position(of: "Actions", on: app.screen), "precondition: the menu is drawn")
        app.send(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        app.send(MouseEvent(button: .left, phase: .released, x: x, y: y))
        app.frame(atNanos: 33_333_334)
        #expect(shows("Second", on: app.screen), "precondition: the click opened the menu")
        app.send(KeyEvent(key: .down))
        app.frame(atNanos: 50_000_000)
        app.send(KeyEvent(key: .enter))
        app.frame(atNanos: 66_666_667)
        #expect(shows("ran first", on: app.screen), "Down from a click-opened menu did not land on its first item")
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
