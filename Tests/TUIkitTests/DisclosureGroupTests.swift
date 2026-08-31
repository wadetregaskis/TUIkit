//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DisclosureGroupTests.swift
//
//  `DisclosureGroup` — the header row, who owns the expansion, and the thing a
//  render-only test would miss: a collapsed group must not BUILD its content.
//
//  The interaction tests drive whole frames (begin/end render pass either
//  side) rather than calling `renderToBuffer` once, because expansion lives in
//  persistent `@State` and a toggle is only observable on the FOLLOWING frame
//  — which is exactly the shape of bug a single-render test cannot see.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("DisclosureGroup")
struct DisclosureGroupTests {

    /// A counter reachable from an escaping `@ViewBuilder` closure.
    @MainActor
    private final class BuildCounter {
        var calls = 0
    }

    /// A mutable flag reachable from an escaping closure, exposed as a real
    /// `Binding` — `.constant(…)` cannot observe a write, so a test using one
    /// passes against a group that never toggles anything.
    @MainActor
    private final class Flag {
        var value: Bool
        init(_ value: Bool) { self.value = value }
        var binding: Binding<Bool> {
            Binding(get: { self.value }, set: { self.value = $0 })
        }
    }

    private func harness(width: Int = 40, height: Int = 12) -> (TUIContext, RenderContext) {
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

    /// Renders one whole frame the way the run loop does, and arms the mouse
    /// dispatcher with the resulting regions.
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

    /// The frame's non-blank lines, ANSI stripped.
    private func lines(_ buffer: FrameBuffer) -> [String] {
        buffer.lines.map(\.stripped).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    // MARK: - The header row

    @Test("collapsed: a right triangle, the label, and nothing else")
    func collapsedShowsOnlyItsHeader() {
        let (tui, context) = harness()
        let rendered = lines(
            frame(
                DisclosureGroup("Advanced") { Text("Secret") },
                tui: tui, context: context))
        #expect(rendered.count == 1, "a collapsed group is one row: \(rendered)")
        let header = rendered.first
        #expect(header?.contains(TerminalSymbols.disclosureCollapsed) == true, "▶: \(rendered)")
        #expect(header?.contains("Advanced") == true, "the label is drawn: \(rendered)")
        #expect(
            rendered.contains { $0.contains("Secret") } == false,
            "collapsed content must not be drawn: \(rendered)")
    }

    @Test("expanded: a down triangle, and the content under the label")
    func expandedShowsItsContent() throws {
        let (tui, context) = harness()
        let rendered = lines(
            frame(
                DisclosureGroup("Advanced", isExpanded: .constant(true)) { Text("Secret") },
                tui: tui, context: context))
        #expect(rendered.count == 2, "header plus content: \(rendered)")
        #expect(rendered[0].contains(TerminalSymbols.disclosureExpanded), "▼: \(rendered)")
        #expect(rendered[1].contains("Secret"), "the content is drawn: \(rendered)")
    }

    /// The indent is what makes nested groups read as a tree, and it has to
    /// land the content under the LABEL — not under the focus gutter, and not
    /// under the triangle.
    @Test("the content starts in the same column as the label")
    func contentAlignsUnderTheLabel() throws {
        let (tui, context) = harness()
        let rendered = lines(
            frame(
                DisclosureGroup("Advanced", isExpanded: .constant(true)) { Text("Secret") },
                tui: tui, context: context))
        let labelColumn = try #require(column(of: "Advanced", in: rendered[0]))
        let contentColumn = try #require(column(of: "Secret", in: rendered[1]))
        #expect(
            contentColumn == labelColumn,
            "content at \(contentColumn), label at \(labelColumn): \(rendered)")
        #expect(
            contentColumn == DisclosureMetrics.contentIndent,
            "and that column is the published indent, \(DisclosureMetrics.contentIndent)")
    }

    private func column(of needle: String, in line: String) -> Int? {
        line.range(of: needle).map { line.distance(from: line.startIndex, to: $0.lowerBound) }
    }

    // MARK: - The content is not built while collapsed

    /// A collapsed section must cost nothing — not its views, not their
    /// measurement. SwiftUI's `content` is `@escaping () -> Content` precisely
    /// so a closed group need never call it, and storing the built view
    /// instead would quietly build every row of every collapsed section on
    /// every frame.
    @Test("a collapsed group never calls its content builder")
    func collapsedDoesNotBuildItsContent() {
        let (tui, context) = harness()
        let counter = BuildCounter()
        let view = DisclosureGroup("Advanced") {
            counter.calls += 1
            return Text("Secret")
        }
        frame(view, tui: tui, context: context)
        frame(view, tui: tui, context: context)
        #expect(counter.calls == 0, "built \(counter.calls) times while collapsed")
    }

    @Test("an expanded group does build it")
    func expandedBuildsItsContent() {
        let (tui, context) = harness()
        let counter = BuildCounter()
        let view = DisclosureGroup("Advanced", isExpanded: .constant(true)) {
            counter.calls += 1
            return Text("Secret")
        }
        frame(view, tui: tui, context: context)
        #expect(counter.calls > 0, "an expanded group must build its content")
    }

    // MARK: - Toggling

    /// Return on the focused header flips the group's OWN expansion, and the
    /// next frame shows it. This is the whole control, end to end: focus
    /// registration, the key handler, the `@State` write, the re-render.
    @Test("Return on the header expands a group that owns its own state")
    func returnTogglesSelfOwnedExpansion() throws {
        let (tui, context) = harness()
        let view = DisclosureGroup("Advanced") { Text("Secret") }

        frame(view, tui: tui, context: context)
        let focus = try #require(context.environment.focusManager)
        #expect(focus.dispatchKeyEvent(KeyEvent(key: .enter)), "the header takes Return")

        let expanded = lines(frame(view, tui: tui, context: context))
        #expect(
            expanded.contains { $0.contains("Secret") },
            "the next frame shows the content: \(expanded)")
        #expect(expanded[0].contains(TerminalSymbols.disclosureExpanded), "and turns the triangle")

        _ = focus.dispatchKeyEvent(KeyEvent(key: .enter))
        let collapsed = lines(frame(view, tui: tui, context: context))
        #expect(
            collapsed.contains { $0.contains("Secret") } == false,
            "a second Return closes it again: \(collapsed)")
    }

    /// The keys an outline view has everywhere else. `List(_:children:)` has
    /// answered Left and Right since it gained a tree; a `DisclosureGroup` that
    /// did not was the odd one out.
    @Test("Right opens the focused group and Left closes it")
    func arrowKeysDiscloseTheFocusedGroup() throws {
        let (tui, context) = harness()
        let open = Flag(false)
        let view = DisclosureGroup("Advanced", isExpanded: open.binding) { Text("Secret") }

        frame(view, tui: tui, context: context)
        let focus = try #require(context.environment.focusManager)

        #expect(focus.dispatchKeyEvent(KeyEvent(key: .right)), "Right is the header's")
        #expect(open.value, "and it opened the group")
        frame(view, tui: tui, context: context)

        #expect(focus.dispatchKeyEvent(KeyEvent(key: .left)), "Left is too")
        #expect(open.value == false, "and it closed it again")
    }

    /// They SET rather than toggle, which is the difference between an arrow
    /// key and Return: holding Right on an open group must not shut it. And
    /// once there is nothing left to open or close, the two keys part company —
    /// Right stays the disclosure's, Left goes back to being focus movement.
    @Test("Right on an open group holds the focus; Left on a closed one releases it")
    func arrowKeysSetRatherThanToggle() throws {
        let (tui, context) = harness(height: 16)
        let first = Flag(true)
        let view = VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup("First", isExpanded: first.binding) { Text("AlphaBody") }
            DisclosureGroup("Second") { Text("BetaBody") }
        }

        frame(view, tui: tui, context: context)
        let focus = try #require(context.environment.focusManager)
        let onFirst = focus.currentFocusedID

        _ = focus.dispatchKeyEvent(KeyEvent(key: .right))
        #expect(first.value, "an open group stays open under Right")
        #expect(
            focus.currentFocusedID == onFirst,
            "and keeps the focus, rather than landing in the control next to it")

        _ = focus.dispatchKeyEvent(KeyEvent(key: .left))
        #expect(first.value == false, "Left closed it")
        frame(view, tui: tui, context: context)

        // On to the second group, which is closed, so its Left has nothing to
        // do — and must therefore go back to being what Left is everywhere
        // else in the framework: a move to the previous control.
        _ = focus.dispatchKeyEvent(KeyEvent(key: .tab))
        let onSecond = focus.currentFocusedID
        #expect(onSecond != onFirst, "Tab reached the second group")
        _ = focus.dispatchKeyEvent(KeyEvent(key: .left))
        #expect(
            focus.currentFocusedID == onFirst,
            "Left on a closed group is the framework's again, and moves the focus")
    }

    @Test("Return writes through the caller's binding when one was supplied")
    func returnWritesTheSuppliedBinding() throws {
        let (tui, context) = harness()
        let open = Flag(false)
        let view = DisclosureGroup("Advanced", isExpanded: open.binding) { Text("Secret") }

        frame(view, tui: tui, context: context)
        let focus = try #require(context.environment.focusManager)
        _ = focus.dispatchKeyEvent(KeyEvent(key: .enter))
        #expect(open.value, "the group wrote the binding rather than a private copy")

        // And it READS it: expansion the app drove from outside must show.
        open.value = false
        #expect(
            lines(frame(view, tui: tui, context: context)).count == 1,
            "closing the binding closes the group")
    }

    // MARK: - What a closed section remembers

    /// Closing a section and opening it again used to reset everything inside
    /// it, because a collapsed group does not build its content and unbuilt
    /// state is collected at the end of the pass. A nested group you had opened
    /// was shut again; a field you had typed in was blank.
    @Test("a nested group keeps its expansion while its parent is closed")
    func nestedExpansionSurvivesTheParentClosing() throws {
        let (tui, context) = harness(height: 20)
        let outer = Flag(true)
        let view = DisclosureGroup("Outer", isExpanded: outer.binding) {
            DisclosureGroup("Inner") { Text("InnerBody") }
        }

        frame(view, tui: tui, context: context)
        let focus = try #require(context.environment.focusManager)
        // Focus starts on the outer header; Tab reaches the inner one.
        _ = focus.dispatchKeyEvent(KeyEvent(key: .tab))
        _ = focus.dispatchKeyEvent(KeyEvent(key: .right))
        let opened = lines(frame(view, tui: tui, context: context))
        #expect(opened.contains { $0.contains("InnerBody") }, "the inner opened: \(opened)")

        // Close the OUTER group, which takes the inner one off screen along
        // with everything it was remembering, then open it again.
        outer.value = false
        frame(view, tui: tui, context: context)
        outer.value = true
        let reopened = lines(frame(view, tui: tui, context: context))
        #expect(
            reopened.contains { $0.contains("InnerBody") },
            "the inner group is as it was left, not as it started: \(reopened)")
    }

    /// The other half: the claim is renewed per pass by the group's own render,
    /// so a group that leaves the tree entirely takes its contents' state with
    /// it. Nothing is kept alive by a section that is no longer there.
    @Test("a group that leaves the tree does not keep its contents' state")
    func stateGoesWhenTheGroupItselfGoes() throws {
        let (tui, context) = harness(height: 20)
        let present = Flag(true)
        @MainActor func view() -> some View {
            VStack(alignment: .leading, spacing: 0) {
                if present.value {
                    DisclosureGroup("Outer", isExpanded: .constant(true)) {
                        DisclosureGroup("Inner") { Text("InnerBody") }
                    }
                }
            }
        }

        frame(view(), tui: tui, context: context)
        let focus = try #require(context.environment.focusManager)
        _ = focus.dispatchKeyEvent(KeyEvent(key: .tab))
        _ = focus.dispatchKeyEvent(KeyEvent(key: .right))
        #expect(lines(frame(view(), tui: tui, context: context)).contains {
            $0.contains("InnerBody")
        })

        present.value = false
        frame(view(), tui: tui, context: context)
        present.value = true
        let rebuilt = lines(frame(view(), tui: tui, context: context))
        #expect(
            rebuilt.contains { $0.contains("InnerBody") } == false,
            "a group rebuilt from nothing starts closed: \(rebuilt)")
    }

    @Test("clicking the header row toggles it")
    func clickTogglesIt() {
        let (tui, context) = harness()
        let open = Flag(false)
        let view = DisclosureGroup("Advanced", isExpanded: open.binding) { Text("Secret") }

        frame(view, tui: tui, context: context)
        // Anywhere on the row — the triangle and the label are one control.
        let column = DisclosureMetrics.contentIndent
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: column, y: 0))
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: column, y: 0))
        #expect(open.value, "a click on the label toggled the group")
    }

    /// Two groups in one stack must not share a slot — the classic `@State`
    /// identity bug, which renders as "opening one opens both".
    @Test("sibling groups expand independently")
    func siblingsAreIndependent() throws {
        let (tui, context) = harness(height: 16)
        let view = VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup("First") { Text("AlphaBody") }
            DisclosureGroup("Second") { Text("BetaBody") }
        }

        frame(view, tui: tui, context: context)
        let focus = try #require(context.environment.focusManager)
        // Focus starts on the first header; open it and leave the second shut.
        _ = focus.dispatchKeyEvent(KeyEvent(key: .enter))
        let rendered = lines(frame(view, tui: tui, context: context))
        #expect(rendered.contains { $0.contains("AlphaBody") }, "the first opened: \(rendered)")
        #expect(
            rendered.contains { $0.contains("BetaBody") } == false,
            "the second stayed shut: \(rendered)")
    }

    // MARK: - Cascading modifiers

    /// The parity rule for every public control: `.disabled(_:)` on the group
    /// must reach the header, and a disabled control does not take focus.
    @Test("a disabled group registers no focus stop")
    func disabledTakesNoFocus() throws {
        let (tui, context) = harness()
        frame(
            DisclosureGroup("Advanced") { Text("Secret") }.disabled(true),
            tui: tui, context: context)
        let focus = try #require(context.environment.focusManager)
        #expect(
            focus.dispatchKeyEvent(KeyEvent(key: .enter)) == false,
            "nothing focusable, so nothing consumes Return")
    }

    /// The one alignment rule — content starts under its own group's label —
    /// applied twice. A nested group is content, so its whole row steps right
    /// by one indent; the leaf inside it then lands under THAT group's label,
    /// which is what draws the tree.
    ///
    ///     ▼ Outer
    ///         ▼ Inner
    ///           Leaf
    @Test("the alignment rule holds at depth, so nesting draws a tree")
    func nestingStepsTheIndent() throws {
        let (tui, context) = harness(width: 50, height: 16)
        let rendered = lines(
            frame(
                DisclosureGroup("Outer", isExpanded: .constant(true)) {
                    DisclosureGroup("Inner", isExpanded: .constant(true)) {
                        Text("Leaf")
                    }
                },
                tui: tui, context: context))
        let glyph = TerminalSymbols.disclosureExpanded
        let outerGlyph = try #require(column(of: glyph, in: rendered[0]))
        let innerGlyph = try #require(column(of: glyph, in: rendered[1]))
        let inner = try #require(column(of: "Inner", in: rendered[1]))
        let leaf = try #require(column(of: "Leaf", in: rendered[2]))
        #expect(
            innerGlyph - outerGlyph == DisclosureMetrics.contentIndent,
            "the nested group's whole row steps in one indent: \(rendered)")
        #expect(leaf == inner, "and its leaf sits under ITS label: \(rendered)")
    }
}
