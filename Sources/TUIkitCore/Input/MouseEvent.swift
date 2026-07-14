//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MouseEvent.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Mouse Button

/// Which mouse button (or wheel direction) generated an event.
public enum MouseButton: Sendable, Equatable {
    /// Whether this button identifies a scroll-wheel event
    /// (vertical or horizontal). Used by the dispatcher to
    /// decide whether to bubble unhandled events out to a
    /// containing region — a scrolling Stepper / List /
    /// ScrollView should still scroll when the cursor lands on
    /// top of a child control that doesn't itself handle the
    /// wheel.
    public var isWheel: Bool {
        switch self {
        case .scrollUp, .scrollDown, .scrollLeft, .scrollRight:
            return true
        default:
            return false
        }
    }

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

    /// Synthetic phase: the cursor just entered a region whose
    /// handler is registered. Emitted by `MouseEventDispatcher`
    /// in response to a `.moved` event that transitioned the
    /// cursor onto a different region from where it was before.
    /// No corresponding raw terminal event — the dispatcher
    /// owns the enter / exit state machine.
    case entered

    /// Synthetic phase: the cursor just left a region whose
    /// handler is still registered. Fires alongside `.entered`
    /// on the new region. Same notes as `.entered`.
    case exited
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

    /// How many clicks this event is part of: `1` for a single click, `2` for
    /// the second click of a double-click, and so on.
    ///
    /// Terminals never report this — `MouseEventDispatcher` synthesises it by
    /// timing successive presses/releases of the same button at (near) the same
    /// cell. Parsed events default to `1`; the count is stamped on during
    /// dispatch. Read it via ``TUIkitView/View/onTapGesture(count:perform:)``.
    public let clickCount: Int

    /// Creates a mouse event.
    public init(
        button: MouseButton,
        phase: MousePhase,
        x: Int,
        y: Int,
        shift: Bool = false,
        ctrl: Bool = false,
        meta: Bool = false,
        clickCount: Int = 1
    ) {
        self.button = button
        self.phase = phase
        self.x = x
        self.y = y
        self.shift = shift
        self.ctrl = ctrl
        self.meta = meta
        self.clickCount = clickCount
    }

    /// Returns a copy of this event with its ``clickCount`` replaced.
    public func withClickCount(_ count: Int) -> Self {
        Self(
            button: button, phase: phase, x: x, y: y,
            shift: shift, ctrl: ctrl, meta: meta, clickCount: count)
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

        guard let (button, phase) = decodeSGRButton(
            buttonCode: buttonCode, isRelease: isRelease
        ) else {
            return nil
        }

        return MouseEvent(
            button: button,
            phase: phase,
            x: max(0, column - 1),
            y: max(0, row - 1),
            shift: (buttonCode & 4) != 0,
            ctrl: (buttonCode & 16) != 0,
            meta: (buttonCode & 8) != 0
        )
    }

    /// Decodes the packed SGR button code into the
    /// `(MouseButton, MousePhase)` pair it describes. Returns
    /// `nil` for codes that don't correspond to any TUIkit
    /// event shape — notably button index 3 in a non-release
    /// position, which is reserved for legacy-mode releases and
    /// shouldn't appear in SGR reports.
    private static func decodeSGRButton(
        buttonCode: Int, isRelease: Bool
    ) -> (MouseButton, MousePhase)? {
        let isMotion = (buttonCode & 32) != 0
        let isWheel = (buttonCode & 64) != 0
        let horizontalWheel = (buttonCode & 128) != 0  // some terms use bit 7
        let buttonNumber = buttonCode & 3

        if isWheel {
            return (decodeSGRWheel(
                buttonNumber: buttonNumber,
                horizontal: horizontalWheel
            ), .scrolled)
        }
        if isMotion {
            let button = decodeSGRMotionButton(buttonNumber: buttonNumber)
            return (button, button == .none ? .moved : .dragged)
        }
        guard let button = decodeSGRClickButton(buttonNumber: buttonNumber)
        else {
            return nil
        }
        return (button, isRelease ? .released : .pressed)
    }

    /// Wheel events split four ways: vertical / horizontal, up
    /// / down (or left / right).
    ///
    /// In the standard xterm encoding the wheel AXIS lives in the low
    /// button bits alongside the direction: within the wheel group
    /// (bit 6), buttons 0/1 are vertical up/down and buttons 2/3 are
    /// horizontal left/right — `64`…`67` unshifted. iTerm2 and
    /// Terminal.app both use this form (measured: macOS translates
    /// Shift+wheel into horizontal wheel deltas, so iTerm2 reports
    /// Shift+wheel as `66`/`67` (+4 for Shift)). Decoding buttons 2/3
    /// as vertical (as this once did) collapsed BOTH horizontal
    /// directions into `.scrollDown`, which the shift-scrolls-
    /// horizontally convention then mapped to "right" — every
    /// Shift+wheel tick scrolled right regardless of direction.
    /// The bit-7 (`+128`) horizontal form some terminals use is
    /// still honoured.
    private static func decodeSGRWheel(
        buttonNumber: Int, horizontal: Bool
    ) -> MouseButton {
        if horizontal {
            return buttonNumber == 0 ? .scrollLeft : .scrollRight
        }
        switch buttonNumber {
        case 0: return .scrollUp
        case 1: return .scrollDown
        case 2: return .scrollLeft
        default: return .scrollRight
        }
    }

    /// Bare-cursor motion or drag — same button-index mapping as
    /// a click but `.none` for "no button held" so the dispatcher
    /// can distinguish `.moved` from `.dragged`.
    private static func decodeSGRMotionButton(buttonNumber: Int) -> MouseButton {
        switch buttonNumber {
        case 0: return .left
        case 1: return .middle
        case 2: return .right
        default: return .none
        }
    }

    /// Click events: button index 0 / 1 / 2 map to left / middle
    /// / right. Index 3 is reserved (used for legacy-mode
    /// releases); SGR releases are signalled by the `m`
    /// terminator instead, so we should never see it here.
    private static func decodeSGRClickButton(buttonNumber: Int) -> MouseButton? {
        switch buttonNumber {
        case 0: return .left
        case 1: return .middle
        case 2: return .right
        default: return nil
        }
    }

    /// Parses one X10-style ("legacy") mouse report into a `MouseEvent`.
    ///
    /// Legacy encoding (predates SGR) looks like:
    ///
    /// ```
    /// ESC [ M <button+32> <x+32> <y+32>
    /// ```
    ///
    /// Six bytes total. Each of button-code, column, and row is
    /// encoded as `value + 32` and may sit anywhere in 0x20…0xFF,
    /// which limits the legacy form to roughly column / row 223.
    /// (TUIkit asks the terminal for SGR encoding via `?1006h`, but
    /// some terminals — notably Apple's Terminal.app — fall back to
    /// X10 reports anyway on certain events.)
    ///
    /// The button code carries the same bit layout as the SGR form:
    /// `+4` shift, `+8` meta, `+16` ctrl, `+32` motion, `+64` wheel,
    /// `+128` horizontal-wheel.
    ///
    /// - Parameter bytes: The full six-byte sequence, *including* the
    ///   leading `ESC [ M`.
    /// - Returns: A parsed event, or `nil` if the bytes are malformed.
    public static func parseLegacy(_ bytes: [UInt8]) -> MouseEvent? {
        guard bytes.count == 6 else { return nil }
        guard bytes[0] == 0x1B, bytes[1] == 0x5B, bytes[2] == 0x4D /* M */ else { return nil }

        // The +32 bias makes every coord byte at least 0x20 (space).
        // Treat values below that as malformed.
        guard bytes[3] >= 0x20, bytes[4] >= 0x20, bytes[5] >= 0x20 else { return nil }
        let buttonCode = Int(bytes[3]) - 32
        let column = Int(bytes[4]) - 32
        let row = Int(bytes[5]) - 32

        // Legacy mouse has no separate release encoding — button code 3
        // is reused for "any release". We don't see uppercase-M vs
        // lowercase-m in this format, so the release is signalled by
        // button 3.
        let shift = (buttonCode & 4) != 0
        let meta = (buttonCode & 8) != 0
        let ctrl = (buttonCode & 16) != 0
        let isMotion = (buttonCode & 32) != 0
        let isWheel = (buttonCode & 64) != 0
        let buttonNumber = buttonCode & 3
        let horizontalWheel = (buttonCode & 128) != 0

        let button: MouseButton
        let phase: MousePhase

        if isWheel {
            phase = .scrolled
            // Same axis-in-the-button-bits layout as the SGR form: see
            // `decodeSGRWheel` — buttons 2/3 within the wheel group are
            // the standard horizontal left/right.
            button = decodeSGRWheel(buttonNumber: buttonNumber, horizontal: horizontalWheel)
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
            case 3:
                // "Any release" in legacy encoding — we don't know
                // which button was released. Default to .left, which
                // is the common case the dispatcher's drag-capture
                // logic can route correctly.
                return MouseEvent(
                    button: .left, phase: .released,
                    x: max(0, column - 1), y: max(0, row - 1),
                    shift: shift, ctrl: ctrl, meta: meta
                )
            default: return nil
            }
            phase = .pressed
        }

        return MouseEvent(
            button: button, phase: phase,
            x: max(0, column - 1), y: max(0, row - 1),
            shift: shift, ctrl: ctrl, meta: meta
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
