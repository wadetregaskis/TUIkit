//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListMixedRowBadgeTests.swift
//
//  `.badge(_:)` on a `ForEach` row, in the arrangements where the list walks
//  its children rather than windowing them: a `ForEach` with a static row
//  beside it, and the same inside a `Section`. Those walks read the badge off
//  the child's view value, and a `ForEach` row is wrapped in `_MemoizedRow`,
//  which is `Renderable` and therefore opaque to that cast — so every badge
//  under the `ForEach` was dropped while the static row beside it kept its
//  own. A `ForEach` that is the whole content takes the windowed path, which
//  reads the badge off the built row, and was never affected; it is pinned
//  here so a future change cannot quietly trade one arrangement for the other.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
private func listContext(width: Int = 30, height: Int = 10) -> RenderContext {
    var environment = EnvironmentValues()
    environment.focusManager = FocusManager()
    return RenderContext(
        availableWidth: width,
        availableHeight: height,
        environment: environment,
        tuiContext: TUIContext()
    ).isolatingRenderCache()
}

@MainActor
private func strippedLines(_ view: some View, context: RenderContext) -> [String] {
    renderToBuffer(view, context: context).lines.map { $0.stripped }
}

/// The rendered row carrying `label`, or `nil`.
@MainActor
private func row(_ label: String, in lines: [String]) -> String? {
    lines.first { $0.contains(label) }
}

/// A badge is drawn to the RIGHT of the row's own text — the same shape
/// `ListRenderTests.badgeOnDirectChild` asserts for a static row, so that a
/// digit appearing anywhere in the line cannot pass for a badge.
@MainActor
private func expectBadge(
    _ badge: String,
    after label: String,
    in lines: [String],
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard let line = row(label, in: lines) else {
        Issue.record("no row drew '\(label)': \(lines)", sourceLocation: sourceLocation)
        return
    }
    guard let text = line.firstRange(of: label), let mark = line.firstRange(of: badge) else {
        #expect(
            Bool(false), "the badge '\(badge)' is missing from '\(line)'",
            sourceLocation: sourceLocation)
        return
    }
    #expect(
        text.upperBound < mark.lowerBound,
        "the badge '\(badge)' sits right of '\(label)': '\(line)'",
        sourceLocation: sourceLocation)
}

@MainActor
@Suite("List badges on ForEach rows", .rendersEnglishUI)
struct ListMixedRowBadgeTests {

    @Test("A ForEach row's badge survives a static row beside it")
    func badgeOnForEachRowBesideStaticRow() {
        let lines = strippedLines(
            List {
                Text("Inbox").badge(7)
                ForEach(["Drafts", "Sent"], id: \.self) { name in
                    Text(name).badge(9)
                }
            },
            context: listContext())

        expectBadge("7", after: "Inbox", in: lines)
        expectBadge("9", after: "Drafts", in: lines)
        expectBadge("9", after: "Sent", in: lines)
    }

    @Test("A ForEach row's badge survives inside a Section beside a static row")
    func badgeOnForEachRowInsideSection() {
        let lines = strippedLines(
            List {
                Section("Mail") {
                    Text("Inbox").badge(7)
                    ForEach(["Drafts", "Sent"], id: \.self) { name in
                        Text(name).badge(9)
                    }
                }
            },
            context: listContext())

        expectBadge("7", after: "Inbox", in: lines)
        expectBadge("9", after: "Drafts", in: lines)
        expectBadge("9", after: "Sent", in: lines)
    }

    @Test("A string badge on a ForEach row beside a static row survives too")
    func stringBadgeOnForEachRow() {
        let lines = strippedLines(
            List {
                Text("Inbox").badge("new")
                ForEach(["Drafts"], id: \.self) { name in
                    Text(name).badge("draft")
                }
            },
            context: listContext(width: 36))

        expectBadge("new", after: "Inbox", in: lines)
        expectBadge("draft", after: "Drafts", in: lines)
    }

    @Test("A ForEach that is the whole list still badges its rows")
    func badgeOnForEachAsWholeContent() {
        // The windowed path, which reads the badge off the row it builds. It
        // was never broken — pinned so the fix above cannot be mistaken for
        // the whole story, and so a later change cannot silently swap which
        // arrangement works.
        let lines = strippedLines(
            List {
                ForEach(["Drafts", "Sent"], id: \.self) { name in
                    Text(name).badge(9)
                }
            },
            context: listContext())

        expectBadge("9", after: "Drafts", in: lines)
        expectBadge("9", after: "Sent", in: lines)
    }

    @Test("A badge-less ForEach row beside a badged static row is not given one")
    func badgeIsNotInvented() {
        // The unwrap must answer for the row it is asked about, not leak the
        // neighbour's badge or the enclosing environment's.
        let lines = strippedLines(
            List {
                Text("Inbox").badge(7)
                ForEach(["Drafts"], id: \.self) { name in
                    Text(name)
                }
            },
            context: listContext())

        expectBadge("7", after: "Inbox", in: lines)
        guard let drafts = row("Drafts", in: lines) else {
            Issue.record("no row drew 'Drafts': \(lines)")
            return
        }
        #expect(
            !drafts.contains("7"), "the plain row carries no badge of its own: '\(drafts)'")
        #expect(
            !drafts.contains("9"), "the plain row carries no badge of its own: '\(drafts)'")
    }
}
