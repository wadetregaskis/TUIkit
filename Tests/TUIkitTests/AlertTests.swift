//  🖥️ TUIKit — Terminal UI Kit for Swift
//  AlertTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Alert Sizing Tests

@MainActor
@Suite("Alert Sizing Tests")
struct AlertSizingTests {

    private func context() -> RenderContext {
        let focusManager = FocusManager()
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        return RenderContext(
            availableWidth: 120,
            availableHeight: 30,
            environment: environment,
            tuiContext: TUIContext()
        ).isolatingRenderCache()
    }

    private let sampleMessage = "This is a standard alert with default theme colors."

    @Test("An alert wide enough for its message renders it on a single line")
    func wideAlertDoesNotWrapMessage() {
        let alert = Alert(title: "Standard Alert", message: sampleMessage).frame(width: 60)
        let buffer = renderToBuffer(alert, context: context())

        let intactLine = buffer.lines.contains { $0.stripped.contains(sampleMessage) }
        #expect(
            intactLine,
            "A 60-wide alert must render its 51-character message on one line, not wrap it"
        )
    }

    @Test("A too-narrow alert is forced to wrap its message")
    func narrowAlertWrapsMessage() {
        let alert = Alert(title: "Standard Alert", message: sampleMessage).frame(width: 40)
        let buffer = renderToBuffer(alert, context: context())

        let intactLine = buffer.lines.contains { $0.stripped.contains(sampleMessage) }
        #expect(
            !intactLine,
            "A 40-wide alert genuinely cannot fit the message on one line"
        )
    }
}
