//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StatusBarItemTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Status Bar Item Tests

@MainActor
@Suite("Status Bar Item Tests")
struct StatusBarItemTests {

    @Test("StatusBarItem with action")
    func itemWithAction() {
        // Use a class to track execution since the closure is @Sendable
        final class ExecutionTracker: @unchecked Sendable {
            var wasExecuted = false
        }
        let tracker = ExecutionTracker()

        let item = StatusBarItem(shortcut: "x", label: "execute") {
            tracker.wasExecuted = true
        }

        item.execute()
        #expect(tracker.wasExecuted == true)
    }

    @Test("StatusBarItem derives key from single character")
    func deriveKeyFromCharacter() {
        let item = StatusBarItem(shortcut: "q", label: "quit")

        #expect(item.triggerKey == .character("q"))
    }

    @Test("StatusBarItem derives key from escape symbol")
    func deriveKeyFromEscape() {
        let item = StatusBarItem(shortcut: Shortcut.escape, label: "close")

        #expect(item.triggerKey == .escape)
    }

    @Test("StatusBarItem derives key from enter symbol")
    func deriveKeyFromEnter() {
        let item = StatusBarItem(shortcut: Shortcut.enter, label: "confirm")

        #expect(item.triggerKey == .enter)
    }

    @Test("StatusBarItem with explicit key")
    func itemWithExplicitKey() {
        let item = StatusBarItem(
            shortcut: "navigate",
            label: "nav",
            key: .up
        )

        #expect(item.triggerKey == .up)
    }

    @Test("StatusBarItem informational has no trigger key")
    func informationalItem() {
        // Multi-character shortcut without explicit key
        let item = StatusBarItem(shortcut: "↑↓", label: "nav")

        // Arrow combinations don't have a single trigger key
        // but matches() handles them specially
        #expect(item.triggerKey == nil)
    }

    @Test("StatusBarItem matches character key")
    func matchesCharacterKey() {
        let item = StatusBarItem(shortcut: "q", label: "quit")

        let event = KeyEvent(key: .character("q"))
        #expect(item.matches(event) == true)

        let wrongEvent = KeyEvent(key: .character("x"))
        #expect(item.matches(wrongEvent) == false)
    }

    @Test("StatusBarItem case sensitive matching")
    func caseSensitiveMatching() {
        let lowerItem = StatusBarItem(shortcut: "n", label: "new")
        let upperItem = StatusBarItem(shortcut: "N", label: "New")

        let lowerEvent = KeyEvent(key: .character("n"))
        let upperEvent = KeyEvent(key: .character("N"))

        #expect(lowerItem.matches(lowerEvent) == true)
        #expect(lowerItem.matches(upperEvent) == false)

        #expect(upperItem.matches(upperEvent) == true)
        #expect(upperItem.matches(lowerEvent) == false)
    }

    @Test("StatusBarItem matches arrow combinations")
    func matchesArrowCombinations() {
        let item = StatusBarItem(shortcut: "↑↓", label: "nav")

        let upEvent = KeyEvent(key: .up)
        let downEvent = KeyEvent(key: .down)
        let leftEvent = KeyEvent(key: .left)

        #expect(item.matches(upEvent) == true)
        #expect(item.matches(downEvent) == true)
        #expect(item.matches(leftEvent) == false)
    }

    /// The shortcut vocabulary can only spell BARE keys — there is no "^a" —
    /// so an item on "a" means plain `a`, and must not also swallow Ctrl+A /
    /// Alt+A, which belong to later dispatch layers (`.selectAll` row
    /// shortcuts, Ctrl+arrow row moves). Status-bar items sit at layer 1,
    /// ahead of everything, so a modifier-blind match here starves those
    /// layers of their chords.
    @Test("StatusBarItem never matches a modified chord of its bare key")
    func modifiedChordsDoNotMatch() {
        let letterItem = StatusBarItem(shortcut: "a", label: "appearance")
        #expect(letterItem.matches(KeyEvent(key: .character("a"))) == true)
        #expect(letterItem.matches(KeyEvent(key: .character("a"), ctrl: true)) == false)
        #expect(letterItem.matches(KeyEvent(key: .character("a"), alt: true)) == false)

        let arrowItem = StatusBarItem(shortcut: "↑↓", label: "nav")
        #expect(arrowItem.matches(KeyEvent(key: .up, shift: true)) == false)
        #expect(arrowItem.matches(KeyEvent(key: .up, ctrl: true)) == false)
        #expect(arrowItem.matches(KeyEvent(key: .down, alt: true)) == false)

        let escItem = StatusBarItem(shortcut: "esc", label: "back")
        #expect(escItem.matches(KeyEvent(key: .escape)) == true)
        #expect(escItem.matches(KeyEvent(key: .escape, alt: true)) == false)
    }

    @Test("StatusBarItem matches all arrows")
    func matchesAllArrows() {
        let item = StatusBarItem(shortcut: Shortcut.arrowsAll, label: "move")

        #expect(item.matches(KeyEvent(key: .up)) == true)
        #expect(item.matches(KeyEvent(key: .down)) == true)
        #expect(item.matches(KeyEvent(key: .left)) == true)
        #expect(item.matches(KeyEvent(key: .right)) == true)
    }
}

// MARK: - Status Bar Item Builder Tests

@MainActor
@Suite("Status Bar Item Builder Tests")
struct StatusBarItemBuilderTests {

    @Test("Builder buildBlock combines arrays")
    func builderCreatesArray() {
        let items = StatusBarItemBuilder.buildBlock(
            [StatusBarItem(shortcut: "a", label: "a")],
            [StatusBarItem(shortcut: "b", label: "b")]
        )

        #expect(items.count == 2)
    }

    @Test("Builder handles expression")
    func builderHandlesExpression() {
        let item = StatusBarItem(shortcut: "e", label: "expr")
        let result = StatusBarItemBuilder.buildExpression(item)

        #expect(result.count == 1)
    }

    // MARK: - Control Flow
    //
    // `buildBlock` and `buildExpression` were called directly above; the four
    // control-flow methods can only be reached by WRITING the control flow, so
    // that is what these do. Asserted by shortcut rather than by count: a
    // `buildEither` whose two arms are transposed — the classic copy-paste in a
    // result builder, invisible at the call site — keeps the count right and
    // shows the wrong key.

    /// Builds an item list from a closure, the way `.statusBarItems { }` and
    /// `StatusBarState.setItems { }` do, and reads back the shortcuts.
    private func build(
        @StatusBarItemBuilder _ builder: () -> [any StatusBarItemProtocol]
    ) -> [String] {
        builder().map(\.shortcut)
    }

    @Test("An if without else contributes its item only when the condition holds")
    func builderOptional() {
        func items(editing: Bool) -> [String] {
            build {
                StatusBarItem(shortcut: "n", label: "new")
                if editing {
                    StatusBarItem(shortcut: "s", label: "save")
                }
            }
        }

        #expect(items(editing: true) == ["n", "s"])
        #expect(items(editing: false) == ["n"])
    }

    @Test("An if/else contributes the arm that matches, not the other one")
    func builderEither() {
        func items(editing: Bool) -> [String] {
            build {
                if editing {
                    StatusBarItem(shortcut: "s", label: "save")
                } else {
                    StatusBarItem(shortcut: "e", label: "edit")
                }
            }
        }

        #expect(items(editing: true) == ["s"])
        #expect(items(editing: false) == ["e"], "the else arm must not be dropped or swapped")
    }

    @Test("An if let contributes the bound item")
    func builderOptionalBinding() {
        func items(shortcut: String?) -> [String] {
            build {
                if let shortcut {
                    StatusBarItem(shortcut: shortcut, label: "bound")
                }
            }
        }

        #expect(items(shortcut: "b") == ["b"])
        #expect(items(shortcut: nil).isEmpty)
    }

    @Test("A for loop contributes every iteration, in order")
    func builderArray() {
        let shortcuts = ["1", "2", "3"]
        let items = build {
            StatusBarItem(shortcut: "h", label: "head")
            for shortcut in shortcuts {
                StatusBarItem(shortcut: shortcut, label: "item \(shortcut)")
            }
        }

        #expect(items == ["h", "1", "2", "3"])
    }

    @Test("An empty for loop contributes nothing")
    func builderEmptyArray() {
        let items = build {
            for shortcut in [String]() {
                StatusBarItem(shortcut: shortcut, label: shortcut)
            }
        }

        #expect(items.isEmpty)
    }
}
