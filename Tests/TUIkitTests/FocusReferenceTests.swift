//  TUIKit - Terminal UI Kit for Swift
//  FocusReferenceTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

// MARK: - Focus Reference Tests

@MainActor
@Suite("Focus Reference Tests", .serialized)
struct FocusReferenceTests {

    @Test("FocusReference isFocused reflects focus manager state")
    func focusReferenceIsFocused() {
        let manager = FocusManager()
        let state = FocusReference(id: "state-test", focusManager: manager)
        let element = MockFocusable(id: "state-test")

        manager.register(element)

        // The element is focused, so state should report focused
        #expect(state.isFocused)
    }

    @Test("FocusReference requestFocus changes focus via manager")
    func focusReferenceRequestFocus() {
        let manager = FocusManager()

        let element1 = MockFocusable(id: "req-1")
        let element2 = MockFocusable(id: "req-2")

        manager.register(element1)
        manager.register(element2)

        // First element is focused after registration
        #expect(manager.isFocused(id: "req-1"))

        // Request focus for second element
        FocusReference(id: "req-2", focusManager: manager).requestFocus()
        #expect(manager.isFocused(id: "req-2"), "req-2 should be focused after requestFocus()")
    }
}
