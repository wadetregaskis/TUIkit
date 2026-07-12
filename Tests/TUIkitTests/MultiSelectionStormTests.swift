//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MultiSelectionStormTests.swift
//
//  A seeded storm over the multi-selection keyboard/mouse model: random key
//  events (extension, extend mode, select-all, Escape), clicks (including
//  stale out-of-range indices), data shrink/grow underneath the handler,
//  selectable-subset churn, windowed-vs-eager id paths, and focus loss.
//  Invariants: no traps, movement lands the cursor in range, Ctrl+A selects
//  exactly the selectable ids, an idle Escape is NEVER consumed (page
//  navigation must fall through), and single-selection mode ignores the
//  multi-selection keys entirely.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

private final class MultiSelectionBox {
    var selection: Set<String> = []
    var binding: Binding<Set<String>> {
        Binding(get: { self.selection }, set: { self.selection = $0 })
    }
}

/// One trial's worth of storm state: the handler under test, its data, and
/// the seeded RNG, with one method per random operation so each stays small
/// and the invariants live next to the op that can violate them.
@MainActor
private final class MultiSelectionStormDriver {
    private var seed: UInt64
    private let trial: Int
    private var step = 0
    private let box = MultiSelectionBox()
    private var ids: [String]
    private let handler: ItemListHandler<String>
    private(set) var violations: [String] = []

    private static let movementKeys: [Key] = [.up, .down, .home, .end, .pageUp, .pageDown]
    private static let otherKeys: [Key] = [
        .space, .enter, .character("v"), .character("V"), .character("x"), .tab,
    ]

    init(trial: Int, seed: UInt64) {
        self.trial = trial
        self.seed = seed
        var localSeed = seed
        func rand(_ bound: Int) -> Int {
            localSeed = localSeed &* 6364136223846793005 &+ 1442695040888963407
            return Int((localSeed >> 33) % UInt64(max(1, bound)))
        }
        ids = (0..<(1 + rand(25))).map { "id\($0)" }
        self.seed = localSeed
        handler = ItemListHandler<String>(
            focusID: "storm", itemCount: ids.count, viewportHeight: 5,
            selectionMode: .multi)
        handler.itemIDs = ids
        handler.multiSelection = box.binding
    }

    private func rand(_ bound: Int) -> Int {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Int((seed >> 33) % UInt64(max(1, bound)))
    }

    private func fail(_ message: String) {
        violations.append("trial \(trial) step \(step): \(message)")
    }

    func run(steps: Int) {
        for current in 0..<steps {
            step = current
            performRandomOp()
            checkUniversalInvariants()
            if !violations.isEmpty { return }
        }
    }

    private func performRandomOp() {
        switch rand(10) {
        case 0..<4: movementKey()
        case 4: selectAllKey()
        case 5: escapeKey()
        case 6:
            _ = handler.handleKeyEvent(
                KeyEvent(key: Self.otherKeys[rand(Self.otherKeys.count)], shift: rand(4) == 0))
        case 7: click()
        case 8: churnData()
        default: cycleFocus()
        }
    }

    /// A movement key, sometimes shifted: afterwards the cursor must be in
    /// range whenever there is any data.
    private func movementKey() {
        let key = Self.movementKeys[rand(Self.movementKeys.count)]
        _ = handler.handleKeyEvent(KeyEvent(key: key, shift: rand(3) == 0))
        if handler.itemCount > 0, !(0..<handler.itemCount).contains(handler.focusedIndex) {
            fail("movement left the cursor out of range: \(handler.focusedIndex)/\(handler.itemCount)")
        }
    }

    /// Ctrl+A: exactly the selectable ids become selected.
    private func selectAllKey() {
        guard handler.handleKeyEvent(KeyEvent(key: .character("a"), ctrl: true)) else { return }
        let selectable: Set<String>
        if handler.selectableIndices.isEmpty {
            selectable = Set(ids)
        } else {
            selectable = Set(handler.selectableIndices.compactMap { handler.id(at: $0) })
        }
        if box.selection != selectable {
            fail("Ctrl+A selected \(box.selection.count) of \(selectable.count) selectable ids")
        }
    }

    /// Escape: staged, and NEVER consumed when idle — a focused list must
    /// not block page navigation.
    private func escapeKey() {
        let idle = !handler.isExtendingSelection && box.selection.isEmpty
        let consumed = handler.handleKeyEvent(KeyEvent(key: .escape))
        if idle && consumed {
            fail("an idle Escape was consumed — page navigation would be blocked")
        }
        if !idle && handler.itemCount > 0 && !consumed {
            fail("Escape had work to do (mode/selection) but was not consumed")
        }
    }

    /// A click, occasionally with a STALE out-of-range index (the mouse maps
    /// rows from the last render; the data may have shrunk since).
    private func click() {
        handler.handleClickSelection(
            at: rand(handler.itemCount + 3),
            event: MouseEvent(
                button: .left, phase: .released, x: 0, y: 0,
                shift: rand(3) == 0, ctrl: rand(4) == 0, meta: rand(6) == 0))
        if handler.isExtendingSelection {
            fail("a click left extend mode active")
        }
    }

    /// Data churn: shrink/grow the data, toggle the selectable subset, and
    /// alternate between the eager itemIDs and windowed idAt paths.
    private func churnData() {
        ids = (0..<rand(30)).map { "id\($0)" }
        if rand(3) == 0 {
            let snapshot = ids
            handler.itemIDs = []
            handler.idAt = { index in
                (0..<snapshot.count).contains(index) ? snapshot[index] : nil
            }
        } else {
            handler.idAt = nil
            handler.itemIDs = ids
        }
        handler.itemCount = ids.count
        if rand(3) == 0, !ids.isEmpty {
            handler.selectableIndices = Set((0..<ids.count).filter { _ in rand(2) == 0 })
        } else {
            handler.selectableIndices = []
        }
    }

    private func cycleFocus() {
        handler.onFocusLost()
        if handler.isExtendingSelection {
            fail("focus loss left extend mode active")
        }
        handler.onFocusReceived()
    }

    private func checkUniversalInvariants() {
        let range = handler.visibleRange
        if range.lowerBound < 0 || range.upperBound > handler.itemCount {
            fail("visibleRange \(range) outside 0..\(handler.itemCount)")
        }
    }
}

@MainActor
@Suite("Multi-selection storm", .serialized)
struct MultiSelectionStormTests {

    @Test("Random keys/clicks/data churn keep the selection invariants")
    func multiSelectionStorm() {
        var violations: [String] = []
        for trial in 0..<30 {
            let driver = MultiSelectionStormDriver(
                trial: trial, seed: 0xDEADBEEFCAFEF00D &+ UInt64(trial) &* 0x9E3779B97F4A7C15)
            driver.run(steps: 250)
            violations.append(contentsOf: driver.violations)
            if !violations.isEmpty { break }
        }

        if !violations.isEmpty {
            print("=== MULTI-SELECTION VIOLATIONS ===")
            for violation in violations.prefix(10) { print(violation) }
        }
        #expect(violations.isEmpty)
    }

    @Test("Single-selection mode never reacts to the multi-selection keys")
    func singleModeStorm() {
        var seed: UInt64 = 0x1357_9BDF_2468_ACE0
        func rand(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(max(1, bound)))
        }

        final class SingleBox {
            var selection: String?
        }
        var violations: [String] = []

        for trial in 0..<10 {
            let box = SingleBox()
            let ids = (0..<(2 + rand(20))).map { "id\($0)" }
            let handler = ItemListHandler<String>(
                focusID: "storm", itemCount: ids.count, viewportHeight: 5,
                selectionMode: .single)
            handler.itemIDs = ids
            handler.singleSelection = Binding(
                get: { box.selection }, set: { box.selection = $0 })

            for step in 0..<150 {
                switch rand(4) {
                case 0:
                    let before = box.selection
                    if handler.handleKeyEvent(KeyEvent(key: .character("v"))) {
                        violations.append("trial \(trial) step \(step): single mode consumed 'v'")
                    }
                    if handler.handleKeyEvent(KeyEvent(key: .character("a"), ctrl: true)) {
                        violations.append("trial \(trial) step \(step): single mode consumed Ctrl+A")
                    }
                    if handler.handleKeyEvent(KeyEvent(key: .escape)) {
                        violations.append("trial \(trial) step \(step): single mode consumed Escape")
                    }
                    if box.selection != before {
                        violations.append("trial \(trial) step \(step): multi keys changed a single selection")
                    }
                case 1:
                    _ = handler.handleKeyEvent(
                        KeyEvent(key: [.up, .down][rand(2)], shift: rand(2) == 0))
                case 2:
                    _ = handler.handleKeyEvent(KeyEvent(key: .space))
                default:
                    handler.handleClickSelection(
                        at: rand(ids.count),
                        event: MouseEvent(button: .left, phase: .released, x: 0, y: 0))
                }
                if handler.isExtendingSelection {
                    violations.append("trial \(trial) step \(step): extend mode active in single mode")
                    break
                }
            }
            if !violations.isEmpty { break }
        }

        if !violations.isEmpty {
            print("=== SINGLE-MODE VIOLATIONS ===")
            for violation in violations.prefix(10) { print(violation) }
        }
        #expect(violations.isEmpty)
    }
}
