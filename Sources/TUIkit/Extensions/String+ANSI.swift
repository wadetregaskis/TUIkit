//  🖥️ TUIkit — Terminal UI Kit for Swift
//  String+ANSI.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - Persistent Background

extension String {
    /// Applies a persistent background color that survives inner ANSI resets.
    ///
    /// If `color` is `nil`, the string is returned unchanged.
    ///
    /// - Parameter color: The background color, or `nil` for no change.
    /// - Returns: The string with persistent background applied, or unchanged if `color` is `nil`.
    func withPersistentBackground(_ color: Color?) -> String {
        guard let color else { return self }
        return ANSIRenderer.applyPersistentBackground(self, color: color)
    }
}

// MARK: - Styling a bare string

extension String {
    /// This string wrapped in the escape sequences that draw it with the given
    /// styling, self-contained and reset at the end.
    ///
    /// The escape hatch for code that assembles terminal cells directly — a
    /// `Renderable` view of your own, or the frames of an ``AnimatedCellRun``.
    /// Ordinary content should be a ``Text`` with the usual modifiers, which
    /// goes through the same renderer and additionally inherits the style
    /// cascade, the palette and the disabled state.
    ///
    /// Self-contained matters more than it looks: a frame handed to the run
    /// loop is spliced over the frame on screen without whatever escape
    /// preceded it, so a cell that leans on the styling of the cell before it
    /// draws in the wrong colour the moment it is replayed.
    ///
    /// ```swift
    /// let bullet = "●".styled(foreground: palette.accent)
    /// ```
    ///
    /// - Parameters:
    ///   - foreground: The text colour, or `nil` for the terminal's.
    ///   - background: The cell colour, or `nil` for the terminal's.
    ///   - bold: Whether to embolden it.
    ///   - underline: Whether to underline it.
    /// - Returns: The string with the escape sequences around it.
    public func styled(
        foreground: Color? = nil,
        background: Color? = nil,
        bold: Bool = false,
        underline: Bool = false
    ) -> String {
        ANSIRenderer.colorize(
            self, foreground: foreground, background: background, bold: bold,
            underline: underline)
    }
}
