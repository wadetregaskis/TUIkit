//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ANSIColor.swift
//
//  Created by LAYERED.work
//  License: MIT

/// The terminal's sixteen colour slots: the eight standard ANSI colours and
/// their eight bright twins.
///
/// A slot is a name, not a colour. SGR 31 paints whatever the user's terminal
/// profile keeps in slot 1, and the user may make that green. The raw value is
/// the slot's number, which is also its index in the 256-colour palette and
/// in OSC 4.
///
/// The terminal's default foreground and background, SGR 39 and 49, are not
/// slots, so they are not cases here. They are `Color.default`.
public enum ANSIColor: UInt8, Sendable, CaseIterable {
    case black = 0
    case red = 1
    case green = 2
    case yellow = 3
    case blue = 4
    case magenta = 5
    case cyan = 6
    case white = 7
    case brightBlack = 8
    case brightRed = 9
    case brightGreen = 10
    case brightYellow = 11
    case brightBlue = 12
    case brightMagenta = 13
    case brightCyan = 14
    case brightWhite = 15

    /// Whether this is one of the eight bright slots, 8 through 15.
    public var isBright: Bool { rawValue >= 8 }

    /// The bright slot of this slot's pair: `.brightRed` for `.red`. A bright
    /// slot is its own bright twin.
    public var brightTwin: Self {
        // `rawValue | 8` is always 8...15, a slot; the fallback is never taken.
        Self(rawValue: rawValue | 8) ?? self
    }

    /// The SGR code that sets this slot as the foreground: 30–37, or 90–97 for a
    /// bright slot.
    ///
    /// Not `30 + rawValue`, which would spell slot 9 as 39, the default
    /// foreground.
    public var foregroundCode: UInt8 {
        isBright ? 90 + (rawValue - 8) : 30 + rawValue
    }

    /// The SGR code that sets this slot as the background: 40–47, or 100–107 for
    /// a bright slot.
    public var backgroundCode: UInt8 {
        isBright ? 100 + (rawValue - 8) : 40 + rawValue
    }

    /// SGR 39, the terminal's default foreground, which is no slot's code.
    package static let defaultForegroundCode: UInt8 = 39

    /// SGR 49, the terminal's default background, which is no slot's code.
    package static let defaultBackgroundCode: UInt8 = 49

    // MARK: - xterm's values

    /// xterm's conventional RGB for this slot.
    ///
    /// Not what the slot measures as. The user's terminal profile decides what a
    /// slot paints, and `Color.ansi(_:)` measures as the colour the terminal
    /// reported for it, or as nothing until it has. This table is kept where a
    /// number is needed and nothing is measured: quantising RGB to sixteen colours,
    /// and reading a slot the terminal has not reported as a value, as a colour
    /// editor does. See "What an ANSI colour actually paints" in
    /// `Documentation/Terminal-compatibility.md`.
    public var xtermRGB: (red: UInt8, green: UInt8, blue: UInt8) {
        switch self {
        case .black: return (0, 0, 0)
        case .red: return (205, 0, 0)
        case .green: return (0, 205, 0)
        case .yellow: return (205, 205, 0)
        case .blue: return (0, 0, 238)
        case .magenta: return (205, 0, 205)
        case .cyan: return (0, 205, 205)
        case .white: return (229, 229, 229)
        case .brightBlack: return (127, 127, 127)
        case .brightRed: return (255, 0, 0)
        case .brightGreen: return (0, 255, 0)
        case .brightYellow: return (255, 255, 0)
        case .brightBlue: return (92, 92, 255)
        case .brightMagenta: return (255, 0, 255)
        case .brightCyan: return (0, 255, 255)
        case .brightWhite: return (255, 255, 255)
        }
    }
}
