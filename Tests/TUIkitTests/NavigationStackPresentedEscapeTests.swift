//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationStackPresentedEscapeTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// What the status bar says Escape does while a dialog is up over a pushed
/// `NavigationStack` screen.
///
/// The stack's bar claims Escape as going back whenever nothing else has, and
/// it recognised only one kind of claim: a surface that WRITES the escape label
/// (an open menu, a popover, a drop-down). A sheet or an alert claims Escape as
/// a status-bar item of its own section instead, so the stack saw no claim and
/// wrote its own label — and the bar renames every escape item to the claimed
/// label. The key still closed the dialog; the bar said it would leave the
/// screen.
@MainActor
@Suite("NavigationStack escape under a presented dialog")
struct NavigationStackPresentedEscapeTests {

    private struct Item: Hashable {
        let name: String
    }

    private var dismissLabel: String {
        LocalizationService.shared.string(for: LocalizationKey.StatusBar.dismiss)
    }

    private var goBackLabel: String {
        LocalizationService.shared.string(for: LocalizationKey.StatusBar.goBack)
    }

    /// One frame with `screen` pushed: the status bar as
    /// `RenderLoop.buildStatusBarBuffer` draws it, the escape label claim
    /// standing over it, and whether Escape at the status bar's own layer did
    /// anything.
    ///
    /// All three are read while the frame's context is alive. The status bar
    /// holds its focus manager weakly and the context owns it; released, the
    /// bar cannot tell which section's items are showing and reads none.
    private func frame(
        pushing screen: some View
    ) throws -> (bar: String, claim: String?, escapeFired: Bool) {
        var path = NavigationPath()
        path.append(Item(name: "one"))
        let binding = Binding(get: { path }, set: { path = $0 })
        let context = makeRenderContext(width: 60, height: 16)
        _ = renderToBuffer(
            NavigationStack(path: binding) {
                Text("root")
                    .navigationDestination(for: Item.self) { _ in screen }
            }, context: context)
        let statusBar = try #require(context.environment.statusBar)

        return withExtendedLifetime(context) { () -> (bar: String, claim: String?, escapeFired: Bool) in
            let bar = renderToBuffer(
                StatusBar(
                    userItems: statusBar.currentUserItems,
                    systemItems: statusBar.currentSystemItems,
                    style: .compact),
                context: context
            ).lines.map(\.stripped).joined()
            let claim = statusBar.escapeLabelOverride
            let escapeFired = statusBar.handleKeyEvent(KeyEvent(key: .escape))
            return (bar, claim, escapeFired)
        }
    }

    @Test("A sheet over a pushed screen keeps its dismiss label, and Escape fires it")
    func sheetKeepsItsDismissLabel() throws {
        var presented = true
        let screen = Text("detail").sheet(
            isPresented: Binding(get: { presented }, set: { presented = $0 })
        ) {
            Dialog(title: "Edit") { Text("body") }
        }

        let shown = try frame(pushing: screen)
        #expect(shown.bar.contains(dismissLabel), "the dialog's own verb belongs on the bar")
        #expect(!shown.bar.contains(goBackLabel), "Escape closes the sheet; it does not go back")
        #expect(shown.claim == nil)
        // With no claim standing over it, the dialog's item is live at the
        // status bar's own layer — the route it was built for — rather than
        // reachable only through the key-handler fallback.
        #expect(shown.escapeFired)
        #expect(!presented)
    }

    @Test("An alert over a pushed screen is not advertised as going back")
    func alertKeepsItsDismissLabel() throws {
        let screen = Text("detail")
            .alert("Discard?", isPresented: .constant(true)) {
                Button("OK") {}
            } message: {
                Text("gone")
            }

        let shown = try frame(pushing: screen)
        #expect(shown.bar.contains(dismissLabel), "the alert's own verb belongs on the bar")
        #expect(!shown.bar.contains(goBackLabel), "Escape answers the alert; it does not go back")
        #expect(shown.escapeFired)
    }

    @Test("A sheet that cannot be dismissed by hand leaves Escape off the bar")
    func undismissableSheetAdvertisesNoEscape() throws {
        // The sheet publishes no escape item and no handler, and its input grab
        // keeps the stack's pop handler from running: the bar used to offer
        // going back on a key that did nothing at all.
        let screen = Text("detail").sheet(isPresented: .constant(true)) {
            Dialog(title: "Edit") { Text("body") }
                .interactiveDismissDisabled()
        }

        let shown = try frame(pushing: screen)
        #expect(!shown.bar.contains(goBackLabel))
        #expect(!shown.bar.contains(Shortcut.escape), "no escape entry at all")
        #expect(shown.claim == nil)
    }
}
