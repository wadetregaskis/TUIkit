//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MouseSupport.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Mouse Support

/// Which mouse features the app wants the terminal to report.
///
/// Terminals are an all-or-nothing prospect for mouse input *capture*:
/// once any tracking mode is active the terminal stops handing
/// mouse events to its own selection / link-handling behaviour and
/// instead pipes them straight to the program. ``MouseSupport``
/// gives you a way to be selective about which kinds of mouse
/// interactions the app cares about, so the rest can be passed to
/// the terminal's native handling.
///
/// ## What's possible
///
/// - **Disabled** (``disabled``): no mouse capture. Native text
///   selection, copy/paste, and link clicking all work as if the
///   app weren't running at all.
///
/// - **Scroll only**: the wheel scrolls a focused list / table /
///   scroll view but clicks and drags fall through to the terminal.
///   Note that on most terminals enabling any tracking mode also
///   captures clicks; users may still need to ``Shift``+click to
///   start a native text selection.
///
/// - **Standard** (``standard``): clicks, scrolling, and drag
///   tracking. Hover effects do **not** work — the terminal does
///   not report cursor motion without a button held.
///
/// - **Full** (``full``): everything including cursor motion. Use
///   this when you want hover highlights or live coordinate
///   read-outs. Motion floods the terminal with reports, so this
///   level is opt-in.
///
/// ## Adaptive elevation
///
/// View modifiers that genuinely need a higher level than the
/// configured one can request it on a per-frame basis (see
/// ``MouseEventDispatcher/requestFeature(_:)``). The dispatcher
/// takes the union of the configured base and any requested
/// features each frame, and emits a mode-change escape code only
/// when the effective set differs from the previous frame.
///
/// ## Native text selection
///
/// Most terminals support **Shift-click** (and Shift-drag) to
/// bypass the program's mouse capture and use the terminal's own
/// selection mechanism. iTerm2, Terminal.app and gnome-terminal
/// all do this by default. Document this for your users if you
/// keep mouse support enabled.
public struct MouseSupport: Sendable, Equatable {
    /// Whether to report mouse-button presses and releases.
    public var clicks: Bool

    /// Whether to report scroll-wheel events (vertical and horizontal).
    public var scrolling: Bool

    /// Whether to report drag motion while a button is held.
    public var drag: Bool

    /// Whether to report cursor motion regardless of button state.
    ///
    /// Required for hover effects. Floods the terminal with events
    /// — most apps should leave this off unless they specifically
    /// need it.
    public var motion: Bool

    /// Creates a mouse-support configuration.
    ///
    /// - Parameters:
    ///   - clicks: Report mouse button presses and releases.
    ///   - scrolling: Report scroll-wheel events.
    ///   - drag: Report drag motion while a button is held.
    ///   - motion: Report cursor motion regardless of button state.
    public init(
        clicks: Bool = false,
        scrolling: Bool = false,
        drag: Bool = false,
        motion: Bool = false
    ) {
        self.clicks = clicks
        self.scrolling = scrolling
        self.drag = drag
        self.motion = motion
    }

    /// No mouse capture — terminal native behaviour is fully preserved.
    public static let disabled = MouseSupport()

    /// Scroll-wheel only, no clicks or drag.
    public static let scrollOnly = MouseSupport(scrolling: true)

    /// Clicks, scrolling, and drag tracking — but no motion.
    ///
    /// This is the recommended default for most TUI apps. Hover
    /// effects require ``full``.
    public static let standard = MouseSupport(
        clicks: true, scrolling: true, drag: true)

    /// Everything including cursor-motion reporting.
    public static let full = MouseSupport(
        clicks: true, scrolling: true, drag: true, motion: true)
}

// MARK: - Effective Terminal Mode

extension MouseSupport {
    /// Whether *any* mouse feature is requested — used to decide
    /// whether to enable the SGR extended-coordinate report.
    var anyEnabled: Bool {
        clicks || scrolling || drag || motion
    }

    /// Returns the union of this configuration and another.
    ///
    /// Used per-frame to merge the base scene-level configuration
    /// with any feature-elevation requests posted by view modifiers
    /// during render.
    func union(with other: MouseSupport) -> MouseSupport {
        MouseSupport(
            clicks: clicks || other.clicks,
            scrolling: scrolling || other.scrolling,
            drag: drag || other.drag,
            motion: motion || other.motion
        )
    }
}
