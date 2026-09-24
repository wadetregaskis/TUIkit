//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListConditionalArmStateTests.swift
//
//  An `if`/`else` a `List` or a `Section` looks through for its rows resets the
//  arm it leaves, as a conditional drawn any other way does (and as SwiftUI
//  does): the rows the flip took away start afresh when it brings them back.
//  The list takes the conditional off without drawing it, so the render that
//  records the live arm and drops the other's `@State`
//  (`ConditionalView.renderToBuffer`) never ran, and every identity under a list
//  is retained — an expanded row came back expanded.
//
//  The oracle is a row that counts its own appearances in its `@State`: kept, a
//  row brought back by a flip reads 2; reset, 1.
//
//  The `Section` case passed before the fix too: a section still renders its
//  whole content once a frame into a buffer nothing reads
//  (`Section.extractSectionInfo`), and that render goes through the
//  conditional's own. It is here so removing that render cannot bring the
//  hole to sections.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// A row that counts how often it has appeared, in its own `@State`.
private struct AppearanceCounter: View {
    let label: String
    @State private var appearances = 0

    var body: some View {
        Text(verbatim: "\(label) \(appearances)").onAppear { appearances += 1 }
    }
}

/// Where the conditional sits: the list's whole content, a section's, or the
/// body of a view of the app's own.
enum ArmHost: CaseIterable, Sendable {
    case list, section, customBody
}

/// Rows by an `if`/`else` whose arms loop over different elements.
private struct Arms: View {
    let showsFirst: Bool

    var body: some View {
        if showsFirst {
            ForEach(["first"], id: \.self) { AppearanceCounter(label: $0) }
        } else {
            ForEach(["second"], id: \.self) { AppearanceCounter(label: $0) }
        }
    }
}

private struct ArmsApp: App {
    let host: ArmHost
    init() { host = .list }
    init(host: ArmHost) { self.host = host }
    var body: some Scene { WindowGroup { ArmsPage(host: host) } }
}

private struct ArmsPage: View {
    let host: ArmHost
    @State private var showsFirst = true

    var body: some View {
        list.onKeyPress(.character("f")) { showsFirst.toggle() }
    }

    @ViewBuilder private var list: some View {
        switch host {
        case .list:
            List {
                if showsFirst {
                    ForEach(["first"], id: \.self) { AppearanceCounter(label: $0) }
                } else {
                    ForEach(["second"], id: \.self) { AppearanceCounter(label: $0) }
                }
            }
        case .section:
            List {
                Section("S") {
                    if showsFirst {
                        ForEach(["first"], id: \.self) { AppearanceCounter(label: $0) }
                    } else {
                        ForEach(["second"], id: \.self) { AppearanceCounter(label: $0) }
                    }
                }
            }
        case .customBody:
            List { Arms(showsFirst: showsFirst) }
        }
    }
}

@MainActor
@Suite("A List looking through an if/else resets the arm it leaves")
struct ListConditionalArmStateTests {
    @Test("A row a flip brings back starts afresh", arguments: ArmHost.allCases)
    func flippedBackRowStartsAfresh(host: ArmHost) {
        let app = HeadlessApp(ArmsApp(host: host), width: 30, height: 8)
        var now: Int64 = 0
        func frames(_ count: Int = 3) {
            for _ in 0..<count {
                now += 16_666_667
                app.frame(atNanos: now)
            }
        }
        func shows(_ text: String) -> Bool { app.screen.contains { $0.contains(text) } }

        frames()
        #expect(shows("first 1"), "\(host): the first arm appeared once: \(app.screen)")
        _ = app.send(KeyEvent(key: .character("f")))
        frames()
        #expect(shows("second 1"), "\(host): the second arm appeared once: \(app.screen)")
        _ = app.send(KeyEvent(key: .character("f")))
        frames()
        #expect(
            shows("first 1"),
            "\(host): the first arm kept its state across the flip: \(app.screen)")
    }
}
