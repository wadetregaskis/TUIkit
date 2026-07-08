//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FocusStormTests.swift
//
//  A deterministic registration-churn storm over the focus system: each
//  simulated frame re-registers a random subset of elements (some disabled)
//  across three sections, dispatches keys, and checks the focus invariants -
//  the focused element is always registered and focusable, Tab always finds
//  a focusable element when one exists anywhere, and nothing is focused when
//  nothing can be. This storm found the two section-edge bugs pinned in
//  FocusEdgeCaseTests.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Focus registration-churn storm", .serialized)
struct FocusStormTests {
    @Test("Registration churn + key dispatch keeps focus invariants")
    func focusStorm() {
        var seed: UInt64 = 0x0123456789ABCDEF
        func rand(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(max(1, bound)))
        }

        var violations: [String] = []

        for trial in 0..<20 {
            let manager = FocusManager()
            let sections = ["alpha", "beta", "gamma"]
            // A pool of elements distributed across sections.
            let pool: [(section: String, element: MockFocusable)] = (0..<12).map { index in
                (sections[index % sections.count], MockFocusable(id: "el\(index)"))
            }

            for frame in 0..<120 {
                // === One render pass: re-register a random subset ===
                manager.beginRenderPass()
                for section in sections { manager.registerSection(id: section) }
                var registered: [MockFocusable] = []
                for (section, element) in pool where rand(4) != 0 {  // ~75% present
                    element.canBeFocused = rand(5) != 0              // ~80% enabled
                    manager.register(element, inSection: section)
                    registered.append(element)
                }
                manager.endRenderPass()

                // === Dispatch a few keys ===
                let events: [KeyEvent] = [
                    KeyEvent(key: .tab), KeyEvent(key: .tab, shift: true),
                    KeyEvent(key: .down), KeyEvent(key: .up), KeyEvent(key: .enter),
                ]
                for _ in 0..<3 {
                    _ = manager.dispatchKeyEvent(events[rand(events.count)])
                }

                // === Invariants ===
                if let focused = manager.currentFocused {
                    let mock = focused as? MockFocusable
                    if let mock, !registered.contains(where: { $0 === mock }) {
                        violations.append("trial \(trial) frame \(frame): focused '\(focused.focusID)' is not registered this frame")
                        break
                    }
                    if !focused.canBeFocused {
                        violations.append("trial \(trial) frame \(frame): focused '\(focused.focusID)' is disabled")
                        break
                    }
                }
                // After a Tab, if anything is focusable, something should hold focus.
                _ = manager.dispatchKeyEvent(KeyEvent(key: .tab))
                let anyFocusable = registered.contains { $0.canBeFocused }
                if anyFocusable && manager.currentFocused == nil {
                    violations.append("trial \(trial) frame \(frame): nothing focused though \(registered.filter(\.canBeFocused).count) focusables exist")
                    break
                }
                if !anyFocusable && manager.currentFocused != nil {
                    violations.append("trial \(trial) frame \(frame): '\(manager.currentFocused!.focusID)' focused though nothing is focusable")
                    break
                }
            }
        }

        if !violations.isEmpty {
            print("=== FOCUS VIOLATIONS (\(violations.count)) ===")
            for violation in violations.prefix(10) { print(violation) }
        }
        #expect(violations.isEmpty)
    }
}
