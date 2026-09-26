//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HelpArrivalWidthTests.swift
//
//  The pointer arriving on a view with help text drops that view from the
//  render cache, so it draws and asks for the tooltip's wake. It moves no
//  cell, so it keeps the sizes: a clear that drops sizes moves
//  `RenderCache.sizeClearGeneration`, and every windowed stack in the app then
//  re-measures the widest row it keeps a width for.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitView

/// How many times each row was built.
@MainActor
private final class BuildCount {
    private(set) var byRow: [Int: Int] = [:]
    func note(_ index: Int) { byRow[index, default: 0] += 1 }
    func reset() { byRow = [:] }
}

/// Row 200 is the widest, and off screen: only a measure builds it.
private struct CountedRow: View {
    let index: Int
    let count: BuildCount

    var body: some View {
        count.note(index)
        return Text(String(repeating: "\(index % 10)", count: index == 200 ? 120 : 8))
    }
}

/// A `CountedRow`, with help text when it is row 3.
private struct HelpRow: View {
    let index: Int
    let count: BuildCount

    var body: some View {
        if index == 3 {
            CountedRow(index: index, count: count).help("about row 3")
        } else {
            CountedRow(index: index, count: count)
        }
    }
}

/// A windowed stack in a two-axis scroll view, with help text on row 3, which
/// is on screen.
private struct HelpPage: App {
    let count: BuildCount

    init() { self.init(count: BuildCount()) }

    init(count: BuildCount) { self.count = count }

    var body: some Scene {
        WindowGroup {
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<400, id: \.self) { HelpRow(index: $0, count: count) }
                }
            }
            .frame(width: 40, height: 12)
        }
        // Motion reporting, which a live app turns on for the frame after a
        // view asks; a headless one applies only what the scene says.
        .mouseSupport(.full)
    }
}

@MainActor
@Suite("A pointer arriving on help text keeps the sizes it moved nothing of")
struct HelpArrivalWidthTests {
    /// The pointer arriving on a view with help text in a row on screen: the
    /// view is dropped from the cache so it draws and asks for the tooltip's
    /// wake, and nothing about it changes size. Reported as a `@State` write
    /// is, it dropped sizes too, and the stack re-measured its widest row.
    @Test("A pointer arriving on help text in a windowed stack does not re-check its width")
    func helpArrivalInTheStack() throws {
        let built = BuildCount()
        let app = HeadlessApp(HelpPage(count: built), width: 60, height: 16)
        var frame = 0
        func step() {
            frame += 1
            app.frame(atNanos: 1_000_000_000 + Int64(frame) * 16_666_667)
        }
        for _ in 0..<5 { step() }
        built.reset()
        let lines = app.screen.map(\.stripped)
        let y = try #require(lines.firstIndex { $0.contains("33333333") }, "precondition: row 3 is on screen")
        let x = lines[y].distance(from: lines[y].startIndex, to: try #require(lines[y].range(of: "33333333")).lowerBound)
        let (generation, clears) = (app.renderCache.sizeClearGeneration, app.renderCache.stats.subtreeClears)
        app.send(MouseEvent(button: .none, phase: .moved, x: x + 1, y: y))
        for _ in 0..<3 { step() }
        #expect(app.renderCache.stats.subtreeClears > clears, "precondition: the arrival was reported")
        #expect(
            app.renderCache.sizeClearGeneration == generation,
            "the arrival dropped sizes: \(app.renderCache.sizeClearGeneration - generation) clears")
        let widestBuilt = built.byRow[200] ?? 0
        #expect(widestBuilt == 0, "the widest row was re-measured \(widestBuilt) times")
    }
}
