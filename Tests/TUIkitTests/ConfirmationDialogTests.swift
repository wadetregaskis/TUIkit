//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ConfirmationDialogTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("confirmationDialog")
struct ConfirmationDialogTests {
    private func render(_ view: some View) -> [String] {
        let context = RenderContext(availableWidth: 80, availableHeight: 24, tuiContext: TUIContext())
            .isolatingRenderCache()
        return renderToBuffer(view, context: context)
            .compositingOverlays(maxWidth: 80, maxHeight: 24, palette: context.environment.palette)
            .lines.map { $0.stripped }
    }

    @Test("Not presented shows only the base content")
    func notPresented() {
        let lines = render(
            Text("Base").confirmationDialog(
                "ConfirmTitle", isPresented: .constant(false),
                actions: { Button("Delete") {} },
                message: { Text("Are you sure?") }))
        let joined = lines.joined(separator: "\n")
        #expect(joined.contains("Base"))
        #expect(!joined.contains("ConfirmTitle"))
        #expect(!joined.contains("Are you sure"))
    }

    @Test("Presented shows the dialog with vertically stacked buttons")
    func presentedStacksVertically() {
        let lines = render(
            Text("Base").confirmationDialog(
                "ConfirmTitle", isPresented: .constant(true),
                actions: {
                    Button("Delete") {}
                    Button("Cancel", role: .cancel) {}
                },
                message: { Text("Are you sure?") }))
        let joined = lines.joined(separator: "\n")
        #expect(joined.contains("ConfirmTitle") && joined.contains("Are you sure"))

        let deleteLine = lines.firstIndex { $0.contains("Delete") }
        let cancelLine = lines.firstIndex { $0.contains("Cancel") }
        #expect(deleteLine != nil && cancelLine != nil, "both buttons render")
        #expect(deleteLine != cancelLine, "action-sheet buttons stack on different lines")
        #expect((deleteLine ?? 0) < (cancelLine ?? 0), "the cancel-role button sorts to the bottom")
    }

    @Test("titleVisibility .hidden suppresses the title")
    func hiddenTitle() {
        let lines = render(
            Text("Base").confirmationDialog(
                "SecretTitle", isPresented: .constant(true), titleVisibility: .hidden,
                actions: { Button("OK") {} }))
        let joined = lines.joined(separator: "\n")
        #expect(!joined.contains("SecretTitle"), "a hidden title is not rendered")
        #expect(joined.contains("OK"))
    }
}
