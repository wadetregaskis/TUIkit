//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Image+TerminalGraphics.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Real pixels, where the terminal has them

/// A terminal cell's size in pixels, as the terminal reports it.
///
/// The sibling of ``EnvironmentValues/imageCellAspect``, which is this
/// divided out — and the reason both exist is that they answer different
/// questions. The *aspect* stops a circle looking like an ellipse and is
/// needed by every gradient and glyph-drawn image, so it has a sane default
/// and never needs to be right. The *size* decides how many real pixels an
/// image is transmitted with, so being wrong costs sharpness rather than
/// shape.
public struct TerminalCellPixels: Equatable, Sendable {
    /// A cell's width in pixels.
    public var width: Int
    /// A cell's height in pixels.
    public var height: Int

    /// Creates a cell size, clamped to at least one pixel each way.
    public init(width: Int, height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
    }
}

private struct TerminalCellPixelsKey: EnvironmentKey {
    /// A plausible cell on an unscaled display, used where the terminal
    /// reports no pixel size. Transmitting at the wrong resolution is a
    /// quality question and not a correctness one — a virtual placement
    /// declares its size in CELLS, and the terminal scales the picture to
    /// fill them — so a terminal that will not say gets a reasonable guess
    /// rather than no image.
    static let defaultValue = TerminalCellPixels(width: 8, height: 16)
}

private struct TerminalGraphicsKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {

    /// The terminal cell's size in pixels, published at startup from
    /// `TIOCGWINSZ`. Used to decide how many real pixels an ``Image`` is
    /// transmitted with.
    public var imageCellPixels: TerminalCellPixels {
        get { self[TerminalCellPixelsKey.self] }
        set { self[TerminalCellPixelsKey.self] = newValue }
    }

    /// Whether ``Image`` draws with the terminal's own graphics protocol where
    /// one is available. Set via ``View/terminalGraphics(_:)``. Default:
    /// `true` — which still draws glyphs on every terminal that did not answer
    /// the startup handshake, because the two conditions are ANDed (see
    /// ``TUIkitCore/KittyGraphics/isSupported``).
    public var terminalGraphics: Bool {
        get { self[TerminalGraphicsKey.self] }
        set { self[TerminalGraphicsKey.self] = newValue }
    }
}

extension View {

    /// Sets whether ``Image`` views within this view draw with the terminal's
    /// own graphics protocol.
    ///
    /// Where the terminal will place an image in its cell grid, TUIkit draws
    /// the real picture — roughly fifty times the pixels of the glyph
    /// renderer, in full colour, with no palette quantisation and no contrast
    /// floor. Where it will not, nothing changes: the glyph renderer draws
    /// what it always drew. The handshake at startup is what decides, so this
    /// modifier is about **preference**, not availability.
    ///
    /// Turn it off for a subtree that wants the glyphs on purpose — and that
    /// is a real want, not only a fallback. A dashboard built around
    /// ``ASCIICharacterSet/blocks(_:)`` or a `.customRamp` has a look, and an
    /// app should not have that look change on exactly the terminals that can
    /// draw a photograph:
    ///
    /// ```swift
    /// Image(.file("logo.png"))
    ///     .imageCharacterSet(.blocks(.halves))
    ///     .terminalGraphics(false)   // the ramp IS the design
    /// ```
    ///
    /// - Parameter enabled: Whether images use the terminal's graphics
    ///   protocol where it has one (default `true`).
    /// - Returns: A view whose images honour the setting.
    public func terminalGraphics(_ enabled: Bool = true) -> some View {
        environment(\.terminalGraphics, enabled)
    }

    /// Sets the terminal cell's pixel size for the subtree — what an
    /// ``Image`` is resampled to before it is handed to the terminal.
    ///
    /// Published automatically at startup from `TIOCGWINSZ`, which all four
    /// measured hosts answer. Override it for a terminal that reports nothing
    /// or reports nonsense; the sibling ``View/imageCellAspect(_:)`` is the
    /// one to reach for if the problem is that pictures look *stretched*
    /// rather than *soft*.
    ///
    /// - Parameter pixels: The cell's size.
    /// - Returns: A modified view.
    public func imageCellPixels(_ pixels: TerminalCellPixels) -> some View {
        environment(\.imageCellPixels, pixels)
    }
}
