//  🖥️ TUIKit — Terminal UI Kit for Swift
//  AuthDialogTabTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Auth dialog Tab navigation")
struct AuthDialogTabTests {

    private func makeContext(focusManager: FocusManager) -> RenderContext {
        // Same as makeRenderContext, but injecting the caller-held FocusManager
        // (the tests drive focus across renders through it).
        makeRenderContext { environment, _ in
            environment.focusManager = focusManager
        }
    }

    @Test("Tab advances focus through every auth-dialog control in order")
    func tabAdvancesThroughAllAuthDialogControls() {
        // Mirrors the Overlays demo's "Dialog (Authentication)" entry — a
        // ``Dialog`` presented via ``ModalPresentationModifier`` whose body
        // hosts a TextField + SecureField and whose footer hosts Cancel +
        // Sign-in buttons. Without the fix to `FocusManager.activateSection`
        // the every-frame re-activation snapped focus back to the username
        // field, so Tab appeared to do nothing.
        let focusManager = FocusManager()
        let context = makeContext(focusManager: focusManager)

        var username = ""
        var password = ""
        var showOverlay = true

        let modal = Dialog(title: "Sign in") {
            VStack(alignment: .leading, spacing: 1) {
                TextField("Username", text: Binding(
                    get: { username }, set: { username = $0 }))
                SecureField("Password", text: Binding(
                    get: { password }, set: { password = $0 }))
            }
        } footer: {
            HStack {
                Spacer()
                Button("Cancel") { showOverlay = false }
                Button("Sign in") { showOverlay = false }
                    .buttonStyle(.primary)
            }
        }
        .frame(width: 50)

        let isPresented = Binding(get: { showOverlay }, set: { showOverlay = $0 })
        let host = Text("background")
            .modal(isPresented: isPresented) { modal }

        // Render once to populate the focus manager.
        _ = renderToBuffer(host, context: context)

        // Tab four times — each press should land on a distinct focusable
        // (username, password, cancel, sign in) before wrapping back to the
        // start. Re-render between presses so any state-driven focus updates
        // settle before the next Tab.
        var visited: [String?] = [focusManager.currentFocusedID]
        for _ in 0..<4 {
            _ = focusManager.dispatchKeyEvent(KeyEvent(key: .tab))
            _ = renderToBuffer(host, context: context)
            visited.append(focusManager.currentFocusedID)
        }

        let uniqueFirstFour = Set(visited.prefix(4).compactMap { $0 })
        #expect(uniqueFirstFour.count == 4, """
            Tab cycled through only \(uniqueFirstFour.count) distinct focusables:
            \(visited)
            """)
    }

    @Test("Open modal registers ESC=dismiss in the status bar")
    func modalRegistersEscapeDismissItem() {
        let focusManager = FocusManager()
        let context = makeContext(focusManager: focusManager)
        context.environment.statusBar.escapeLabelOverride = nil
        // In a real app the render loop wires StatusBarState to the focus
        // manager so the bar knows which section's items to show. Mirror
        // that here so currentItems picks up the modal's items.
        context.environment.statusBar.focusManager = focusManager

        var presented = true
        let isPresented = Binding(get: { presented }, set: { presented = $0 })
        let view = Text("background").modal(isPresented: isPresented) {
            Dialog(title: "Confirm") {
                Text("Sure?")
            }
        }

        _ = renderToBuffer(view, context: context)

        // The status bar should now carry an ESC item bound to the modal
        // section, whose label says "dismiss" and whose action closes the
        // modal by flipping the presentation binding back to false.
        let items = context.environment.statusBar.currentItems
        let escItem = items.first { $0.shortcut == Shortcut.escape }
        #expect(escItem != nil, "expected an ESC item; items were: \(items.map(\.shortcut))")
        #expect(escItem?.label == "dismiss",
                "expected the ESC label to be 'dismiss', got \(escItem?.label ?? "nil")")

        // Firing the ESC item should close the modal.
        let handled = context.environment.statusBar.handleKeyEvent(KeyEvent(key: .escape))
        #expect(handled, "ESC should have been handled by the status bar item")
        #expect(presented == false, "ESC should have closed the modal")
    }

    @Test("Re-activating an already-active section preserves the focused element")
    func reactivatingAlreadyActiveSectionPreservesFocus() {
        // FocusManager.activateSection used to unconditionally reset focus
        // to the section's first focusable. Modal/Picker overlays call it
        // on every render, so once the section was first set up Tab could
        // never appear to move focus — re-rendering snapped it back.
        let focusManager = FocusManager()
        let a = TestFocusable(id: "a")
        let b = TestFocusable(id: "b")
        focusManager.registerSection(id: "modal")
        focusManager.register(a, inSection: "modal")
        focusManager.register(b, inSection: "modal")
        focusManager.activateSection(id: "modal")

        #expect(focusManager.currentFocusedID == "a")

        // Move focus to the second element.
        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .tab))
        #expect(focusManager.currentFocusedID == "b")

        // Re-activate the section — the focus should stick to "b".
        focusManager.activateSection(id: "modal")
        #expect(focusManager.currentFocusedID == "b",
                "re-activating the active section should not reset focus")
    }
}

/// Minimal `Focusable` implementation used to drive
/// ``FocusManager`` without spinning up a full view tree.
private final class TestFocusable: Focusable, @unchecked Sendable {
    let focusID: String
    var canBeFocused: Bool = true

    init(id: String) {
        self.focusID = id
    }

    func handleKeyEvent(_ event: KeyEvent) -> Bool { false }
}
