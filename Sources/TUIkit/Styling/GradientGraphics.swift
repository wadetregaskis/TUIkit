//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GradientGraphics.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Whether a ramp may be a picture

private struct GradientGraphicsKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether a gradient that fills cells with nothing else in them is drawn
    /// as a picture, where the terminal draws pictures. See
    /// ``View/gradientGraphics(_:)``.
    public var gradientGraphics: Bool {
        get { self[GradientGraphicsKey.self] }
        set { self[GradientGraphicsKey.self] = newValue }
    }
}

extension View {

    /// Sets whether gradients within this view are drawn as pictures on a
    /// terminal that draws them.
    ///
    /// A gradient is painted one colour per cell: forty steps across a
    /// forty-cell bar, and a circle as a staircase. Where the terminal will
    /// place an image in its cell grid — the same handshake that decides
    /// ``View/terminalGraphics(_:)`` for ``Image`` — a ramp that fills cells
    /// with nothing else in them is sent as a picture instead: a
    /// ``LinearGradient`` used as a view, a `.background` behind blank cells,
    /// the fill of a ``ProgressView`` or ``Slider`` whose style is a solid
    /// block, and the indeterminate `.gradient` motion. One colour per pixel,
    /// no palette quantisation, and a boundary that lands on a pixel rather
    /// than a cell. Everything with a glyph in it keeps its glyphs: a shaded
    /// track, a braille ramp, text over a ramp — a picture cannot carry a
    /// character, and the terminal has the font.
    ///
    /// This is the preference. Availability is the handshake's, and it is
    /// ANDed with ``View/terminalGraphics(_:)``: turning pictures off for a
    /// subtree turns ramp pictures off with them.
    ///
    /// ```swift
    /// ProgressView(value: 0.4)
    ///     .progressViewStyle(.gradient)
    ///     .gradientGraphics(false)   // the cells are the look
    /// ```
    ///
    /// - Parameter enabled: Whether ramps use the terminal's graphics
    ///   protocol where it has one (default `true`).
    /// - Returns: A view whose gradients honour the setting.
    public func gradientGraphics(_ enabled: Bool = true) -> some View {
        environment(\.gradientGraphics, enabled)
    }
}

// MARK: - What a picture of a ramp needs from its context

/// Everything a renderer needs to draw a ramp as a picture — where to keep
/// it, who owns it, how big a cell is — or `nil`, which is the answer for
/// every frame that draws cells: no graphics, a measure pass, the preference
/// off, or no store to put a picture in.
///
/// Asking for one also registers the picture's lifetime: the token is
/// recorded as appeared for this pass, and its disappearance releases the
/// image, exactly as ``Image`` does for its own. So a caller that gets a
/// non-`nil` answer has nothing to clean up, and a caller that renders cells
/// this frame — whose token is therefore not recorded — has its picture freed
/// at the end of the pass, which is the right answer for a view that stopped
/// being a ramp.
struct GradientGraphicsContext {
    let store: TerminalImageStore
    let token: String
    let cellPixels: TerminalCellPixels
    /// How many pictures the owner holds under this token — one, or a cycle
    /// of them for a moving ramp.
    let frames: Int

    /// The store token for frame `index` of a cycle; the token itself for a
    /// single picture.
    func token(forFrame index: Int) -> String {
        Self.token(token, forFrame: index, of: frames)
    }

    /// The store token for frame `index` of a cycle of `frames` pictures owned by
    /// `token`, without a context to ask.
    ///
    /// For an owner giving back pictures a context no longer describes: the
    /// spelling depends on the count, so a token has to be spelled with the count
    /// it was put in the store under, not the count the owner has now.
    static func token(_ token: String, forFrame index: Int, of frames: Int) -> String {
        frames == 1 ? token : "\(token)/\(index)"
    }
}

extension RenderContext {
    /// The graphics context for a ramp picture owned by `token`, or `nil`
    /// when this frame draws cells. See ``GradientGraphicsContext``.
    ///
    /// Reads the flags in cost order — the process-wide support answer first,
    /// which is `false` on most terminals and costs nothing — so a page full
    /// of gradients on a glyph terminal pays one static read per ramp.
    func gradientGraphics(token: String, frames: Int = 1) -> GradientGraphicsContext? {
        guard KittyGraphics.isSupported, !isMeasuring,
            environment.terminalGraphics, environment.gradientGraphics,
            let store = environment.terminalImageStore
        else { return nil }
        let graphics = GradientGraphicsContext(
            store: store, token: token, cellPixels: environment.imageCellPixels, frames: frames)
        // A subtree whose cells name an image is a subtree the memo cannot
        // serve from a cached buffer once the image is gone — the same
        // declaration `_ImageCore` makes.
        environment.volatileReadTracker?.recordRenderSideEffect()
        if let lifecycle = environment.lifecycle {
            _ = lifecycle.recordAppear(token: token) {}
            lifecycle.registerDisappear(token: token) {
                for index in 0..<max(1, frames) { store.release(token: graphics.token(forFrame: index)) }
            }
        }
        return graphics
    }
}
