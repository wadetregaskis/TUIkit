//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ButtonFillingLabelTests.swift
//
//  A button whose `@ViewBuilder` label fills its width — a `Spacer` between
//  two texts — draws as wide as it is offered. It reported itself rigid at
//  that width, so a row that holds it beside another control gave it its
//  whole offer and the other control nothing: the second button was not
//  drawn at all.
//
//  The button learns that its label fills by asking the label, at the
//  identity its style draws the label at: the standard variant draws it
//  inside an `HStack`, which gives it a child identity of its own, and a
//  label whose `Spacer` sits behind its own `@State` read that state fresh
//  anywhere else.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// `left`, a `Spacer`, `right`: a label that fills.
private struct FillingButtonLabel: View {
    var body: some View {
        HStack(spacing: 1) {
            Text(verbatim: "left")
            Spacer()
            Text(verbatim: "right")
        }
    }
}

/// The same, but its `Spacer` only appears once its own `@State` says so,
/// which it does on appearing.
private struct FillingOnceItHasAppeared: View {
    @State private var fills = false

    var body: some View {
        HStack(spacing: 1) {
            Text(verbatim: "left")
            if fills { Spacer() }
            Text(verbatim: "right")
        }
        .onAppear { fills = true }
    }
}

/// Which label, in which style.
enum FillingButtonCase: CaseIterable, Sendable, CustomStringConvertible {
    case filling, fillingPlain, fillingOnceAppeared, fillingOnceAppearedPlain

    var description: String {
        switch self {
        case .filling: "filling"
        case .fillingPlain: "filling, plain"
        case .fillingOnceAppeared: "filling once appeared"
        case .fillingOnceAppearedPlain: "filling once appeared, plain"
        }
    }
}

/// A filling button beside an OK button, in a row.
private struct BesideASiblingApp: App {
    let kind: FillingButtonCase

    init() { kind = .filling }
    init(kind: FillingButtonCase) { self.kind = kind }

    var body: some Scene {
        WindowGroup { BesideASibling(kind: kind) }
    }
}

private struct BesideASibling: View {
    let kind: FillingButtonCase

    var body: some View {
        HStack(spacing: 1) {
            switch kind {
            case .filling:
                Button(action: {}, label: { FillingButtonLabel() })
            case .fillingPlain:
                Button(action: {}, label: { FillingButtonLabel() }).buttonStyle(.plain)
            case .fillingOnceAppeared:
                Button(action: {}, label: { FillingOnceItHasAppeared() })
            case .fillingOnceAppearedPlain:
                Button(action: {}, label: { FillingOnceItHasAppeared() }).buttonStyle(.plain)
            }
            Button("OK") {}
        }
    }
}

@MainActor
@Suite("A button whose label fills says so")
struct ButtonFillingLabelTests {
    @Test("A filling button leaves its sibling room", arguments: FillingButtonCase.allCases)
    func leavesItsSiblingRoom(kind: FillingButtonCase) {
        let app = HeadlessApp(BesideASiblingApp(kind: kind), width: 40, height: 6)
        var now: Int64 = 0
        // Past the frame the `@State` label's appearing writes its state on.
        for _ in 0..<3 {
            now += 16_666_667
            app.frame(atNanos: now)
        }
        let row = app.screen.map(\.stripped).first { $0.contains("left") } ?? "<none>"
        #expect(row.contains("OK"), "\(kind): |\(row)|")
        #expect(row.contains("right"), "\(kind): |\(row)|")
    }

    @Test("A filling button leaves its sibling room when drawn directly")
    func leavesItsSiblingRoomDrawnDirectly() {
        let view = HStack(spacing: 1) {
            Button(action: {}, label: { FillingButtonLabel() })
            Button("OK") {}
        }
        let buffer = renderToBuffer(view, context: makeRenderContext(width: 40, height: 3))
        let row = buffer.lines.first?.stripped ?? ""
        #expect(row.contains("OK"), "|\(row)|")
        #expect(row.contains("right"), "|\(row)|")
    }
}
