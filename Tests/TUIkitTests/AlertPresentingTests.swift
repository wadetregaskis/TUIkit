//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AlertPresentingTests.swift
//
//  The data-driven alert spellings: `presenting:` and `error:`.
//
//  What they add over closing over the value is a CONDITION — an alert about
//  nothing is not presented — and what they risk is the builders' output being
//  wrapped in an Optional on the way to the modifier, which is where an alert's
//  buttons are found by walking the actions view. Both are asserted here.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

@MainActor
@Suite("Data-driven alerts")
struct AlertPresentingTests {

    private struct Doomed {
        let name: String
    }

    private struct Sad: LocalizedError {
        var errorDescription: String? { "The disk is full" }
        var recoverySuggestion: String? { "Delete something." }
    }

    private struct Terse: LocalizedError {
        var errorDescription: String? { "Nope" }
    }

    private func render(_ view: some View) -> String {
        let context = RenderContext(
            availableWidth: 80, availableHeight: 24, tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context)
            .compositingOverlays(
                maxWidth: 80, maxHeight: 24, palette: context.environment.palette)
            .lines.joined(separator: "\n").stripped
    }

    @Test("presenting: builds the alert from the value")
    func presentingBuildsFromTheValue() {
        let screen = render(
            Text("base")
                .alert(
                    "Delete?", isPresented: .constant(true), presenting: Doomed(name: "notes.txt")
                ) { doomed in
                    Button("Delete \(doomed.name)") {}
                    Button("Cancel", role: .cancel) {}
                } message: { doomed in
                    Text("\(doomed.name) cannot be recovered.")
                })

        #expect(screen.contains("Delete?"))
        #expect(screen.contains("notes.txt cannot be recovered."))
        // The buttons are what the Optional wrapper most easily swallows: they
        // reach the alert by walking the actions view for `Button`s, and an
        // `Optional<TupleView<…>>` is not the shape that walk was written for.
        #expect(screen.contains("Delete notes.txt"), "the actions survived the builder: \(screen)")
        #expect(screen.contains("Cancel"))
    }

    @Test("A nil value withholds the alert even while the flag is true")
    func nilValueWithholdsTheAlert() {
        let screen = render(
            Text("base")
                .alert("Delete?", isPresented: .constant(true), presenting: Doomed?.none) { doomed in
                    Button("Delete \(doomed.name)") {}
                } message: { doomed in
                    Text("\(doomed.name) cannot be recovered.")
                })

        #expect(screen.contains("base"))
        #expect(!screen.contains("Delete?"), "an alert about nothing is not an alert: \(screen)")
    }

    @Test("presenting: without a message")
    func presentingWithoutAMessage() {
        let screen = render(
            Text("base")
                .alert(
                    "Discard?", isPresented: .constant(true), presenting: Doomed(name: "draft")
                ) { doomed in
                    Button("Discard \(doomed.name)") {}
                })

        #expect(screen.contains("Discard?"))
        #expect(screen.contains("Discard draft"))
    }

    @Test("error: takes its title and message off the error")
    func errorSuppliesTitleAndMessage() {
        let screen = render(
            Text("base")
                .alert(isPresented: .constant(true), error: Sad()) {
                    Button("OK") {}
                })

        #expect(screen.contains("The disk is full"))
        #expect(screen.contains("Delete something."))
        #expect(screen.contains("OK"))
    }

    @Test("An error with no recovery suggestion gets no message")
    func errorWithoutARecoverySuggestion() {
        let screen = render(
            Text("base")
                .alert(isPresented: .constant(true), error: Terse()) {
                    Button("OK") {}
                })

        #expect(screen.contains("Nope"))
        #expect(screen.contains("OK"))
    }

    @Test("A nil error withholds the alert")
    func nilErrorWithholdsTheAlert() {
        let screen = render(
            Text("base")
                .alert(isPresented: .constant(true), error: Sad?.none) {
                    Button("OK") {}
                })

        #expect(screen.contains("base"))
        #expect(!screen.contains("OK"), "nothing to describe, so nothing to dismiss: \(screen)")
    }

    @Test("The error form with a message of its own hands the error to both builders")
    func errorWithCustomMessage() {
        let screen = render(
            Text("base")
                .alert(isPresented: .constant(true), error: Sad()) { error in
                    Button("Retry (\(error.errorDescription ?? ""))") {}
                } message: { error in
                    Text("Suggestion: \(error.recoverySuggestion ?? "none")")
                })

        #expect(screen.contains("The disk is full"))
        #expect(screen.contains("Suggestion: Delete something."))
        #expect(screen.contains("Retry (The disk is full)"))
    }

    @Test("confirmationDialog takes presenting: on the same terms")
    func confirmationDialogPresenting() {
        let screen = render(
            Text("base")
                .confirmationDialog(
                    "Discard?", isPresented: .constant(true), presenting: Doomed(name: "draft")
                ) { doomed in
                    Button("Discard \(doomed.name)", role: .destructive) {}
                    Button("Keep", role: .cancel) {}
                } message: { doomed in
                    Text("\(doomed.name) has unsaved changes.")
                })

        #expect(screen.contains("Discard?"))
        #expect(screen.contains("draft has unsaved changes."))
        #expect(screen.contains("Discard draft"))
        #expect(screen.contains("Keep"))
    }

    @Test("A nil value withholds the confirmation dialog too")
    func confirmationDialogNilWithholds() {
        let screen = render(
            Text("base")
                .confirmationDialog(
                    "Discard?", isPresented: .constant(true), presenting: Doomed?.none
                ) { doomed in
                    Button("Discard \(doomed.name)") {}
                })

        #expect(screen.contains("base"))
        #expect(!screen.contains("Discard?"), "nothing to confirm: \(screen)")
    }

    @Test("titleVisibility still suppresses the title of a presenting dialog")
    func confirmationDialogHiddenTitle() {
        let screen = render(
            Text("base")
                .confirmationDialog(
                    "Discard?", isPresented: .constant(true), titleVisibility: .hidden,
                    presenting: Doomed(name: "draft")
                ) { doomed in
                    Button("Discard \(doomed.name)") {}
                })

        #expect(!screen.contains("Discard?"))
        #expect(screen.contains("Discard draft"))
    }
}
