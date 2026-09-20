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
//  Two cases assert on the extracted `ListRow.badge` / `BadgeValue?` rather
//  than on rendered text — identity and presence of data is a structural
//  question, and a string search can pass for the wrong reason (a stray
//  digit, a coincidental substring):
//
//  - `badgeOnForEachRowInsideSection` calls `Section.extractListRows(context:)`
//    directly, the same call `SectionListRowExtractorTests` already makes on
//    a bare `Section`, reading `.badge` where that suite reads `.id`.
//  - `badgeOnForEachAsWholeContent` calls `extractListRows(context:)` on a
//    bare `ForEach`, which conforms to the same `ListRowExtractor` protocol
//    `Section` does.
//
//  Both call the actual production method whose BODY is what `95798a0b`
//  changed (a plain `extractBadgeValue` to the row-unwrapping
//  `extractRowBadgeValue`), so which one runs depends on whichever `Sources`
//  are checked out — the same way a full render would, but without one.
//
//  The other three stay rendered, because the arrangement they exercise —
//  a static row beside a `ForEach`, *without* a `Section` — is walked by
//  `_ListCore.extractFromChildren`, which is private and has no equivalent to
//  `Section`/`ForEach`'s `extractListRows`. The only way to reach it at all is
//  a full render, so for these three "does it appear on screen" is not a
//  looser stand-in for the structural question — it is the only question this
//  suite can ask them. (`extractRowBadgeValue` itself is `internal` and
//  reachable from a test, but calling it BY NAME would couple the test to a
//  symbol `95798a0b` introduces — a test that cannot even compile against the
//  tree before the fix cannot pin the regression at that boundary; verified
//  empirically in the scratch worktree below.)
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
        // `_ListCore.extractFromChildren` is private, so this is the only
        // route in — see the file header.
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
        let section = Section("Mail") {
            Text("Inbox").badge(7)
            ForEach(["Drafts", "Sent"], id: \.self) { name in
                Text(name).badge(9)
            }
        }

        // Same call `SectionListRowExtractorTests.sectionExtractsRowsFromForEach`
        // makes on a bare `Section` — only the header/footer wrapping differs,
        // and `extractListRows` never sees those; it walks `content` alone,
        // which is exactly the static-row-beside-`ForEach` shape this suite is
        // about.
        let rows: [ListRow<String>] = section.extractListRows(context: listContext())

        #expect(rows.map(\.badge) == [.int(7), .int(9), .int(9)])
    }

    @Test("A string badge on a ForEach row beside a static row survives too")
    func stringBadgeOnForEachRow() {
        // `_ListCore.extractFromChildren` again — see the file header.
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
        //
        // `ForEach` conforms to `ListRowExtractor` itself (the same protocol
        // `Section` does), so this calls `extractListRows` directly on it —
        // the same pattern as `badgeOnForEachRowInsideSection` above, applied
        // to the other conformer. `_ListCore`'s actual windowed dispatch calls
        // `listRowID`/`makeListRowContent` rather than `extractListRows`
        // itself, but `extractListRows`'s own implementation calls those same
        // two functions per element, so the badge computation exercised here
        // is identical to what a real `List` would run.
        let each = ForEach(["Drafts", "Sent"], id: \.self) { name in
            Text(name).badge(9)
        }
        let rows: [ListRow<String>] = each.extractListRows(context: listContext())

        #expect(rows.map(\.badge) == [.int(9), .int(9)])
    }

    @Test("A badge-less ForEach row beside a badged static row is not given one")
    func badgeIsNotInvented() {
        // The unwrap must answer for the row it is asked about, not leak the
        // neighbour's badge or the enclosing environment's. `_ListCore
        // .extractFromChildren` again — see the file header — and, as the
        // original commit's own RED run recorded, this arrangement carries no
        // badge on the `ForEach` row at all, so it cannot distinguish the fix
        // from its absence; it is a pin of the no-leak invariant, not a
        // regression catcher.
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
