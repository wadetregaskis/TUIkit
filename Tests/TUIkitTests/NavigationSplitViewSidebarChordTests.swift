//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationSplitViewSidebarChordTests.swift
//
//  SwiftUI's two sidebar chords, View ▸ Show Sidebar ⌃⌘S and the hidden Toggle
//  Sidebar ⌥⌘S, resolved through `commandKey` (⌃S and ⌥⌃S under the default
//  `.control`). They toggle the sidebar only, as macOS does, whatever holds the
//  focus: an app shortcut, an `onKeyPress` handler or a focused control that uses
//  the key takes it first; with several split views the focused one, or the one
//  holding the focus, wins, and otherwise the first in render order.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitStyling

@MainActor
@Suite("⌃S and ⌥⌃S toggle a split view's sidebar")
struct NavigationSplitViewSidebarChordTests {

    /// Renders views through the run loop's per-frame passes and hands keys to a
    /// real `InputHandler` over the same services.
    @MainActor
    private final class Harness {
        let tui = TUIContext()
        let focusManager = FocusManager()
        let statusBar = StatusBarState()
        let context: RenderContext
        let handler: InputHandler

        init(width: Int = 120, height: Int = 12) {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.applyRuntimeServices(from: tui)
            statusBar.focusManager = focusManager
            environment.statusBar = statusBar
            context = RenderContext(
                availableWidth: width, availableHeight: height, environment: environment, tuiContext: tui)
            handler = InputHandler(
                statusBar: statusBar,
                keyEventDispatcher: tui.keyEventDispatcher,
                focusManager: focusManager,
                paletteManager: ThemeManager(items: PaletteRegistry.all, renderTrigger: {}),
                appearanceManager: ThemeManager(items: AppearanceRegistry.all, renderTrigger: {}),
                keyboardShortcuts: tui.keyboardShortcuts,
                dragAndDropSession: tui.dragAndDropSession,
                onQuit: {}, onSuspend: {})
        }

        @discardableResult
        func frame(_ view: some View) -> FrameBuffer {
            tui.mouseEventDispatcher.beginRenderPass()
            tui.keyEventDispatcher.clearHandlers()
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            tui.keyboardShortcuts.beginRenderPass()
            tui.preferences.beginRenderPass()
            statusBar.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tui.stateStorage.endRenderPass()
            return buffer
        }

        @discardableResult
        func press(_ event: KeyEvent) -> Bool {
            handler.handle(event)
        }
    }

    private final class Box {
        var visibility: NavigationSplitViewVisibility
        init(_ visibility: NavigationSplitViewVisibility = .all) { self.visibility = visibility }
        var binding: Binding<NavigationSplitViewVisibility> {
            Binding(get: { self.visibility }, set: { self.visibility = $0 })
        }
    }

    private final class Counter { var value = 0 }

    private static let controlS = KeyEvent(key: .character("s"), ctrl: true)
    private static let optionControlS = KeyEvent(key: .character("s"), ctrl: true, alt: true)

    /// A two-column split whose columns hold toggles `<name>-side` and
    /// `<name>-detail`.
    private func split(_ name: String, _ box: Box) -> some View {
        NavigationSplitView(columnVisibility: box.binding) {
            Toggle(name, isOn: .constant(false)).focusID("\(name)-side")
        } detail: {
            Toggle(name, isOn: .constant(false)).focusID("\(name)-detail")
        }
    }

    private func threeColumns(_ box: Box) -> some View {
        NavigationSplitView(columnVisibility: box.binding) {
            Text("S")
        } content: {
            Text("C")
        } detail: {
            Text("D")
        }
    }

    /// What the parser makes of `bytes`, read in one go.
    private func parse(_ bytes: [UInt8]) -> KeyEvent? {
        final class Pending { var bytes: [UInt8] = [] }
        let pending = Pending()
        pending.bytes = bytes
        let terminal = Terminal()
        terminal.readSource = { buffer in
            let count = min(pending.bytes.count, buffer.count)
            for index in 0..<count { buffer[index] = pending.bytes[index] }
            pending.bytes.removeFirst(count)
            return count
        }
        guard case .key(let event) = terminal.readEvent() else { return nil }
        return event
    }

    // MARK: The keys

    /// Raw mode clears IXON (Terminal.swift `enableRawMode`), so ⌃S is not eaten
    /// as XOFF by the tty driver and arrives as the byte 0x13.
    @Test("The byte 0x13 is ⌃S, and it hides the sidebar")
    func controlSByte() {
        let event = parse([0x13])
        #expect(event == Self.controlS)
        let harness = Harness()
        let box = Box()
        harness.frame(split("a", box))
        #expect(harness.press(event ?? Self.controlS))
        #expect(box.visibility == .detailOnly)
    }

    @Test("ESC 0x13 is ⌥⌃S, and it hides the sidebar too")
    func optionControlSBytes() {
        let event = parse([0x1B, 0x13])
        #expect(event == Self.optionControlS)
        let harness = Harness()
        let box = Box()
        harness.frame(split("a", box))
        #expect(harness.press(event ?? Self.optionControlS))
        #expect(box.visibility == .detailOnly)
    }

    @Test(
        "⌃S toggles the sidebar only",
        arguments: [
            (false, NavigationSplitViewVisibility.all, NavigationSplitViewVisibility.detailOnly),
            (false, .automatic, .detailOnly),
            (false, .doubleColumn, .detailOnly),
            (false, .detailOnly, .all),
            (true, .all, .doubleColumn),
            (true, .automatic, .doubleColumn),
            (true, .doubleColumn, .all),
            (true, .detailOnly, .all),
        ])
    func togglesTheSidebar(three: Bool, from: NavigationSplitViewVisibility, to: NavigationSplitViewVisibility) {
        let harness = Harness()
        let box = Box(from)
        if three { harness.frame(threeColumns(box)) } else { harness.frame(split("a", box)) }
        #expect(harness.press(Self.controlS))
        #expect(box.visibility == to)
    }

    @Test("Without a binding the split view keeps the visibility itself")
    func withoutABinding() {
        let harness = Harness()
        let view = NavigationSplitView { Text("SIDEBAR") } detail: { Text("DETAIL") }
        harness.frame(view)
        harness.press(Self.controlS)
        #expect(!harness.frame(view).lines.contains { $0.stripped.contains("SIDEBAR") })
        harness.press(Self.controlS)
        #expect(harness.frame(view).lines.contains { $0.stripped.contains("SIDEBAR") })
    }

    // MARK: What takes the key first

    @Test("An app's ⌘S (⌃S here) wins wherever its button renders, and ⌥⌃S still toggles")
    func appShortcutWins() {
        for placement in ["above", "inside", "below"] {
            let harness = Harness()
            let box = Box()
            let saves = Counter()
            let save = Button("Save") { saves.value += 1 }.keyboardShortcut("s")
            let view = VStack {
                if placement == "above" { save }
                NavigationSplitView(columnVisibility: box.binding) {
                    if placement == "inside" { save } else { Text("S") }
                } detail: {
                    Text("D")
                }
                if placement == "below" { save }
            }
            harness.frame(view)
            #expect(harness.press(Self.controlS))
            #expect(saves.value == 1, "\(placement)")
            #expect(box.visibility == .all, "\(placement)")
            harness.frame(view)
            #expect(harness.press(Self.optionControlS))
            #expect(box.visibility == .detailOnly, "\(placement)")
        }
    }

    @Test("An onKeyPress handler for ⌃S wins")
    func onKeyPressWins() {
        let harness = Harness()
        let box = Box()
        let seen = Counter()
        let view = split("a", box).onKeyPress { event in
            guard event == Self.controlS else { return false }
            seen.value += 1
            return true
        }
        harness.frame(view)
        #expect(harness.press(Self.controlS))
        #expect(seen.value == 1)
        #expect(box.visibility == .all)
    }

    private struct Row: Identifiable, Sendable {
        let id: Int
        let name: String
        let size: Int
    }

    @Test("A focused sortable Table sorts on ⌃S instead")
    func focusedSortableTableSorts() {
        let harness = Harness()
        let box = Box()
        final class Sort { var order = [KeyPathComparator(\Row.name)] }
        let sort = Sort()
        let rows = [Row(id: 1, name: "b", size: 2), Row(id: 2, name: "a", size: 1)]
        let view = NavigationSplitView(columnVisibility: box.binding) {
            Text("S")
        } detail: {
            Table(
                rows, selection: .constant(Int?.none),
                sortOrder: Binding(get: { sort.order }, set: { sort.order = $0 })
            ) {
                TableColumn("Name", value: \Row.name)
                TableColumn("Size", value: \Row.size) { "\($0.size)" }
            }
        }
        harness.frame(view)
        harness.focusManager.activateSection(
            id: harness.focusManager.section(withPrefix: "nav-split-detail")?.id ?? "")
        harness.frame(view)
        #expect(harness.press(Self.controlS))
        #expect(sort.order.first?.keyPath == \Row.size, "the table sorted")
        #expect(box.visibility == .all)
    }

    @Test("A focused TextField lets ⌃S through, so the chord works while typing")
    func textFieldLetsItThrough() {
        let harness = Harness()
        let box = Box()
        final class Draft { var text = "hi" }
        let draft = Draft()
        let view = NavigationSplitView(columnVisibility: box.binding) {
            Text("S")
        } detail: {
            TextField("Draft", text: Binding(get: { draft.text }, set: { draft.text = $0 }))
        }
        harness.frame(view)
        harness.focusManager.activateSection(
            id: harness.focusManager.section(withPrefix: "nav-split-detail")?.id ?? "")
        harness.frame(view)
        #expect(harness.focusManager.hasTextInputFocus, "sanity")
        #expect(harness.press(Self.controlS))
        #expect(box.visibility == .detailOnly)
        #expect(draft.text == "hi")
    }

    // MARK: commandKey

    @Test("commandKey(.unavailable) turns both chords off")
    func unavailableCommandKey() {
        let harness = Harness()
        let box = Box()
        let view = split("a", box).commandKey(.unavailable)
        harness.frame(view)
        harness.press(Self.controlS)
        harness.press(Self.optionControlS)
        #expect(box.visibility == .all)
    }

    @Test("commandKey(.option) makes them ⌥⌃S and ⌥S, and leaves ⌃S alone")
    func optionCommandKey() {
        for (event, toggles) in [
            (Self.controlS, false),
            (Self.optionControlS, true),
            (KeyEvent(key: .character("s"), alt: true), true),
        ] {
            let harness = Harness()
            let box = Box()
            harness.frame(split("a", box).commandKey(.option))
            harness.press(event)
            #expect((box.visibility == .detailOnly) == toggles, "\(event)")
        }
    }

    // MARK: Which split

    @Test("With the focus outside the only split, it still responds")
    func focusOutsideOneSplit() {
        let harness = Harness()
        let box = Box()
        let view = VStack {
            Toggle("above", isOn: .constant(false)).focusID("above")
            split("a", box)
        }
        harness.frame(view)
        harness.focusManager.focus(id: "above")
        harness.frame(view)
        #expect(harness.press(Self.controlS))
        #expect(box.visibility == .detailOnly)
        #expect(harness.focusManager.currentFocusedID == "above")
    }

    @Test("Side by side, the split holding the focus toggles; with the focus elsewhere, the first")
    func sideBySide() {
        for (focus, expectA, expectB) in [
            ("b-detail", NavigationSplitViewVisibility.all, NavigationSplitViewVisibility.detailOnly),
            ("a-side", .detailOnly, .all),
            ("above", .detailOnly, .all),
        ] {
            let harness = Harness()
            let a = Box()
            let b = Box()
            let view = VStack {
                Toggle("above", isOn: .constant(false)).focusID("above")
                HStack(spacing: 0) {
                    split("a", a)
                    split("b", b)
                }
            }
            harness.frame(view)
            harness.focusManager.focus(id: focus)
            harness.frame(view)
            harness.press(Self.controlS)
            #expect(a.visibility == expectA, "focus on \(focus)")
            #expect(b.visibility == expectB, "focus on \(focus)")
        }
    }

    @Test("Nested, the innermost split holding the focus toggles; with the focus outside both, the outer")
    func nested() {
        for (focus, expectOuter, expectInner) in [
            ("inner-detail", NavigationSplitViewVisibility.all, NavigationSplitViewVisibility.detailOnly),
            ("outer-side", .detailOnly, .all),
            ("above", .detailOnly, .all),
        ] {
            let harness = Harness()
            let outer = Box()
            let inner = Box()
            let view = VStack {
                Toggle("above", isOn: .constant(false)).focusID("above")
                NavigationSplitView(columnVisibility: outer.binding) {
                    Toggle("outer", isOn: .constant(false)).focusID("outer-side")
                } detail: {
                    split("inner", inner)
                }
            }
            harness.frame(view)
            harness.focusManager.focus(id: focus)
            harness.frame(view)
            harness.press(Self.controlS)
            #expect(outer.visibility == expectOuter, "focus on \(focus)")
            #expect(inner.visibility == expectInner, "focus on \(focus)")
        }
    }

    // MARK: Other modifiers

    @Test("toolbar(removing: .sidebarToggle) keeps the chords")
    func removalKeepsTheChords() {
        let harness = Harness()
        let box = Box()
        harness.frame(split("a", box).toolbar(removing: .sidebarToggle))
        #expect(harness.press(Self.controlS))
        #expect(box.visibility == .detailOnly)
    }

    @Test("A disabled split ignores the chords")
    func disabledSplitIgnoresThem() {
        let harness = Harness()
        let box = Box()
        harness.frame(split("a", box).disabled(true))
        harness.press(Self.controlS)
        harness.press(Self.optionControlS)
        #expect(box.visibility == .all)
    }

    @Test("⌃S hiding the focused sidebar leaves the keyboard in the split")
    func chordHidingTheFocusedColumn() {
        let harness = Harness()
        let box = Box()
        let view = VStack {
            Toggle("above", isOn: .constant(false)).focusID("above")
            split("a", box)
        }
        harness.frame(view)
        harness.focusManager.focus(id: "a-side")
        harness.frame(view)
        harness.press(Self.controlS)
        harness.frame(view)
        #expect(box.visibility == .detailOnly)
        #expect(harness.focusManager.currentFocusedID == "a-detail")
    }
}
