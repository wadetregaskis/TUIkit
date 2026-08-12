//  🖥️ TUIKit — Terminal UI Kit for Swift
//  BorderStyle.swift
//
//  Created by LAYERED.work
//  License: MIT

/// Defines the visual style of a border.
///
/// Each style provides characters for all border components:
/// corners, edges, and T-junctions for complex layouts.
public struct BorderStyle: Sendable, Hashable {
    /// Top-left corner character.
    public let topLeft: Character

    /// Top-right corner character.
    public let topRight: Character

    /// Bottom-left corner character.
    public let bottomLeft: Character

    /// Bottom-right corner character.
    public let bottomRight: Character

    /// Horizontal edge character.
    public let horizontal: Character

    /// Vertical edge character.
    public let vertical: Character

    /// Left T-junction character (├).
    public let leftT: Character

    /// Right T-junction character (┤).
    public let rightT: Character

    /// Creates a custom border style.
    public init(
        topLeft: Character,
        topRight: Character,
        bottomLeft: Character,
        bottomRight: Character,
        horizontal: Character,
        vertical: Character,
        leftT: Character? = nil,
        rightT: Character? = nil
    ) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight
        self.horizontal = horizontal
        self.vertical = vertical
        // Default T-junctions based on the vertical character
        self.leftT = leftT ?? vertical
        self.rightT = rightT ?? vertical
    }

    // MARK: - Preset Styles

    /// Single line border (─ │ ┌ ┐ └ ┘ ├ ┤).
    ///
    /// ```
    /// ┌─────────┐
    /// │ Title   │
    /// ├─────────┤
    /// │ Content │
    /// └─────────┘
    /// ```
    public static let line = Self(
        topLeft: "┌",
        topRight: "┐",
        bottomLeft: "└",
        bottomRight: "┘",
        horizontal: "─",
        vertical: "│",
        leftT: "├",
        rightT: "┤"
    )

    /// Double line border (═ ║ ╔ ╗ ╚ ╝ ╠ ╣).
    ///
    /// ```
    /// ╔═════════╗
    /// ║ Title   ║
    /// ╠═════════╣
    /// ║ Content ║
    /// ╚═════════╝
    /// ```
    public static let doubleLine = Self(
        topLeft: "╔",
        topRight: "╗",
        bottomLeft: "╚",
        bottomRight: "╝",
        horizontal: "═",
        vertical: "║",
        leftT: "╠",
        rightT: "╣"
    )

    /// Rounded border with curved corners (─ │ ╭ ╮ ╰ ╯ ├ ┤).
    ///
    /// ```
    /// ╭─────────╮
    /// │ Title   │
    /// ├─────────┤
    /// │ Content │
    /// ╰─────────╯
    /// ```
    public static let rounded = Self(
        topLeft: "╭",
        topRight: "╮",
        bottomLeft: "╰",
        bottomRight: "╯",
        horizontal: "─",
        vertical: "│",
        leftT: "├",
        rightT: "┤"
    )

    /// Heavy/bold border (━ ┃ ┏ ┓ ┗ ┛ ┣ ┫).
    ///
    /// ```
    /// ┏━━━━━━━━━┓
    /// ┃ Title   ┃
    /// ┣━━━━━━━━━┫
    /// ┃ Content ┃
    /// ┗━━━━━━━━━┛
    /// ```
    public static let heavy = Self(
        topLeft: "┏",
        topRight: "┓",
        bottomLeft: "┗",
        bottomRight: "┛",
        horizontal: "━",
        vertical: "┃",
        leftT: "┣",
        rightT: "┫"
    )

    /// No visible border (space characters).
    public static let none = Self(
        topLeft: " ",
        topRight: " ",
        bottomLeft: " ",
        bottomRight: " ",
        horizontal: " ",
        vertical: " ",
        leftT: " ",
        rightT: " "
    )
}
