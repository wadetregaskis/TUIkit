//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextCursorStyle.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - TextCursorStyle

/// Defines the visual appearance and animation of the text cursor in text fields.
///
/// Use this type with the `.textCursor(_:)` modifier to customize how the cursor
/// appears in ``TextField`` and ``SecureField`` components.
///
/// ## Cursor Shapes
///
/// TUIkit provides three cursor shapes optimized for terminal display:
///
/// | Shape | Character | Description |
/// |-------|-----------|-------------|
/// | `block` | `█` | Full block cursor (default) |
/// | `bar` | `▎` | Insertion bar at the left edge of the cell |
/// | `underscore` | `▁` | Lower one eighth block |
///
/// ## Animation Styles
///
/// | Animation | Description |
/// |-----------|-------------|
/// | `none` | Static cursor, no animation |
/// | `blink` | Classic on/off blinking |
/// | `pulse` | Smooth color pulsing between dim and bright |
///
/// ## Animation Speed
///
/// How fast the cursor animates is not part of its style. It is the speed set for
/// the text cursor with `indicatorAnimationSpeed(_:for: .textCursor)`. At the
/// standard rate a blink shows and hides for 350 ms each and a pulse takes 800 ms,
/// and each is divided by the rate: at `.doubleSpeed` a blink's halves are 175 ms.
///
/// ## While the Window Is Not Active
///
/// Where a field does not appear active (its environment's `appearsActive` is
/// `false`, as when the terminal window loses focus), the cursor neither blinks
/// nor pulses. It stays visible, still, at the dim end of its pulse, whatever its
/// animation, and animates again when the field appears active.
///
/// ## Usage
///
/// ```swift
/// // Block cursor with pulse animation (default)
/// TextField("Name", text: $name)
///
/// // Bar cursor with blink animation
/// TextField("Email", text: $email)
///     .textCursor(.bar, animation: .blink)
///
/// // Fast blinking underscore cursor
/// TextField("Code", text: $code)
///     .textCursor(.underscore, animation: .blink)
///     .indicatorAnimationSpeed(.doubleSpeed, for: .textCursor)
///
/// // Apply to all text fields in a container
/// VStack {
///     TextField("First", text: $first)
///     TextField("Last", text: $last)
/// }
/// .textCursor(.bar)
/// ```
public struct TextCursorStyle: Equatable, Sendable {
    /// The visual shape of the cursor.
    public let shape: Shape

    /// The animation style of the cursor.
    public let animation: Animation

    /// Creates a text cursor style with the specified shape and animation.
    ///
    /// - Parameters:
    ///   - shape: The cursor shape. Defaults to `.block`.
    ///   - animation: The cursor animation. Defaults to `.blink`.
    public init(shape: Shape = .block, animation: Animation = .blink) {
        self.shape = shape
        self.animation = animation
    }
}

// MARK: - Shape

extension TextCursorStyle {
    /// The visual shape of the text cursor.
    public enum Shape: String, CaseIterable, Sendable {
        /// Full block cursor (`█`, U+2588).
        ///
        /// The default cursor shape, providing maximum visibility.
        case block

        /// Left-edge bar cursor (`▎`, U+258E).
        ///
        /// An insertion bar at the left edge of the character cell, similar
        /// to modern GUI text editors (where the bar sits just before the
        /// character at the insertion point).
        case bar

        /// Lower underscore cursor (`▁`, U+2581).
        ///
        /// A horizontal line at the bottom of the character cell.
        case underscore

        /// The Unicode character representing this cursor shape.
        public var character: Character {
            switch self {
            case .block: "█"
            case .bar: "▎"
            case .underscore: "▁"
            }
        }
    }
}

// MARK: - Animation

extension TextCursorStyle {
    /// The animation style for the text cursor.
    public enum Animation: String, CaseIterable, Sendable {
        /// No animation. The cursor remains static.
        case none

        /// Classic blinking animation.
        ///
        /// The cursor alternates between visible and invisible at a fixed interval.
        case blink

        /// Smooth pulsing animation.
        ///
        /// The cursor color smoothly transitions between dim and bright,
        /// creating a gentle breathing effect. This is the default animation.
        case pulse
    }
}

// MARK: - Convenience Initializers

extension TextCursorStyle {
    /// A block cursor with blink animation (the default style).
    public static let block = TextCursorStyle(shape: .block, animation: .blink)

    /// A bar cursor with blink animation.
    public static let bar = TextCursorStyle(shape: .bar, animation: .blink)

    /// An underscore cursor with blink animation.
    public static let underscore = TextCursorStyle(shape: .underscore, animation: .blink)
}
