//  🖥️ TUIkit — Terminal UI Kit for Swift
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

    /// Whether this style's glyphs are opaque — paint the cell in the border's
    /// colour as well as the glyph.
    ///
    /// A `Bool` and not a `Color`, deliberately. A border's colour arrives per
    /// frame — `palette.border`, a container's override, or one step of an
    /// `AnimatedColor` pulse — so a colour stored on the style would be a
    /// second source of truth the pulse could not honour, and an animated wall
    /// would breathe over a frozen background. This says only "my glyph fills
    /// its cell; paint it in whatever colour you are drawing me in", which is
    /// exactly what ``TrackConfiguration/Background/solid`` means.
    ///
    /// True only for ``block``. `U+2588` does not cover its cell on every
    /// terminal — Terminal.app leaves hairline seams between adjacent full
    /// blocks, recorded in `Documentation/Terminal-compatibility.md` — and
    /// painting the cell the same colour as the glyph makes the pixels the
    /// glyph misses the right colour anyway. `TrackConfiguration.block` has
    /// always done this; a border made of the same glyph has the same problem.
    ///
    /// It must stay false for ``none``, whose whole contract is that whatever
    /// is behind it shows through: painting would make the quietest border the
    /// loudest.
    public let paintsBackground: Bool

    /// Creates a custom border style.
    public init(
        topLeft: Character,
        topRight: Character,
        bottomLeft: Character,
        bottomRight: Character,
        horizontal: Character,
        vertical: Character,
        leftT: Character? = nil,
        rightT: Character? = nil,
        paintsBackground: Bool = false
    ) {
        self.paintsBackground = paintsBackground
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

    /// A solid bar of full blocks (█), drawn in the border colour.
    ///
    /// The heaviest border a terminal can draw: not a line around the content
    /// but a band of colour enclosing it. Its corners and junctions are the
    /// same glyph as its edges, because a full block has no direction to turn.
    public static let block = Self(
        topLeft: "█",
        topRight: "█",
        bottomLeft: "█",
        bottomRight: "█",
        horizontal: "█",
        vertical: "█",
        leftT: "█",
        rightT: "█",
        paintsBackground: true
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
