//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MouseEvent.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Mouse Button

/// Which mouse button (or wheel direction) generated an event.
public enum MouseButton: Sendable, Equatable {
    /// The left (primary) mouse button.
    case left

    /// The middle mouse button (commonly a scroll-wheel click).
    case middle

    /// The right (secondary) mouse button.
    case right

    /// Scroll wheel pushed upward (away from the user).
    case scrollUp

    /// Scroll wheel pulled downward (toward the user).
    case scrollDown

    /// Horizontal scroll to the left (trackpads / shifted wheel).
    case scrollLeft

    /// Horizontal scroll to the right.
    case scrollRight

    /// Carried for plain-motion events; no button is pressed.
    case none
}

// MARK: - Mouse Phase

/// The phase of a mouse interaction.
///
/// Terminals collapse the rich mouse lifecycle into three reporting
/// modes — press, release, and motion. TUIkit synthesises a `.dragged`
/// phase when motion arrives between a press and its matching release
/// for the same button, so views can treat drag-tracking the same way
/// they treat a regular sequence of move events.
public enum MousePhase: Sendable, Equatable {
    /// A button just went down.
    case pressed

    /// A button just went up.
    case released

    /// The cursor moved with no button pressed.
    case moved

    /// The cursor moved with at least one button held down.
    case dragged

    /// A scroll-wheel "tick" — no press/release pairs, the wheel emits
    /// a single tick at the cursor's current position.
    case scrolled
}

// MARK: - Mouse Event

/// A single mouse event reported by the terminal.
///
/// Positions are expressed in zero-indexed terminal cells with the
/// origin at the top-left corner of the rendered viewport (`x` increases
/// to the right, `y` downward).
public struct MouseEvent: Sendable, Equatable {
    /// The button (or wheel direction) the event refers to.
    public let button: MouseButton

    /// What the button is doing.
    public let phase: MousePhase

    /// Zero-indexed column.
    public let x: Int

    /// Zero-indexed row.
    public let y: Int

    /// Whether Shift was held when the event was generated.
    public let shift: Bool

    /// Whether Control was held.
    public let ctrl: Bool

    /// Whether Meta / Alt / Option was held.
    public let meta: Bool

    /// Creates a mouse event.
    public init(
        button: MouseButton,
        phase: MousePhase,
        x: Int,
        y: Int,
        shift: Bool = false,
        ctrl: Bool = false,
        meta: Bool = false
    ) {
        self.button = button
        self.phase = phase
        self.x = x
        self.y = y
        self.shift = shift
        self.ctrl = ctrl
        self.meta = meta
    }
}

// MARK: - SGR Parsing

extension MouseEvent {
    /// Parses one SGR-style mouse report into a `MouseEvent`.
    ///
    /// SGR encoding (XTerm 1006 extension) looks like:
    ///
    /// ```
    /// ESC [ < button ; column ; row M     (button down / motion)
    /// ESC [ < button ; column ; row m     (button up)
    /// ```
    ///
    /// where `button` is a packed code combining the button index
    /// (`0/1/2`), modifier bits (`+4` shift, `+8` meta, `+16` ctrl),
    /// the motion bit (`+32`), and the wheel-event bit (`+64`).
    ///
    /// Positions in the wire format are 1-indexed; the returned
    /// `MouseEvent` uses 0-indexed coordinates.
    ///
    /// - Parameter bytes: The full escape sequence, *including* the
    ///   leading `ESC [`.
    /// - Returns: A parsed event, or `nil` if the bytes are malformed
    ///   or not an SGR mouse report.
    public static func parseSGR(_ bytes: [UInt8]) -> MouseEvent? {
        // Minimum well-formed sequence: ESC [ < N ; N ; N M
        guard bytes.count >= 9 else { return nil }
        guard bytes[0] == 0x1B, bytes[1] == 0x5B, bytes[2] == 0x3C else { return nil }

        let terminator = bytes.last
        guard terminator == 0x4D /* M */ || terminator == 0x6D /* m */ else {
            return nil
        }
        let isRelease = (terminator == 0x6D)

        // Drop ESC, '[', '<' and the trailing terminator, then split on `;`.
        let payload = bytes.dropFirst(3).dropLast()
        let parts = payload.split(separator: 0x3B /* ';' */)
        guard parts.count == 3 else { return nil }
        guard let buttonCode = parseInt(parts[0]),
            let column = parseInt(parts[1]),
            let row = parseInt(parts[2])
        else {
            return nil
        }

        // Decode the packed button code into its component bits.
        let shift = (buttonCode & 4) != 0
        let meta = (buttonCode & 8) != 0
        let ctrl = (buttonCode & 16) != 0
        let isMotion = (buttonCode & 32) != 0
        let isWheel = (buttonCode & 64) != 0
        let buttonNumber = buttonCode & 3
        let horizontalWheel = (buttonCode & 128) != 0  // some terms use bit 7

        let button: MouseButton
        let phase: MousePhase

        if isWheel {
            phase = .scrolled
            if horizontalWheel {
                button = (buttonNumber == 0) ? .scrollLeft : .scrollRight
            } else {
                button = (buttonNumber == 0) ? .scrollUp : .scrollDown
            }
        } else if isMotion {
            switch buttonNumber {
            case 0: button = .left
            case 1: button = .middle
            case 2: button = .right
            default: button = .none
            }
            phase = (button == .none) ? .moved : .dragged
        } else {
            switch buttonNumber {
            case 0: button = .left
            case 1: button = .middle
            case 2: button = .right
            default:
                // 3 is reserved (used for legacy mode releases); SGR
                // releases are signalled by the lowercase 'm' terminator
                // instead, so we should never see button 3 here.
                return nil
            }
            phase = isRelease ? .released : .pressed
        }

        return MouseEvent(
            button: button,
            phase: phase,
            x: max(0, column - 1),
            y: max(0, row - 1),
            shift: shift,
            ctrl: ctrl,
            meta: meta
        )
    }

    /// Parses an ASCII decimal integer slice into an `Int`.
    private static func parseInt(_ slice: ArraySlice<UInt8>) -> Int? {
        var value = 0
        for byte in slice {
            guard byte >= 0x30, byte <= 0x39 else { return nil }
            value = value * 10 + Int(byte - 0x30)
        }
        return value
    }
}
