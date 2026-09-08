//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StepperHandler.swift
//
//  Created by LAYERED.work
//  License: MIT

/// The value-type-erased surface of a stepper's focus handler.
///
/// This lets ``Stepper`` and `_StepperCore` stay non-generic over the value
/// type `V` — matching SwiftUI's `Stepper<Label>`, which also erases `V` — while
/// still driving the generic ``StepperHandler`` for keyboard/mouse stepping.
/// The one `V`-typed piece (the value binding) is refreshed separately through
/// a closure captured where `V` is statically known.
protocol StepperDriving: Focusable {
    var canBeFocused: Bool { get set }
    var shiftStepMultiplier: Int { get set }
    var onIncrement: (() -> Void)? { get set }
    var onDecrement: (() -> Void)? { get set }
    var onEditingChanged: ((Bool) -> Void)? { get set }
    func increment(times: Int)
    func decrement(times: Int)
    func clampValue()
    /// See ``StepperHandler/beginEditingIfNeeded()`` — a requirement so the
    /// view's mouse closure, which holds this existential rather than the
    /// concrete handler, can report the gesture it is driving.
    func beginEditingIfNeeded()
    func endEditingIfNeeded()
}

/// A focus handler for stepper components.
///
/// `StepperHandler` manages value changes and keyboard input for `Stepper`.
/// It handles:
/// - Increment/decrement via arrow keys or +/-
/// - Jump to min/max via Home/End (when bounds are defined)
/// - Clamping values to the defined range
///
/// ## Keyboard Controls
///
/// | Key | Action |
/// |-----|--------|
/// | `->` or `+` | Increment by step |
/// | `<-` or `-` | Decrement by step |
/// | `Home` | Jump to minimum (if bounds defined) |
/// | `End` | Jump to maximum (if bounds defined) |
final class StepperHandler<V: Strideable>: PersistedFocusable where V.Stride: SignedNumeric {
    /// The unique identifier for this focusable element.
    var focusID: String

    /// The binding to the current value.
    var value: Binding<V>

    /// The optional range of valid values.
    ///
    /// Mutable because the handler PERSISTS across renders while the view's
    /// declared range may not: a `Stepper(value:in:)` whose range derives
    /// from other state (e.g. a ceiling that depends on a mode picker) must
    /// clamp against the range the CURRENT render declared, not the one in
    /// force when the handler was first created. Refreshed every render via
    /// `syncValue` alongside the value binding.
    var bounds: ClosedRange<V>?

    /// The step size for increment/decrement. Mutable for the same reason
    /// as ``bounds``.
    var step: V.Stride

    /// How many steps a Shift-accelerated arrow press takes. Set from
    /// `environment.shiftStepMultiplier` during render (default 5); a plain arrow
    /// (and the `+`/`-` keys) take one. See ``View/shiftStepMultiplier(_:)``.
    var shiftStepMultiplier: Int = 5

    /// Whether this element can currently receive focus.
    var canBeFocused: Bool

    /// Callback triggered when increment is requested.
    var onIncrement: (() -> Void)?

    /// Callback triggered when decrement is requested.
    var onDecrement: (() -> Void)?

    /// Callback triggered when editing begins or ends.
    ///
    /// A span, not an event: a pointer HOLD on an arrow (press to release), a wheel notch, or an
    /// arrow key. The pointer's span ends with its
    /// release; a wheel notch and a key have no release, so theirs ends when
    /// the control loses focus. Idempotent at both edges — see
    /// ``beginEditingIfNeeded()``.
    var onEditingChanged: ((Bool) -> Void)?

    /// Whether the stepper is currently being edited.
    private var isEditing = false

    /// Creates a stepper handler with a value binding.
    ///
    /// - Parameters:
    ///   - focusID: The unique focus identifier.
    ///   - value: The binding to the current value.
    ///   - bounds: The optional range of valid values.
    ///   - step: The step size for changes.
    ///   - canBeFocused: Whether this element can receive focus. Defaults to `true`.
    init(
        focusID: String,
        value: Binding<V>,
        bounds: ClosedRange<V>? = nil,
        step: V.Stride,
        canBeFocused: Bool = true
    ) {
        self.focusID = focusID
        self.value = value
        self.bounds = bounds
        self.step = step
        self.canBeFocused = canBeFocused
    }

    /// Creates a stepper handler with custom increment/decrement callbacks.
    ///
    /// - Parameters:
    ///   - focusID: The unique focus identifier.
    ///   - onIncrement: Callback when increment is requested.
    ///   - onDecrement: Callback when decrement is requested.
    ///   - canBeFocused: Whether this element can receive focus. Defaults to `true`.
    init(
        focusID: String,
        onIncrement: (() -> Void)?,
        onDecrement: (() -> Void)?,
        canBeFocused: Bool = true
    ) where V: ExpressibleByIntegerLiteral, V.Stride: ExpressibleByIntegerLiteral {
        self.focusID = focusID
        // Create a dummy binding that does nothing
        var dummy: V?
        self.value = Binding(
            get: { dummy ?? 0 },
            set: { dummy = $0 }
        )
        self.bounds = nil
        self.step = 1
        self.canBeFocused = canBeFocused
        self.onIncrement = onIncrement
        self.onDecrement = onDecrement
    }
}

// MARK: - Key Event Handling

extension StepperHandler {
    func handleKeyEvent(_ event: KeyEvent) -> Bool {
        // Holding Shift with an arrow steps by the (env-configured) multiplier,
        // for coarse adjustment. (Only the arrow keys carry an explicit Shift
        // flag from the terminal; `+`/`-` don't, so they keep the single step.)
        let times = event.shift ? max(1, shiftStepMultiplier) : 1
        switch event.key {
        case .right, .character("+"), .character("="):
            beginEditingIfNeeded()
            increment(times: times)
            return true

        case .left, .character("-"), .character("_"):
            beginEditingIfNeeded()
            decrement(times: times)
            return true

        case .home:
            if bounds != nil {
                beginEditingIfNeeded()
                jumpToMinimum()
                return true
            }
            return false

        case .end:
            if bounds != nil {
                beginEditingIfNeeded()
                jumpToMaximum()
                return true
            }
            return false

        default:
            return false
        }
    }
}

// MARK: - Value Manipulation

extension StepperHandler {
    /// Increments the value by `times` step sizes (default one). Stepping one at a
    /// time clamps to `bounds` at each move and fires `onIncrement` per step, so a
    /// Shift-accelerated press behaves exactly like that many ordinary presses.
    func increment(times: Int = 1) {
        for _ in 0..<max(1, times) {
            if let onIncrement {
                onIncrement()
            } else if let bounds {
                // Saturate, then clamp — this does NOT test for overshoot
                // first, as it used to. That guard pivoted off the BOUND
                // (`upperBound - step`), which is trapping arithmetic in its
                // own right: it underflowed whenever the ceiling sat within
                // `step` of the type's MINIMUM, and on an unsigned value type
                // an ordinary `0...2` with `step: 5` was enough. Saturating
                // costs nothing here because a sum that saturated is past
                // every representable bound, so it and the true
                // (unrepresentable) sum clamp to the same answer. The final
                // `min`/`max` still pins the bound and neutralises a NaN value
                // the way it always did.
                let candidate = value.wrappedValue.advancedSaturating(by: step)
                value.wrappedValue = max(bounds.lowerBound, min(bounds.upperBound, candidate))
            } else {
                // Unbounded, so there is no clamp to fall back on: saturating
                // is the whole answer, and pins a value already at the type's
                // extreme instead of trapping on the press.
                value.wrappedValue = value.wrappedValue.advancedSaturating(by: step)
            }
        }
    }

    /// Decrements the value by `times` step sizes (default one). See ``increment(times:)``.
    func decrement(times: Int = 1) {
        let negativeStep = V.Stride.zero - step
        for _ in 0..<max(1, times) {
            if let onDecrement {
                onDecrement()
            } else if let bounds {
                // Mirror of `increment`: a step that runs off the bottom of
                // the type saturates at the type's minimum, which is at or
                // below `lowerBound`, so the clamp lands on the floor. The
                // final `min`/`max` also pulls an out-of-range-high value back
                // into bounds and neutralises NaN, exactly as before.
                let candidate = value.wrappedValue.advancedSaturating(by: negativeStep)
                value.wrappedValue = min(bounds.upperBound, max(bounds.lowerBound, candidate))
            } else {
                value.wrappedValue = value.wrappedValue.advancedSaturating(by: negativeStep)
            }
        }
    }

    /// Jumps to the minimum value.
    func jumpToMinimum() {
        guard let bounds else { return }
        value.wrappedValue = bounds.lowerBound
    }

    /// Jumps to the maximum value.
    func jumpToMaximum() {
        guard let bounds else { return }
        value.wrappedValue = bounds.upperBound
    }

    /// Clamps the current value to the bounds.
    func clampValue() {
        guard let bounds else { return }
        if value.wrappedValue < bounds.lowerBound {
            value.wrappedValue = bounds.lowerBound
        } else if value.wrappedValue > bounds.upperBound {
            value.wrappedValue = bounds.upperBound
        }
    }
}

// MARK: - Overflow-Safe Stepping

extension Strideable where Stride: SignedNumeric {
    /// `advanced(by:)` with the value type's own extremes as a floor and
    /// ceiling instead of a trap.
    ///
    /// This is NOT the stepper's bounds clamp — the caller still pins the
    /// result to its `bounds`; this is the arithmetic underneath that clamp.
    /// `advanced(by:)` on a fixed-width integer is ordinary trapping addition,
    /// so a sum landing past the type's maximum kills the process before there
    /// is a number left to clamp. Saturating first loses nothing: a sum that
    /// saturated is past every representable bound, so it and the true
    /// (unrepresentable) sum clamp to the same answer.
    ///
    /// The runtime cast is what finds the trapping types, and a `where` clause
    /// could not: the stepper's value type is only known to be `Strideable`,
    /// and Swift picks between protocol-extension overloads at compile time,
    /// so a `where Self: FixedWidthInteger` twin would never be the one that
    /// generic context calls. Types whose arithmetic cannot trap (`Double`,
    /// `Date`, …) take the plain `advanced(by:)` — as does a fixed-width
    /// integer with a custom `Stride`, which no standard integer type has.
    ///
    /// - Parameter n: How far to advance, as for `advanced(by:)`.
    /// - Returns: The advanced value, or the nearer of the type's extremes
    ///   when that value is not representable.
    fileprivate func advancedSaturating(by n: Stride) -> Self {
        guard let integer = self as? any FixedWidthInteger, let step = n as? Int,
            let saturated = integer.addingSaturating(step) as? Self
        else { return advanced(by: n) }
        return saturated
    }
}

extension FixedWidthInteger {
    /// `self + n` with this type's extremes as a floor and ceiling.
    ///
    /// A step too large for the type to even hold (an `Int8` stepped by 1000)
    /// saturates for the same reason an overflowing sum does: the true result
    /// is past the extreme the step points at.
    fileprivate func addingSaturating(_ n: Int) -> Self {
        guard let delta = Self(exactly: n) else { return n > 0 ? .max : .min }
        let (sum, overflow) = addingReportingOverflow(delta)
        guard overflow else { return sum }
        return n > 0 ? .max : .min
    }
}

// MARK: - Editing State

extension StepperHandler {
    /// Begins editing if not already editing.
    ///
    /// Internal rather than private because the POINTER path has to reach it —
    /// see the twin note on ``SliderHandler/beginEditingIfNeeded()``. SwiftUI's
    /// wording for a `Stepper` is "the user may touch and hold the increment or
    /// decrement button", which is a press and a release, and `Stepper` drives
    /// those from its own mouse closure rather than through here.
    func beginEditingIfNeeded() {
        guard !isEditing else { return }
        isEditing = true
        onEditingChanged?(true)
    }

    /// Ends editing if currently editing.
    func endEditingIfNeeded() {
        guard isEditing else { return }
        isEditing = false
        onEditingChanged?(false)
    }
}

// MARK: - Focus Lifecycle

extension StepperHandler {
    func onFocusReceived() {
        clampValue()
    }

    func onFocusLost() {
        endEditingIfNeeded()
    }
}

// MARK: - Value-type-erased driving

/// All requirements are met by `StepperHandler`'s existing members (including
/// `increment(times:)`/`decrement(times:)`, whose default `times` argument still
/// satisfies the non-defaulted protocol requirement).
extension StepperHandler: StepperDriving {}
