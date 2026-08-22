//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ButtonRow.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Button Row Helper

/// A horizontal row of buttons — the shape a ``Dialog``'s footer usually wants.
///
/// Each button receives its own focus identity, so `Tab` cycles between them and
/// only the focused one pulses. They are laid out from the leading edge with
/// `spacing` columns between them; any remaining width on the trailing side is
/// left empty.
///
/// # Example
///
/// ```swift
/// ButtonRow {
///     Button("Cancel") { dismiss() }
///     Button("OK") { confirm() }
/// }
/// ```
///
/// ## It takes views, not `Button` values
///
/// The content is an ordinary `@ViewBuilder`, so a button here can carry
/// modifiers — which is the difference between a footer button that can open
/// something and one that cannot:
///
/// ```swift
/// ButtonRow {
///     Button("Cancel") { dismiss() }
///     Button("Advanced…") { advanced = true }
///         .sheet(isPresented: $advanced) { Dialog(title: "Advanced") { … } }
///     Button("Export") { export() }
///         .contextMenu { Button("Export as CSV…") { exportCSV() } }
/// }
/// ```
///
/// This used to be a `@ButtonRowBuilder` taking `Button...`, and every one of
/// those examples was a compile error: `.sheet` and `.contextMenu` return
/// `some View`, not `Button`. A dialog's footer is exactly where a
/// "More options…" button belongs, so the restriction bit precisely where the
/// type is most used.
public struct ButtonRow<Content: View>: View {
    private let content: Content
    private let spacing: Int

    /// Creates a button row.
    ///
    /// - Parameters:
    ///   - spacing: The horizontal spacing between buttons (default: 2).
    ///   - content: The buttons to display.
    public init(spacing: Int = 2, @ViewBuilder _ content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    /// An `HStack`, which is what the hand-written core was: render each child
    /// at its own child identity, join them horizontally with `spacing`, and
    /// carry up what their buffers hold.
    ///
    /// Composed rather than re-implemented, so the row cannot drift from the
    /// stack — the previous core lifted hit-test regions and animated runs by
    /// hand and did not lift overlays, which is the whole reason a presentation
    /// in a footer would have been swallowed even once it could be written.
    /// `.top` because that is where the concatenation put a short button beside
    /// a tall one.
    public var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            content
        }
    }
}
