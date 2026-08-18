//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OutlineGroupTests.swift
//
//  `OutlineGroup` — the flattening (which nodes are visible, at what depth),
//  the alignment that makes it read as a tree, and the interaction that opens
//  a branch. The flattening is the part worth pinning: every visible node has
//  to be its own row, or nothing that contains an outline can measure, window
//  or select one.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("OutlineGroup")
struct OutlineGroupTests {

    /// A small tree: two roots, one of which nests two levels.
    ///
    ///     Sources          (branch)
    ///       TUIkit         (branch)
    ///         Views        (leaf)
    ///       Core           (leaf)
    ///     README           (leaf)
    private struct Node: Identifiable {
        let id: String
        var children: [Self]?
    }

    private let tree = [
        Node(
            id: "Sources",
            children: [
                Node(id: "TUIkit", children: [Node(id: "Views", children: nil)]),
                Node(id: "Core", children: nil),
            ]),
        Node(id: "README", children: nil),
    ]

    private func harness(width: Int = 40, height: Int = 20) -> (TUIContext, RenderContext) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.terminalWidth = width
        return (
            tui,
            RenderContext(
                availableWidth: width, availableHeight: height, environment: environment,
                tuiContext: tui)
        )
    }

    /// One whole frame, the way the run loop does it.
    @discardableResult
    private func frame(_ view: some View, tui: TUIContext, context: RenderContext) -> FrameBuffer {
        tui.mouseEventDispatcher.beginRenderPass()
        tui.keyEventDispatcher.clearHandlers()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        context.environment.focusManager?.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
        tui.stateStorage.endRenderPass()
        context.environment.focusManager?.endRenderPass()
        return buffer
    }

    /// Every rendered line, ANSI stripped and trailing blanks trimmed. Blank
    /// lines are KEPT — a stray one is exactly the defect these look for.
    private func lines(_ buffer: FrameBuffer) -> [String] {
        var rows = buffer.lines.map { $0.stripped.replacingOccurrences(of: " +$", with: "", options: .regularExpression) }
        while rows.last?.isEmpty == true { rows.removeLast() }
        return rows
    }

    private func outline() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            OutlineGroup(tree, children: \.children) { node in
                Text(verbatim: node.id)
            }
        }
    }

    private func column(of needle: String, in line: String) -> Int? {
        line.range(of: needle).map { line.distance(from: line.startIndex, to: $0.lowerBound) }
    }

    // MARK: - Flattening

    @Test("closed: only the roots, one row each")
    func closedShowsOnlyRoots() {
        let (tui, context) = harness()
        let rendered = lines(frame(outline(), tui: tui, context: context))
        #expect(rendered.count == 2, "two roots, two rows — got \(rendered)")
        #expect(rendered[0].contains("Sources"))
        #expect(rendered[1].contains("README"))
        #expect(rendered.contains { $0.contains("TUIkit") } == false, "children stay hidden")
    }

    /// The whole design in one assertion: a branch's children are the NEXT
    /// rows, not a subtree drawn inside the branch's own row. A nested render
    /// would put "TUIkit" on the same row as "Sources" or leave a blank one
    /// between them.
    @Test("opening a branch adds one row per child, and no blank ones")
    func openingAddsSiblingRows() throws {
        let (tui, context) = harness()
        let view = outline()
        frame(view, tui: tui, context: context)
        let focus = try #require(context.environment.focusManager)
        #expect(focus.dispatchKeyEvent(KeyEvent(key: .enter)), "the first branch takes Return")

        let rendered = lines(frame(view, tui: tui, context: context))
        let names = ["Sources", "TUIkit", "Core", "README"]
        let order = rendered.map { row in names.first { row.contains($0) } ?? "?" }
        #expect(
            order == names, "one row per visible node, in reading order: \(rendered)")
        #expect(rendered.allSatisfy { !$0.isEmpty }, "no blank row anywhere: \(rendered)")
    }

    @Test("a closed branch's descendants are never built")
    func closedBranchesBuildNothing() {
        let (tui, context) = harness()
        var built: [String] = []
        let view = VStack(alignment: .leading, spacing: 0) {
            OutlineGroup(tree, children: \.children) { node in
                built.append(node.id)
                return Text(verbatim: node.id)
            }
        }
        frame(view, tui: tui, context: context)
        #expect(
            built.contains("TUIkit") == false && built.contains("Views") == false,
            "only visible nodes are built: \(built)")
    }

    // MARK: - Alignment

    /// A leaf has no triangle, so without an extra step its label would sit
    /// under its sibling's triangle rather than under its sibling's label, and
    /// a column of names would not be a column.
    @Test("a leaf's label lines up with its siblings' labels")
    func leafAlignsWithSiblingLabels() throws {
        let (tui, context) = harness()
        let view = outline()
        frame(view, tui: tui, context: context)
        let focus = try #require(context.environment.focusManager)
        _ = focus.dispatchKeyEvent(KeyEvent(key: .enter))
        let rendered = lines(frame(view, tui: tui, context: context))

        let branch = try #require(column(of: "TUIkit", in: rendered[1]))
        let leaf = try #require(column(of: "Core", in: rendered[2]))
        #expect(branch == leaf, "siblings share a column: \(rendered)")
    }

    @Test("each level steps in by one disclosure indent")
    func depthStepsByOneIndent() throws {
        let (tui, context) = harness()
        let view = outline()
        frame(view, tui: tui, context: context)
        let focus = try #require(context.environment.focusManager)
        // Open "Sources", then Tab onto "TUIkit" and open that too.
        _ = focus.dispatchKeyEvent(KeyEvent(key: .enter))
        frame(view, tui: tui, context: context)
        _ = focus.dispatchKeyEvent(KeyEvent(key: .tab))
        frame(view, tui: tui, context: context)
        _ = focus.dispatchKeyEvent(KeyEvent(key: .enter))
        let rendered = lines(frame(view, tui: tui, context: context))

        #expect(rendered.count == 5, "Sources / TUIkit / Views / Core / README: \(rendered)")
        let root = try #require(column(of: "Sources", in: rendered[0]))
        let child = try #require(column(of: "TUIkit", in: rendered[1]))
        let grandchild = try #require(column(of: "Views", in: rendered[2]))
        #expect(child - root == DisclosureMetrics.contentIndent, "one step: \(rendered)")
        #expect(grandchild - child == DisclosureMetrics.contentIndent, "two steps: \(rendered)")
    }

    // MARK: - Branch vs leaf

    @Test("a leaf gets no triangle; an EMPTY branch still does")
    func emptyChildrenIsStillABranch() {
        let (tui, context) = harness()
        let rendered = lines(
            frame(
                VStack(alignment: .leading, spacing: 0) {
                    OutlineGroup(
                        [
                            Node(id: "empty", children: []),
                            Node(id: "leaf", children: nil),
                        ], children: \.children
                    ) { Text(verbatim: $0.id) }
                }, tui: tui, context: context))
        #expect(
            rendered[0].contains(TerminalSymbols.disclosureCollapsed),
            "an empty-but-present children list is a group: \(rendered)")
        #expect(
            rendered[1].contains(TerminalSymbols.disclosureCollapsed) == false,
            "a nil children list is a leaf: \(rendered)")
    }

    @Test("the root form shows exactly that element's tree")
    func rootFormWorks() {
        let (tui, context) = harness()
        let rendered = lines(
            frame(
                VStack(alignment: .leading, spacing: 0) {
                    OutlineGroup(tree[0], children: \.children) { Text(verbatim: $0.id) }
                }, tui: tui, context: context))
        // One row, the root itself, closed. (It leads with the focus indicator:
        // it is the only focusable thing on screen, so focus lands on it.)
        #expect(
            rendered.count == 1
                && rendered[0].hasSuffix("\(TerminalSymbols.disclosureCollapsed) Sources"),
            "\(rendered)")
    }

    @Test("an explicit id key path keys the rows")
    func explicitIDForm() {
        let (tui, context) = harness()
        struct Plain {
            let name: String
            var kids: [Self]?
        }
        let data = [Plain(name: "a", kids: [Plain(name: "b", kids: nil)])]
        let rendered = lines(
            frame(
                VStack(alignment: .leading, spacing: 0) {
                    OutlineGroup(data, id: \.name, children: \.kids) { Text(verbatim: $0.name) }
                }, tui: tui, context: context))
        #expect(rendered.count == 1 && rendered[0].contains("a"), "\(rendered)")
    }

    // MARK: - Where a click lands

    /// Clicks `(x, 0)` on a fresh outline and answers whether the first branch
    /// opened. Row 0 is "Sources" at depth 0, so its triangle is at column 2,
    /// with the focus gutter at 0–1 and the blank after it at 3.
    private func clickOpensFirstBranch(atColumn x: Int) -> Bool {
        let (tui, context) = harness()
        let view = outline()
        frame(view, tui: tui, context: context)
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: x, y: 0))
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: x, y: 0))
        return lines(frame(view, tui: tui, context: context)).contains { $0.contains("TUIkit") }
    }

    /// The triangle discloses; the label does not. An outline row's text has to
    /// stay free for whatever contains the outline to claim — a list's
    /// selection — which is the whole reason this is narrower than
    /// ``DisclosureGroup``'s whole-row target.
    @Test("clicking the triangle opens the branch; clicking the label does not")
    func onlyTheTriangleToggles() {
        #expect(clickOpensFirstBranch(atColumn: 2), "the triangle itself")
        #expect(clickOpensFirstBranch(atColumn: 6) == false, "a click on \"Sources\" is not a toggle")
    }

    /// One cell is a mean target with a mouse, so the button is deliberately
    /// wider than its glyph.
    @Test("the blank cell either side of the triangle counts as the triangle")
    func theTargetIsWiderThanTheGlyph() {
        #expect(clickOpensFirstBranch(atColumn: 1), "the cell before it")
        #expect(clickOpensFirstBranch(atColumn: 3), "the cell after it")
    }

    // MARK: - Independence

    /// Two branches, one open: the expansion is a set keyed by node id, so
    /// opening one must not open its sibling.
    @Test("opening one branch leaves its siblings closed")
    func siblingBranchesAreIndependent() throws {
        let (tui, context) = harness()
        let both = [
            Node(id: "first", children: [Node(id: "alpha", children: nil)]),
            Node(id: "second", children: [Node(id: "beta", children: nil)]),
        ]
        let view = VStack(alignment: .leading, spacing: 0) {
            OutlineGroup(both, children: \.children) { Text(verbatim: $0.id) }
        }
        frame(view, tui: tui, context: context)
        let focus = try #require(context.environment.focusManager)
        _ = focus.dispatchKeyEvent(KeyEvent(key: .enter))
        let rendered = lines(frame(view, tui: tui, context: context))
        #expect(rendered.contains { $0.contains("alpha") }, "the first opened: \(rendered)")
        #expect(rendered.contains { $0.contains("beta") } == false, "the second did not")
    }

    // MARK: - Inside a List

    /// The point of `List(_:children:)`: the list's rows are the NODES. If the
    /// outline arrived as one child, the list would have exactly one row — the
    /// whole tree — and its cursor, its selection binding and its scrolling
    /// would all address the tree rather than anything in it.
    @Test("a hierarchical List makes each visible node one of its own rows")
    func listRowsAreNodes() throws {
        let (tui, context) = harness(width: 40, height: 20)
        let selection = Selection()
        let view = List(tree, children: \.children, selection: selection.binding) { node in
            Text(verbatim: node.id)
        }

        frame(view, tui: tui, context: context)
        let focus = try #require(context.environment.focusManager)
        // Down moves the list's own cursor, one row per node — which it can
        // only do if the nodes ARE the rows.
        _ = focus.dispatchKeyEvent(KeyEvent(key: .down))
        frame(view, tui: tui, context: context)
        _ = focus.dispatchKeyEvent(KeyEvent(key: .space))
        #expect(selection.value == "README", "the cursor reached the second ROOT, and selected it")
    }

    @Test("selection is by node id, and survives opening a branch")
    func selectionIsByNodeID() throws {
        let (tui, context) = harness(width: 40, height: 20)
        let selection = Selection()
        let view = List(tree, children: \.children, selection: selection.binding) { node in
            Text(verbatim: node.id)
        }

        frame(view, tui: tui, context: context)
        let focus = try #require(context.environment.focusManager)
        // No priming: the list's cursor is live on the first frame, because the
        // triangle is no longer a focus stop competing for it.
        _ = focus.dispatchKeyEvent(KeyEvent(key: .space))
        #expect(selection.value == "Sources", "the first node, by its own id")

        // Open it with the triangle; the rows below shift, the selection does
        // not. A `List` draws a border and insets its rows by one, so row 0 is
        // screen row 1 and its triangle sits two cells further right than it
        // does in a bare outline.
        let triangle = (x: 1 + 1 + BorderRenderer.focusIndicatorWidth, y: 1)
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: triangle.x, y: triangle.y))
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: triangle.x, y: triangle.y))
        let opened = lines(frame(view, tui: tui, context: context))
        #expect(opened.contains { $0.contains("TUIkit") }, "the branch opened: \(opened)")
        #expect(selection.value == "Sources", "and the selection stayed on the node it was on")
    }

    /// The rule the owner asked for, on the one focusable that has both a
    /// selection and an action: SPACE belongs to the selection, RETURN
    /// activates — and for a branch with no other action, activating it is
    /// disclosing it.
    @Test("Space selects the branch row; Return discloses it")
    func spaceSelectsReturnDiscloses() throws {
        let (tui, context) = harness(width: 40, height: 20)
        let selection = Selection()
        let view = List(tree, children: \.children, selection: selection.binding) { node in
            Text(verbatim: node.id)
        }
        frame(view, tui: tui, context: context)
        let focus = try #require(context.environment.focusManager)

        _ = focus.dispatchKeyEvent(KeyEvent(key: .space))
        #expect(selection.value == "Sources", "Space selected the focused branch")
        var rendered = lines(frame(view, tui: tui, context: context))
        #expect(
            rendered.contains { $0.contains("TUIkit") } == false,
            "…and did NOT disclose it: \(rendered)")

        _ = focus.dispatchKeyEvent(KeyEvent(key: .enter))
        rendered = lines(frame(view, tui: tui, context: context))
        #expect(rendered.contains { $0.contains("TUIkit") }, "Return disclosed it: \(rendered)")
        #expect(selection.value == "Sources", "…without disturbing the selection")
    }

    /// The tree's own keys, which is what keeps disclosure reachable when an
    /// app claims Return with its own `.onRowActivate`.
    @Test("Right expands and Left collapses the focused branch")
    func arrowsDiscloseTheBranch() throws {
        let (tui, context) = harness(width: 40, height: 20)
        let view = List(tree, children: \.children) { node in Text(verbatim: node.id) }
        frame(view, tui: tui, context: context)
        let focus = try #require(context.environment.focusManager)

        #expect(focus.dispatchKeyEvent(KeyEvent(key: .right)), "Right opened the branch")
        var rendered = lines(frame(view, tui: tui, context: context))
        #expect(rendered.contains { $0.contains("TUIkit") }, "\(rendered)")

        #expect(focus.dispatchKeyEvent(KeyEvent(key: .left)), "Left closed it again")
        rendered = lines(frame(view, tui: tui, context: context))
        #expect(rendered.contains { $0.contains("TUIkit") } == false, "\(rendered)")
    }

    /// The Finder's gesture: ⌥→ opens a branch and everything under it, in one
    /// keystroke, however deep. "Views" is two levels down and no plain Right
    /// can reach it without a stop at "TUIkit" on the way.
    @Test("Option-Right opens the whole subtree, not one level of it")
    func optionRightOpensEverythingBeneath() throws {
        let (tui, context) = harness(width: 40, height: 20)
        let view = List(tree, children: \.children) { node in Text(verbatim: node.id) }
        frame(view, tui: tui, context: context)
        let focus = try #require(context.environment.focusManager)

        #expect(focus.dispatchKeyEvent(KeyEvent(key: .right, alt: true)))
        let rendered = lines(frame(view, tui: tui, context: context))
        #expect(rendered.contains { $0.contains("TUIkit") }, "the child branch: \(rendered)")
        #expect(rendered.contains { $0.contains("Views") }, "its own child too: \(rendered)")
        #expect(rendered.contains { $0.contains("Core") }, "and the leaf beside it: \(rendered)")
    }

    /// ⌥← takes the descendants with it, so the subtree is folded away rather
    /// than merely hidden: opening the branch again shows it closed, which is
    /// the whole difference between "collapse" and "collapse everything".
    @Test("Option-Left folds the subtree away, and it stays folded")
    func optionLeftFoldsEverythingBeneath() throws {
        let (tui, context) = harness(width: 40, height: 20)
        let view = List(tree, children: \.children) { node in Text(verbatim: node.id) }
        frame(view, tui: tui, context: context)
        let focus = try #require(context.environment.focusManager)

        // Open two levels the plain way, so the state under test was NOT built
        // by the gesture being tested: Right on "Sources", down to "TUIkit",
        // Right on that, back up to "Sources".
        for key in [Key.right, .down, .right, .up] {
            _ = focus.dispatchKeyEvent(KeyEvent(key: key))
            frame(view, tui: tui, context: context)
        }
        var rendered = lines(frame(view, tui: tui, context: context))
        #expect(rendered.contains { $0.contains("Views") }, "two levels open: \(rendered)")

        #expect(focus.dispatchKeyEvent(KeyEvent(key: .left, alt: true)), "it had things to close")
        rendered = lines(frame(view, tui: tui, context: context))
        #expect(rendered.contains { $0.contains("TUIkit") } == false, "\(rendered)")

        // One plain Right re-opens the branch alone. Had the collapse stopped
        // at "Sources", "TUIkit" would still be open underneath and "Views"
        // would come back with it.
        _ = focus.dispatchKeyEvent(KeyEvent(key: .right))
        rendered = lines(frame(view, tui: tui, context: context))
        #expect(rendered.contains { $0.contains("TUIkit") }, "the branch is back: \(rendered)")
        #expect(rendered.contains { $0.contains("Views") } == false, "still folded: \(rendered)")
    }

    /// The recursive form keeps the plain form's fall-through rules: a leaf has
    /// no subtree, and a subtree already fully open has nothing to do.
    @Test("Option-Right is consumed on a leaf and on an already-open subtree")
    func optionRightIsConsumedWithNothingToOpen() throws {
        let (tui, context) = harness(width: 40, height: 20)
        let view = List(tree, children: \.children) { node in Text(verbatim: node.id) }
        frame(view, tui: tui, context: context)
        let focus = try #require(context.environment.focusManager)

        _ = focus.dispatchKeyEvent(KeyEvent(key: .right, alt: true))
        frame(view, tui: tui, context: context)
        var row = try #require(focus.currentFocused)
        // Consumed, not fallen through: Right is the tree's key whether or not
        // it has anything to open — see `rightIsTheTreesKey`.
        #expect(
            row.handleKeyEvent(KeyEvent(key: .right, alt: true)),
            "the subtree is already open all the way down, and the key stays here")

        // "README" is a leaf: three rows down once "Sources" is open.
        for _ in 0..<4 {
            _ = focus.dispatchKeyEvent(KeyEvent(key: .down))
        }
        frame(view, tui: tui, context: context)
        row = try #require(focus.currentFocused)
        #expect(row.handleKeyEvent(KeyEvent(key: .right, alt: true)), "a leaf")
        // ⌥← has nothing to fold on a leaf, so it walks out of the subtree
        // exactly as a plain Left does — see `leftWalksOutOfTheSubtree`.
        #expect(row.handleKeyEvent(KeyEvent(key: .left, alt: true)), "a leaf: Left walks out")
    }

    /// A key a row cannot use must fall through, or the list swallows it from
    /// whatever is outside — a horizontal scroller, a split-view divider.
    ///
    /// Asked of the focused ELEMENT rather than of `dispatchKeyEvent`, because
    /// that is where the fall-through happens: a Left or Right the focused
    /// element declines is claimed one level up by the focus manager, which
    /// treats the pair as previous/next within the section and always reports
    /// it handled. What matters here is that the row doesn't take it first.
    /// Right belongs to the TREE, whether or not there is anything to open.
    ///
    /// It used to fall through when nothing opened — on a leaf, and on a branch
    /// already open — which handed the key to the focus system and moved the
    /// cursor sideways OUT of the outline. Pressing Right on an open folder to
    /// see what happens should not land you in the control beside the list.
    ///
    /// Left keeps its own ladder (see `leftWalksOutOfTheSubtree`): it collapses,
    /// then walks out of the subtree, and only leaves the list from the top row.
    @Test("Right is consumed inside a tree even when nothing opens")
    func rightIsTheTreesKey() throws {
        let (tui, context) = harness(width: 40, height: 20)
        let view = List(tree, children: \.children) { node in Text(verbatim: node.id) }
        frame(view, tui: tui, context: context)
        let focus = try #require(context.environment.focusManager)

        // The focused row is a CLOSED branch: Left has nothing to close.
        var row = try #require(focus.currentFocused)
        #expect(
            row.handleKeyEvent(KeyEvent(key: .left)) == false,
            "Left on an already-closed branch is not consumed")

        // Right opens it, and a second Right — nothing left to open — is
        // consumed rather than escaping the list.
        #expect(row.handleKeyEvent(KeyEvent(key: .right)), "Right opens the branch")
        frame(view, tui: tui, context: context)
        row = try #require(focus.currentFocused)
        #expect(
            row.handleKeyEvent(KeyEvent(key: .right)),
            "Right on an already-open branch stays in the tree")

        // …and on a leaf, likewise: consumed, and the tree does not move.
        _ = focus.dispatchKeyEvent(KeyEvent(key: .end))
        frame(view, tui: tui, context: context)
        row = try #require(focus.currentFocused)
        let before = lines(frame(view, tui: tui, context: context))
        #expect(row.handleKeyEvent(KeyEvent(key: .right)), "Right on a leaf is still the tree's")
        #expect(
            lines(frame(view, tui: tui, context: context)) == before,
            "and it opened nothing: \(before)")
    }

    /// Left's ladder, once there is nothing left to close: up to the parent,
    /// then to the top of the tree, and only then out of the list.
    ///
    /// It used to fall through the moment it met a row it could not close — on
    /// a leaf, or on a branch already shut — so a single Left inside a tree
    /// threw the focus at whatever view came next, which is not what any
    /// outline view does with the key.
    ///
    /// Where the cursor landed is read with Space through a selection binding,
    /// the same way `listRowsAreNodes` reads it: the row's id is the node's.
    @Test("Left walks out of the subtree before it leaves the list")
    func leftWalksOutOfTheSubtree() throws {
        let (tui, context) = harness(width: 40, height: 20)
        let selection = Selection()
        let view = List(tree, children: \.children, selection: selection.binding) { node in
            Text(verbatim: node.id)
        }
        frame(view, tui: tui, context: context)
        let focus = try #require(context.environment.focusManager)

        // Open "Sources" and step onto its child "TUIkit".
        _ = focus.dispatchKeyEvent(KeyEvent(key: .right))
        frame(view, tui: tui, context: context)
        _ = focus.dispatchKeyEvent(KeyEvent(key: .down))
        frame(view, tui: tui, context: context)
        _ = focus.dispatchKeyEvent(KeyEvent(key: .space))
        #expect(selection.value == "TUIkit", "the cursor is on the child")

        // 1 — a closed child branch: Left goes UP to "Sources", not out.
        var row = try #require(focus.currentFocused)
        #expect(row.handleKeyEvent(KeyEvent(key: .left)), "Left is consumed by the tree")
        frame(view, tui: tui, context: context)
        _ = focus.dispatchKeyEvent(KeyEvent(key: .space))
        #expect(selection.value == "Sources", "…and landed on the parent")

        // 2 — "Sources" is open, so this Left closes it (the first rung).
        row = try #require(focus.currentFocused)
        #expect(row.handleKeyEvent(KeyEvent(key: .left)), "Left closed the branch")
        let closed = lines(frame(view, tui: tui, context: context))
        #expect(closed.contains { $0.contains("TUIkit") } == false, "\(closed)")

        // 3 — a root row that is not the first: Left goes to the top.
        _ = focus.dispatchKeyEvent(KeyEvent(key: .down))
        frame(view, tui: tui, context: context)
        _ = focus.dispatchKeyEvent(KeyEvent(key: .space))
        #expect(selection.value == "README", "the cursor is on the second root")
        row = try #require(focus.currentFocused)
        #expect(row.handleKeyEvent(KeyEvent(key: .left)), "Left is still the tree's")
        frame(view, tui: tui, context: context)
        _ = focus.dispatchKeyEvent(KeyEvent(key: .space))
        #expect(selection.value == "Sources", "…and landed on the first row")

        // 4 — and only now does it leave.
        row = try #require(focus.currentFocused)
        #expect(
            row.handleKeyEvent(KeyEvent(key: .left)) == false,
            "Left on the first row falls through to the next view")
    }

    /// An app that gives its rows an action gets it — Return is theirs, and the
    /// arrows are what keep the tree reachable.
    @Test("onRowActivate wins Return; the arrows still disclose")
    func appActivationWinsReturn() throws {
        let (tui, context) = harness(width: 40, height: 20)
        var activated: [String] = []
        // With a selection binding the row ids ARE the node ids, so the
        // activation closure is handed the name rather than an index.
        let selection = Selection()
        let view = List(tree, children: \.children, selection: selection.binding) { node in
            Text(verbatim: node.id)
        }
        .onRowActivate { activated.append($0) }
        frame(view, tui: tui, context: context)
        let focus = try #require(context.environment.focusManager)

        _ = focus.dispatchKeyEvent(KeyEvent(key: .enter))
        var rendered = lines(frame(view, tui: tui, context: context))
        #expect(activated == ["Sources"], "the app's action ran")
        #expect(
            rendered.contains { $0.contains("TUIkit") } == false,
            "and Return did NOT also disclose: \(rendered)")

        _ = focus.dispatchKeyEvent(KeyEvent(key: .right))
        rendered = lines(frame(view, tui: tui, context: context))
        #expect(rendered.contains { $0.contains("TUIkit") }, "the arrows still do: \(rendered)")
    }

    /// A selection binding that a test can read back.
    @MainActor
    private final class Selection {
        var value: String?
        var binding: Binding<String?> {
            Binding(get: { self.value }, set: { self.value = $0 })
        }
    }

    @Test("a second Return closes the branch again")
    func returnClosesItAgain() throws {
        let (tui, context) = harness()
        let view = outline()
        frame(view, tui: tui, context: context)
        let focus = try #require(context.environment.focusManager)
        _ = focus.dispatchKeyEvent(KeyEvent(key: .enter))
        frame(view, tui: tui, context: context)
        _ = focus.dispatchKeyEvent(KeyEvent(key: .enter))
        let rendered = lines(frame(view, tui: tui, context: context))
        #expect(rendered.count == 2, "back to the two roots: \(rendered)")
    }
}
