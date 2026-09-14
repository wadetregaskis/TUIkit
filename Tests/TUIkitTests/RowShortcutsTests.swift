//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RowShortcutsTests.swift
//
//  The customisable key bindings of a `List` / `Table`: what a `ShortcutSet`
//  says, how the table resolves it, and that a rebound list actually answers
//  the new key and stops answering the old one.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Row shortcuts")
struct RowShortcutsTests {

    private let ctrlV = KeyboardShortcut("v", modifiers: .control)
    private let ctrlE = KeyboardShortcut("e", modifiers: .control)
    private let ctrlA = KeyboardShortcut("a", modifiers: .control)

    // MARK: - The set

    @Test("The four things a set can say")
    func setVocabulary() {
        let defaults: Set<KeyboardShortcut> = [ctrlV]
        #expect(ShortcutSet.default.resolved(defaults: defaults) == [ctrlV])
        #expect(ShortcutSet.unbound.resolved(defaults: defaults).isEmpty)
        #expect(ShortcutSet.only(ctrlE).resolved(defaults: defaults) == [ctrlE])
        #expect(ShortcutSet.default.and(ctrlE).resolved(defaults: defaults) == [ctrlV, ctrlE])
    }

    /// The literal is ``ShortcutSet/only(_:)`` — so `[]` is "unbound", which is
    /// the spelling most people will reach for.
    @Test("An array literal replaces; an empty one unbinds")
    func arrayLiteral() {
        let defaults: Set<KeyboardShortcut> = [ctrlV]
        let replaced: ShortcutSet = [ctrlE]
        let empty: ShortcutSet = []
        #expect(replaced.resolved(defaults: defaults) == [ctrlE])
        #expect(empty.resolved(defaults: defaults).isEmpty)
        #expect(empty == .unbound)
    }

    // MARK: - Ordering

    /// Display order is a property of the shortcut, not of the order a call site
    /// listed them in — otherwise the help text reads differently depending on
    /// which app wrote the table.
    @Test("Shortcuts sort into one order regardless of how they were written")
    func ordering() {
        let table = RowShortcuts([.selectAll: .default.and(ctrlE)])
        let shortcuts = table.shortcuts(for: .selectAll)
        #expect(shortcuts == [ctrlA, ctrlE], "by key, then modifiers")
        #expect(
            RowShortcuts([.selectAll: .only(ctrlE, ctrlA)]).shortcuts(for: .selectAll)
                == [ctrlA, ctrlE],
            "the same order, written the other way round")
        #expect(KeyboardShortcut.defaultAction < ctrlA, "the semantic roles sort first")
    }

    /// Where only one chord fits, the framework's own is preferred: adding an
    /// alias must not silently rename the hint a user has learned.
    @Test("The one-chord hint prefers the framework's binding")
    func hintPrefersTheDefault() {
        let aliased = RowShortcuts([.selectAll: .default.and(KeyboardShortcut("b", modifiers: .control))])
        #expect(aliased.hint(for: .selectAll) == "^A")
        let replaced = RowShortcuts([.selectAll: [KeyboardShortcut("b", modifiers: .control)]])
        #expect(replaced.hint(for: .selectAll) == "^B", "…unless it is gone")
    }

    /// The arrow keys had no `KeyEquivalent` at all until the nudge needed one,
    /// so a chord on them could not be written, let alone fired. They print as
    /// their names — the private-use scalar behind `.upArrow` would otherwise
    /// reach the screen as a missing-glyph box.
    @Test("Non-printable keys are bindable, and print as names")
    func nonPrintableKeys() {
        let ctrlUp = KeyboardShortcut(.upArrow, modifiers: .control)
        #expect(ctrlUp.displayString == "^↑")
        #expect(KeyboardShortcut(.pageDown, modifiers: []).displayString == "PgDn")

        let table = RowShortcuts()
        let lookup = table.lookup(commandKey: .control)
        #expect(
            table.shortcuts(for: .moveRowUp) == [ctrlUp, KeyboardShortcut(.upArrow, modifiers: .option)],
            "two bindings: the one macOS eats, and the one it leaves alone")
        #expect(
            lookup.action(for: KeyEvent(key: .up, alt: true))?.action == .moveRowUp,
            "Option+↑ is the binding that survives Mission Control")
        #expect(
            lookup.action(for: KeyEvent(key: .up, alt: true, shift: true))?.accelerated == true,
            "and Shift on top of it is the coarse step, not a separate binding")
        #expect(lookup.action(for: KeyEvent(key: .up, ctrl: true))?.action == .moveRowUp)
        #expect(lookup.action(for: KeyEvent(key: .down, ctrl: true))?.action == .moveRowDown)
        #expect(lookup.action(for: KeyEvent(key: .up)) == nil, "a bare arrow still navigates")
    }

    /// Return and Escape keep their semantic roles when unmodified — the default
    /// button and the cancel button depend on it — and become ordinary key
    /// equivalents only when a modifier is held.
    @Test("Bare Return and Escape stay the semantic roles")
    func semanticRolesSurvive() {
        #expect(KeyboardShortcut.trigger(for: KeyEvent(key: .enter)) == .defaultAction)
        #expect(KeyboardShortcut.trigger(for: KeyEvent(key: .escape)) == .cancelAction)
        #expect(
            KeyboardShortcut.trigger(for: KeyEvent(key: .enter, ctrl: true))
                == .key(.return, .control),
            "…but a modified one is just a key")
    }

    // MARK: - Resolution

    @Test("An unmentioned action keeps its defaults")
    func unmentionedActionsKeepDefaults() {
        let table = RowShortcuts([.selectAll: [ctrlE]])
        #expect(table.shortcuts(for: .extendSelection) == [ctrlV])
    }

    @Test("The lookup maps a key event to its action")
    func lookupMatchesEvents() {
        let lookup = RowShortcuts.default.lookup(commandKey: .control)
        #expect(lookup.action(for: KeyEvent(key: .character("v"), ctrl: true))?.action == .extendSelection)
        #expect(lookup.action(for: KeyEvent(key: .character("a"), ctrl: true))?.action == .selectAll)
        #expect(
            lookup.action(for: KeyEvent(key: .character("v"))) == nil,
            "the BARE key is free — it belongs to the app, and to row type-ahead")
    }

    /// A shortcut written the SwiftUI way — `KeyboardShortcut("g")`, i.e. ⌘G —
    /// goes through the same ⌘ stand-in as a `Button`'s, so it is Ctrl-G here.
    @Test("A command-key shortcut resolves through the command-key binding")
    func commandKeyIsResolved() {
        let table = RowShortcuts([.selectAll: [KeyboardShortcut("g")]])
        #expect(table.shortcuts(for: .selectAll, commandKey: .control)
            == [KeyboardShortcut("g", modifiers: .control)])
        let lookup = table.lookup(commandKey: .control)
        #expect(lookup.action(for: KeyEvent(key: .character("g"), ctrl: true))?.action == .selectAll)
        #expect(
            table.lookup(commandKey: .unavailable)
                .action(for: KeyEvent(key: .character("g"), ctrl: true)) == nil,
            "an app that says ⌘ is unavailable gets no binding, not a silent Control one")
    }

    /// An override beats a default on the same chord — an app that binds Ctrl-A
    /// to something else means it, and the default yields rather than the two
    /// fighting over which fires.
    @Test("An override takes a chord away from a default binding")
    func overrideBeatsDefault() {
        let table = RowShortcuts([.extendSelection: [ctrlA]])
        var reports: [String] = []
        let lookup = table.lookup(commandKey: .control, onClash: { reports.append($0) })
        #expect(lookup.action(for: KeyEvent(key: .character("a"), ctrl: true))?.action == .extendSelection)
        #expect(reports.isEmpty, "taking a default's chord is not a clash: \(reports)")
    }

    /// Only one action can answer a key, so two overrides on one chord are the
    /// app's mistake. What a release build does with it: the action `RowAction`
    /// declares first keeps the chord, and the clash is reported once per build
    /// of the table. The pairs are written with the later-declared action first,
    /// so declaration order, not the literal's order, is what decides.
    @Test(
        "Two overrides on one chord: the action RowAction declares first keeps it, and the clash is reported",
        arguments: [
            (RowAction.extendSelection, RowAction.selectAll),
            (RowAction.reverseSortOrder, RowAction.pickUpRow),
        ])
    func clashingOverrides(later: RowAction, earlier: RowAction) {
        let ctrlX = KeyboardShortcut("x", modifiers: .control)
        let table = RowShortcuts([later: [ctrlE, ctrlX], earlier: [ctrlE]])
        var reports: [String] = []
        let lookup = table.lookup(commandKey: .control, onClash: { reports.append($0) })

        #expect(lookup.action(for: KeyEvent(key: .character("e"), ctrl: true))?.action == earlier)
        #expect(
            lookup.action(for: KeyEvent(key: .character("x"), ctrl: true))?.action == later,
            "the losing action keeps the chords nobody else claimed")
        #expect(
            reports == ["rowShortcuts binds ^E to both \(earlier) and \(later); \(earlier), which RowAction declares first, keeps it"])
    }

    /// A shortcut written the SwiftUI way, `KeyboardShortcut("e")`, is ⌘E, and ⌘E
    /// is Ctrl-E where ⌘ stands for Control. So it clashes with an override
    /// written as Ctrl-E exactly as a second Ctrl-E would, in either order.
    @Test(
        "Two spellings of one chord clash like one spelling",
        arguments: [
            (KeyboardShortcut("e"), KeyboardShortcut("e", modifiers: .control)),
            (KeyboardShortcut("e", modifiers: .control), KeyboardShortcut("e")),
        ])
    func clashingSpellings(earlierSpelling: KeyboardShortcut, laterSpelling: KeyboardShortcut) {
        let table = RowShortcuts([.extendSelection: [laterSpelling], .selectAll: [earlierSpelling]])
        var reports: [String] = []
        let lookup = table.lookup(commandKey: .control, onClash: { reports.append($0) })

        #expect(lookup.action(for: KeyEvent(key: .character("e"), ctrl: true))?.action == .selectAll)
        #expect(
            reports == ["rowShortcuts binds ^E to both selectAll and extendSelection; selectAll, which RowAction declares first, keeps it"])
    }

    #if DEBUG
        /// The default report is a soft trap, so a debug build stops. In a child
        /// process, because a stop in this one would end the test run.
        @Test("Two overrides on one chord stop a debug build")
        func clashStopsADebugBuild() async {
            await #expect(processExitsWith: .failure) {
                let ctrlE = KeyboardShortcut("e", modifiers: .control)
                _ = RowShortcuts([.selectAll: [ctrlE], .extendSelection: [ctrlE]])
                    .lookup(commandKey: .control)
            }
        }
    #endif

    // MARK: - The table is memoised, and the memo notices

    /// The chord table is built once per handler now, not once per pass — it is
    /// a fresh `Dictionary` and some fifty hashes for a value that is identical
    /// for every list on the page and, in most apps, never changes.
    ///
    /// So the memo has to notice when it DOES change. A list whose
    /// `.rowShortcuts` are swapped between frames must answer the new chord on
    /// the next frame, not the one it captured first.
    @Test("Rebinding between frames rebuilds the captured table")
    func rebindingInvalidatesTheMemo() {
        let tui = TUIContext()
        var env = EnvironmentValues()
        env.focusManager = FocusManager()
        env.applyRuntimeServices(from: tui)
        var selection: Set<String> = []
        let view = List(
            selection: Binding(get: { selection }, set: { selection = $0 })
        ) {
            ForEach(["a", "b", "c"], id: \.self) { Text($0) }
        }

        func frame(_ shortcuts: RowShortcuts) {
            env.rowShortcuts = shortcuts
            let context = RenderContext(
                availableWidth: 20, availableHeight: 8, environment: env, tuiContext: tui)
            tui.stateStorage.beginRenderPass()
            env.focusManager?.beginRenderPass()
            _ = renderToBuffer(view, context: context)
            env.focusManager?.endRenderPass()
            tui.stateStorage.endRenderPass()
        }

        // Frame 1 binds extend-selection to Ctrl-E, frame 2 moves it to Ctrl-X.
        frame(RowShortcuts([.extendSelection: [ctrlE]]))
        frame(RowShortcuts([.extendSelection: [KeyboardShortcut("x", modifiers: .control)]]))

        let focus = env.focusManager
        // The OLD chord must no longer be answered…
        #expect(
            focus?.dispatchKeyEvent(KeyEvent(key: .character("e"), ctrl: true)) != true,
            "the memo kept the first frame's table")
        // …and the new one must be.
        #expect(focus?.dispatchKeyEvent(KeyEvent(key: .character("x"), ctrl: true)) == true)
    }

    // MARK: - End to end

    /// The list itself has to answer the rebound key — the table is captured at
    /// render, so a binding that never reaches the handler is invisible in every
    /// unit test of the table alone.
    @Test("A rebound list answers the new key and not the old one")
    func listHonoursTheTable() {
        let tui = TUIContext()
        var env = EnvironmentValues()
        env.focusManager = FocusManager()
        env.applyRuntimeServices(from: tui)
        env.rowShortcuts = RowShortcuts([.extendSelection: [ctrlE]])
        let context = RenderContext(
            availableWidth: 20, availableHeight: 8, environment: env, tuiContext: tui)

        var selection: Set<String> = []
        let view = List(
            selection: Binding(get: { selection }, set: { selection = $0 })
        ) {
            ForEach(["a", "b", "c"], id: \.self) { Text($0) }
        }
        env.focusManager?.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        env.focusManager?.endRenderPass()

        // Through the focus manager, as a real key press arrives — the table is
        // captured during the render, so a binding that never reaches the
        // handler would still pass a test that drove the handler directly.
        let focus = env.focusManager
        #expect(focus?.dispatchKeyEvent(KeyEvent(key: .character("v"), ctrl: true)) != true)
        #expect(selection.isEmpty, "Ctrl-V was rebound away, so it selected nothing")
        #expect(focus?.dispatchKeyEvent(KeyEvent(key: .character("e"), ctrl: true)) == true)
        #expect(selection == ["a"], "…to Ctrl-E, which entered extend mode on the cursor row")
    }
}
