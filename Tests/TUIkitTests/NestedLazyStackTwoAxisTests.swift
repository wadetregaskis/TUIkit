//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NestedLazyStackTwoAxisTests.swift
//
//  A lazy stack nested in the content of a view that scrolls both ways. It is
//  drawn whole, so it answers the width it is asked from the rows it walks —
//  except to the horizontal probe, which asks how far right the content can be
//  scrolled and may stop the walk short of rows the stack's kept width record
//  has counted. These hold both halves to the same rows in an eager `VStack`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

/// A row that is sometimes two lines, sometimes a filler right-aligned across
/// whatever it is offered, and at `wide` fifty cells past the viewport.
private struct TwoAxisRow: View {
    let label: String
    let index: Int
    let wide: Int

    var body: some View {
        if index == wide {
            Text("\(label) r\(index) " + String(repeating: "w", count: 50) + " END")
        } else if index % 7 == 3 {
            Text("\(label) r\(index) fill").frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            Text(index.isMultiple(of: 3) ? "\(label) r\(index)\nmore" : "\(label) r\(index)")
        }
    }
}

/// Four groups of ~270 such rows, centred, in an outer lazy stack — lazy
/// inside, or the eager twin. `w` moves the wide row, `t` writes above.
private struct TwoAxisGroupsApp: App {
    let lazy: Bool

    init() { self.init(lazy: true) }
    init(lazy: Bool) { self.lazy = lazy }

    var body: some Scene {
        WindowGroup { TwoAxisGroupsPage(lazy: lazy) }
    }
}

private struct TwoAxisGroupsPage: View {
    let lazy: Bool
    @State private var tick = 0
    @State private var wide = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("tick \(tick)")
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .center, spacing: 0) {
                    ForEach(0..<4, id: \.self) { group in
                        VStack(alignment: .center, spacing: 0) {
                            Text("group \(group)")
                            if lazy {
                                LazyVStack(alignment: .center, spacing: 0) {
                                    ForEach(0..<(270 + group), id: \.self) { index in
                                        TwoAxisRow(label: "g\(group)", index: index, wide: group == 1 ? wide : -1)
                                    }
                                }
                            } else {
                                VStack(alignment: .center, spacing: 0) {
                                    ForEach(0..<(270 + group), id: \.self) { index in
                                        TwoAxisRow(label: "g\(group)", index: index, wide: group == 1 ? wide : -1)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .onKeyPress(.character("t")) { tick += 1 }
        .onKeyPress(.character("w")) { wide = wide == 200 ? 5 : 200 }
    }
}

/// A header over 2,200 two-line rows — 4,401 lines, past the 4,096 the
/// horizontal probe offers — whose widest row is the last.
private struct TwoAxisTallApp: App {
    let lazy: Bool

    init() { self.init(lazy: true) }
    init(lazy: Bool) { self.lazy = lazy }

    var body: some Scene {
        WindowGroup { TwoAxisTallPage(lazy: lazy) }
    }
}

private struct TwoAxisTallPage: View {
    let lazy: Bool

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                Text("header")
                if lazy {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<2_200, id: \.self) { TwoAxisTallRow(index: $0) }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<2_200, id: \.self) { TwoAxisTallRow(index: $0) }
                    }
                }
            }
        }
    }
}

private struct TwoAxisTallRow: View {
    let index: Int

    var body: some View {
        Text(index == 2_199 ? "r\(index) " + String(repeating: "w", count: 60) + " END\nx" : "r\(index)\nx")
    }
}

@MainActor
@Suite("A lazy stack nested in a view that scrolls both ways")
struct NestedLazyStackTwoAxisTests {
    private static let frame: Int64 = 16_666_667

    @Test("Groups of filling, wrapping and wide rows draw what their eager twin draws")
    func groupsDrawWhatTheirEagerTwinDraws() {
        // The nested stacks answer every ask but the probe from the rows they
        // walk; the eager twin always has. A row that fills its offer is where
        // the two ways of counting a width part — as the offer, or as nothing
        // of its own — so the rows fill, centred, beside a row fifty cells
        // past the viewport, and the page scrolls both ways, writes, moves the
        // wide row and narrows. Content only: the vertical bar's thumb, placed
        // from an estimate by design, and the rows under the viewport go.
        let lazy = HeadlessApp(TwoAxisGroupsApp(lazy: true), width: 34, height: 12)
        let eager = HeadlessApp(TwoAxisGroupsApp(lazy: false), width: 34, height: 12)
        var script: [KeyEvent?] = [nil, nil, KeyEvent(key: .character("t"))]
        script += Array(repeating: KeyEvent(key: .pageDown), count: 12)
        script += Array(repeating: KeyEvent(key: .right), count: 30)
        script += [KeyEvent(key: .character("w")), KeyEvent(key: .end), KeyEvent(key: .character("t")), nil]
        script += Array(repeating: KeyEvent(key: .left), count: 10)
        script += [KeyEvent(key: .home), KeyEvent(key: .character("w")), nil]
        let content = { (app: HeadlessApp<TwoAxisGroupsApp>) in
            app.screen.dropLast(4).map { String($0.stripped.dropLast()) }
        }
        var diverged: [String] = []
        for (step, event) in script.enumerated() {
            if step == 50 {
                lazy.resize(width: 26, height: 10)
                eager.resize(width: 26, height: 10)
            }
            if let event {
                lazy.send(event)
                eager.send(event)
            }
            lazy.frame(atNanos: Int64(step) * Self.frame)
            eager.frame(atNanos: Int64(step) * Self.frame)
            if content(lazy) != content(eager) {
                diverged.append("step \(step): lazy \(content(lazy)) eager \(content(eager))")
            }
        }
        #expect(diverged.isEmpty, "\(diverged.count) screens differ: \(diverged.prefix(1))")
    }

    @Test("A nested stack taller than the horizontal probe's budget scrolls to a row past it")
    func probeStillCountsRowsPastItsBudget() {
        // The probe offers 4,096 lines; the stack is 4,400, and its widest row
        // the last. The walk stops short of that row, and the stack's kept
        // record, taken over every row, is what widens the canvas to it. Asked
        // like every other width, the probe missed it: the row wrapped at the
        // viewport and "END" was on a line of its own, never scrolled to.
        for lazy in [true, false] {
            let app = HeadlessApp(TwoAxisTallApp(lazy: lazy), width: 30, height: 10)
            app.frame(atNanos: 0)
            app.frame(atNanos: Self.frame)
            app.send(KeyEvent(key: .end))
            app.frame(atNanos: 2 * Self.frame)
            for step in 0..<80 {
                app.send(KeyEvent(key: .right))
                app.frame(atNanos: Int64(3 + step) * Self.frame)
            }
            let screen = app.screen.map(\.stripped)
            #expect(
                screen.contains { $0.contains("wwww END") },
                "\(lazy ? "lazy" : "eager"): the wide row's end, on its own line: \(screen)")
        }
    }
}
