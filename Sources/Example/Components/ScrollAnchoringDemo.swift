//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollAnchoringDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// The scroll-anchoring demos on the ScrollView page, in three parts:
///
///   1. **Anchor a chosen row** — pick any row, anchor it, then insert or
///      remove rows around it; it keeps its place on screen while the scroll
///      position moves. Arrow keys (or the wheel) break the anchor and scroll
///      normally, and once the anchor is forced off its line (e.g. rows above
///      it are deleted) it stays where it landed rather than springing back.
///   2. **Selection becomes the anchor** — a List that follows the bottom (like
///      a log) until you select a row, which shadow-switches the anchor onto
///      that row so newly appended rows no longer pull the view off it.
///   3. **Anchor at the top or bottom** — the two edge anchors: `.top` keeps the
///      view at the start as rows are appended; `.bottom` follows the tail.
struct ScrollAnchoringDemo: View {

    // MARK: Section 1 — anchor a chosen row

    @State private var rows: [Int] = Array(1...40)
    @State private var pickedRow = 20
    @State private var rowAnchor: ScrollAnchor<Int>?
    @State private var nextRow = 100

    // MARK: Section 2 — selection becomes the anchor

    @State private var logRows: [Int] = Array(1...30)
    @State private var selection: Int?
    @State private var selAnchor: ScrollAnchor<Int>?
    @State private var nextLogRow = 200

    // MARK: Section 3 — top vs bottom

    @State private var edgeRows: [Int] = Array(1...14)
    @State private var edgeAnchor: ScrollAnchor<Int>? = .bottom
    @State private var nextEdgeRow = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            rowSection
            selectionSection
            edgeSection
        }
    }

    // MARK: - Section 1

    private var rowSection: some View {
        DemoSection(L("page.scrollView.anchorSection")) {
            VStack(alignment: .leading, spacing: 1) {
                Text(L("page.scrollView.anchorBody"))
                .foregroundStyle(.palette.foregroundSecondary)

                ScrollView {
                    // LazyVStack, not VStack: anchoring is a property of the
                    // windowed render paths (a plain VStack has no window).
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows, id: \.self) { row in rowLine(row) }
                    }
                }
                .frame(height: 8)
                .border(color: .palette.border)
                .anchorPosition($rowAnchor)

                Stepper(
                    "\(L("page.scrollView.anchorPick")): \(pickedRow)",
                    value: $pickedRow, in: 1...40)
                HStack(spacing: 1) {
                    Button(L("page.scrollView.anchorHold")) { rowAnchor = .row(pickedRow) }
                    Button(L("page.scrollView.anchorRelease")) { rowAnchor = .window }
                }
                HStack(spacing: 1) {
                    Button(L("page.scrollView.anchorInsert")) { insertAboveTarget() }
                    Button(L("page.scrollView.anchorRemove")) { removeAboveTarget() }
                    Button(L("page.scrollView.anchorReset")) { resetRows() }
                }
                ValueDisplayRow(L("page.scrollView.anchorState"), describe(rowAnchor))
            }
        }
    }

    @ViewBuilder
    private func rowLine(_ row: Int) -> some View {
        if row == anchoredValue {
            Text("▶ \(L("page.scrollView.anchorRowLabel")) \(row)")
            .bold()
            .foregroundStyle(.palette.accent)
        } else {
            Text("  \(L("page.scrollView.anchorRowPlain")) \(row)")
        }
    }

    /// The value of the currently anchored row, if a specific row is held.
    private var anchoredValue: Int? {
        if case .row(let value)? = rowAnchor { return value }
        return nil
    }

    /// Inserts rows just above the held (or picked) row, so the hold is visible
    /// as its neighbours change.
    private func insertAboveTarget() {
        let target = anchoredValue ?? pickedRow
        guard let index = rows.firstIndex(of: target) else { return }
        let inserted = (0..<5).map { nextRow + $0 }
        nextRow += 5
        rows.insert(contentsOf: inserted, at: max(0, index - 2))
    }

    private func removeAboveTarget() {
        let target = anchoredValue ?? pickedRow
        guard let index = rows.firstIndex(of: target), index > 0 else { return }
        rows.removeSubrange(max(0, index - 5)..<index)
    }

    private func resetRows() {
        rows = Array(1...40)
        nextRow = 100
    }

    // MARK: - Section 2

    private var selectionSection: some View {
        DemoSection(L("page.scrollView.anchorSelSection")) {
            VStack(alignment: .leading, spacing: 1) {
                Text(L("page.scrollView.anchorSelBody"))
                .foregroundStyle(.palette.foregroundSecondary)

                List(selection: $selection) {
                    ForEach(logRows, id: \.self) { row in
                        Text("\(L("page.scrollView.anchorLogLine")) \(row)")
                    }
                }
                // No `.border()` here, unlike the two ScrollView demos above and
                // below: a List draws its own. Its frame height is inclusive of
                // that border, so 10 puts this box on exactly the same 10 screen
                // rows as a bordered `ScrollView.frame(height: 8)`.
                .frame(height: 10)
                // The List declares a Bottom edge anchor, so selecting a row
                // shadow-switches the bound anchor onto that row (§1.2) — the
                // read-out flips to "holding row N" and the List then pins it:
                // inserting rows above holds the selected row on its line. A
                // wheel scroll releases it back to Window.
                .defaultScrollAnchor(.bottom)
                .anchorPosition($selAnchor)

                HStack(spacing: 1) {
                    Button(L("page.scrollView.anchorInsert")) { insertAboveSelection() }
                    Button(L("page.scrollView.anchorReset")) { resetSelection() }
                }
                ValueDisplayRow(
                    L("page.scrollView.anchorSelSelection"),
                    selection.map(String.init) ?? "—")
                ValueDisplayRow(L("page.scrollView.anchorState"), describe(selAnchor))
            }
        }
    }

    /// Inserts rows directly above the selected (anchored) row, so the hold is
    /// visible: the selected row keeps its line while its neighbours change.
    private func insertAboveSelection() {
        let target = selection ?? logRows.first
        guard let value = target, let index = logRows.firstIndex(of: value) else { return }
        let inserted = (0..<5).map { nextLogRow + $0 }
        nextLogRow += 5
        logRows.insert(contentsOf: inserted, at: index)
    }

    private func resetSelection() {
        logRows = Array(1...30)
        nextLogRow = 200
        selection = nil
        selAnchor = nil
    }

    // MARK: - Section 3

    private var edgeSection: some View {
        DemoSection(L("page.scrollView.anchorEdgeSection")) {
            VStack(alignment: .leading, spacing: 1) {
                Text(L("page.scrollView.anchorEdgeBody"))
                .foregroundStyle(.palette.foregroundSecondary)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(edgeRows, id: \.self) { row in
                            Text("\(L("page.scrollView.anchorLogLine")) \(row)")
                        }
                    }
                }
                .frame(height: 8)
                .border(color: .palette.border)
                // BOUND, not declared: picking an edge writes it into the
                // binding, which is the code-side `anchor(to:)` — the write
                // jumps the view to that edge, and it then holds it. A
                // declaration alone could not demo Top: both edges engage
                // POSITIONALLY (being at the edge is the engagement), so
                // switching to Top halfway down the content leaves it nothing
                // to do, and the section would read as "Top is broken" when it
                // is only "Top is not engaged".
                .anchorPosition($edgeAnchor)

                Picker(
                    L("page.scrollView.anchorEdgePick"),
                    selection: Binding(
                        get: { edgeAnchor != .top },
                        set: { edgeAnchor = $0 ? .bottom : .top })
                ) {
                    Text(L("page.scrollView.anchorEdgeTop")).tag(false)
                    Text(L("page.scrollView.anchorEdgeBottom")).tag(true)
                }
                HStack(spacing: 1) {
                    Button(L("page.scrollView.anchorAppend")) { appendEdgeRow() }
                    Button(L("page.scrollView.anchorPrepend")) { prependEdgeRow() }
                    Button(L("page.scrollView.anchorReset")) { resetEdge() }
                }
                // Scrolling the box by hand flips this to "released" — the
                // §1.2 shadow-switch, visible. Matches the other two sections.
                ValueDisplayRow(L("page.scrollView.anchorState"), describe(edgeAnchor))
            }
        }
    }

    private func appendEdgeRow() {
        edgeRows.append(nextEdgeRow)
        nextEdgeRow += 1
    }

    /// Inserting at the FRONT is what tells the two edges apart. Appending only
    /// exercises Bottom (Top has nothing to do — the start hasn't moved), so
    /// without this button Top looked inert next to it.
    private func prependEdgeRow() {
        edgeRows.insert(nextEdgeRow, at: 0)
        nextEdgeRow += 1
    }

    private func resetEdge() {
        edgeRows = Array(1...14)
        nextEdgeRow = 15
    }

    // MARK: - Shared read-out

    /// Spells out a bound anchor, including the distinction the optional exists
    /// for: `nil` (never departed from the declaration) reads differently from
    /// `.window` (explicitly released).
    private func describe(_ anchor: ScrollAnchor<Int>?) -> String {
        switch anchor {
        case .none: L("page.scrollView.anchorState.none")
        case .window: L("page.scrollView.anchorState.window")
        case .top: L("page.scrollView.anchorState.top")
        case .bottom: L("page.scrollView.anchorState.bottom")
        case .row(let value): "\(L("page.scrollView.anchorState.row")) \(value)"
        }
    }
}
