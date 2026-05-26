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
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        return RenderContext(
            availableWidth: 80,
            availableHeight: 24,
            environment: environment,
            tuiContext: TUIContext()
        )
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
