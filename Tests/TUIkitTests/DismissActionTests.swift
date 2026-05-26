//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DismissActionTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Dismiss Action Tests", .serialized)
struct DismissActionTests {

    /// Drains any exit request left over from a previous test or runner.
    private func drainExitFlag() {
        _ = AppState.shared.consumeShouldExit()
    }

    @Test("Calling dismiss requests an exit on AppState.shared")
    func dismissRequestsExit() {
        drainExitFlag()
        let dismiss = DismissAction()
        dismiss()
        #expect(AppState.shared.consumeShouldExit() == true)
        // Flag clears after one consume.
        #expect(AppState.shared.consumeShouldExit() == false)
    }

    @Test("The default environment dismiss action signals an exit")
    func defaultEnvironmentDismissSignalsExit() {
        drainExitFlag()
        var environment = EnvironmentValues()
        environment.dismiss()
        #expect(AppState.shared.consumeShouldExit() == true)
    }

    @Test("requestExit is independent of needsRender flag")
    func requestExitDoesNotInterfereWithRender() {
        drainExitFlag()
        AppState.shared.didRender()  // clear needsRender
        AppState.shared.requestExit()
        // Exit flag is set but consumeNeedsCacheClear still reflects only
        // observable-property changes, which we haven't triggered here.
        #expect(AppState.shared.consumeShouldExit() == true)
        #expect(AppState.shared.consumeNeedsCacheClear() == false)
    }
}
