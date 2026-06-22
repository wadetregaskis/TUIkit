//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ButtonRow.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Button Row Helper

/// A horizontal row of buttons.
///
/// Use this to display multiple buttons side by side with consistent spacing.
/// Each button receives its own focus identity so `Tab` cycles between them
/// and only the focused button pulses. Buttons are laid out from the
/// leading edge with `spacing` columns between them; any remaining width
/// on the trailing side is left empty.
///
/// # Example
///
/// ```swift
/// ButtonRow {
///     Button("Cancel") { dismiss() }
///     Button("OK") { confirm() }
/// }
/// ```
public struct ButtonRow: View {
    private let buttons: [Button]
    private let spacing: Int

    /// Creates a button row.
    ///
    /// - Parameters:
    ///   - spacing: The horizontal spacing between buttons (default: 2).
    ///   - buttons: The buttons to display.
    public init(spacing: Int = 2, @ButtonRowBuilder _ buttons: () -> [Button]) {
        self.spacing = spacing
        self.buttons = buttons()
    }

    public var body: some View {
        _ButtonRowCore(buttons: buttons, spacing: spacing)
    }
}

// MARK: - ButtonRow Builder

/// A result builder that constructs arrays of buttons for use in ``ButtonRow``.
///
/// `ButtonRowBuilder` enables the declarative syntax for defining multiple
/// buttons within a ``ButtonRow``. You don't use this type directly; instead,
/// the `@ButtonRowBuilder` attribute is applied to the trailing closure of
/// ``ButtonRow/init(spacing:_:)``.
///
/// ## Overview
///
/// When you write:
///
/// ```swift
/// ButtonRow {
///     Button("Cancel") { dismiss() }
///     Button("OK") { confirm() }
/// }
/// ```
///
/// The `@ButtonRowBuilder` attribute transforms this closure into an array
/// of ``Button`` instances that the row can lay out horizontally.
///
/// ## Supported Control Flow
///
/// The builder supports:
/// - Multiple button expressions
/// - `if`/`else` conditionals
/// - `if let` optional binding
/// - `for`...`in` loops
@resultBuilder
public struct ButtonRowBuilder {
    /// Combines multiple buttons into a single array.
    public static func buildBlock(_ buttons: Button...) -> [Button] {
        buttons
    }

    /// Combines an array of button arrays (from `for` loops).
    public static func buildArray(_ components: [[Button]]) -> [Button] {
        components.flatMap { $0 }
    }

    /// Handles optional button arrays (from `if` without `else`).
    public static func buildOptional(_ component: [Button]?) -> [Button] {
        component ?? []
    }

    /// Handles the first branch of an `if`/`else`.
    public static func buildEither(first component: [Button]) -> [Button] {
        component
    }

    /// Handles the second branch of an `if`/`else`.
    public static func buildEither(second component: [Button]) -> [Button] {
        component
    }
}

// MARK: - Internal Core View

/// Internal view that handles the actual rendering of ButtonRow.
private struct _ButtonRowCore: View, Renderable, Layoutable {
    let buttons: [Button]
    let spacing: Int

    var body: Never {
        fatalError("_ButtonRowCore renders via Renderable")
    }

    /// A button row is fixed: its fixed-width buttons sit left-aligned with
    /// `spacing` between them and it does not fill the remaining width, so a
    /// single render is its exact, fixed measure.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureFixedByRendering(self, proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard !buttons.isEmpty else {
            return FrameBuffer(lines: [])
        }

        // Render each button. Every button gets a unique child identity so
        // they each receive their own auto-generated focus ID and persisted
        // state — without that, every button in the row would resolve to the
        // same focus ID, so the focus system would treat them as a single
        // control: they would all pulse together and Tab could not move
        // focus between them.
        var buttonBuffers: [FrameBuffer] = []
        for (index, button) in buttons.enumerated() {
            let childContext = context.withChildIdentity(type: Button.self, index: index)
            let buffer = TUIkit.renderToBuffer(button, context: childContext)
            buttonBuffers.append(buffer)
        }

        // Find the maximum height
        let maxHeight = buttonBuffers.map { $0.height }.max() ?? 0

        // Combine horizontally (left-aligned — buttons stack from the leading
        // edge with `spacing` columns between them; any remaining width on
        // the right is left empty for the parent to fill or ignore).
        //
        // Each child buffer carries its own hit-test regions (registered by
        // the Button's mouse wiring); we shift those by the running x-offset
        // so clicks on individual buttons land on the right handler in the
        // composed row.
        var resultLines: [String] = Array(repeating: "", count: maxHeight)
        var resultRegions: [HitTestRegion] = []
        let spacer = String(repeating: " ", count: spacing)
        var xCursor = 0

        for (index, buffer) in buttonBuffers.enumerated() {
            if index > 0 {
                for lineIndex in 0..<maxHeight {
                    resultLines[lineIndex] += spacer
                }
                xCursor += spacing
            }
            for lineIndex in 0..<maxHeight {
                if lineIndex < buffer.height {
                    resultLines[lineIndex] += buffer.lines[lineIndex]
                } else {
                    resultLines[lineIndex] += String(repeating: " ", count: buffer.width)
                }
            }
            resultRegions.append(
                contentsOf: buffer.shiftedHitTestRegions(byX: xCursor, y: 0))
            xCursor += buffer.width
        }

        var result = FrameBuffer(lines: resultLines)
        result.hitTestRegions = resultRegions
        return result
    }
}
