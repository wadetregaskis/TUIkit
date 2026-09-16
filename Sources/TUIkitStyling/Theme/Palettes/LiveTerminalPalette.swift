//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LiveTerminalPalette.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - The Terminal's Own Colours

/// The palette that names no colour of its own: every role is a colour the user's
/// terminal decides.
///
/// The other sixteen built-ins state sRGB values — a phosphor green, Terminal.app's
/// "Homebrew" — and paint them whatever the host is set to. This one states the
/// terminal's own vocabulary instead, so an app drawn with it looks like the rest of
/// the user's terminal and follows their profile when they change it:
///
/// | Role | Value |
/// |---|---|
/// | ``Palette/background``, ``Palette/statusBarBackground``, ``Palette/appHeaderBackground`` | ``Color/clear``: the terminal's own page, SGR 49 |
/// | ``Palette/overlayBackground``, ``Palette/foreground`` | ``Color/default``: SGR 39 as ink, 49 as a fill |
/// | ``Palette/foregroundSecondary`` / ``Palette/foregroundTertiary`` / ``Palette/foregroundQuaternary`` | ``Color/default`` at 75%, 55% and 38% |
/// | ``Palette/accent`` | ``Color/ansi(_:)`` blue, and ``Palette/cursorColor`` with it |
/// | ``Palette/success`` / ``Palette/warning`` / ``Palette/error`` / ``Palette/info`` | ``Color/ansi(_:)`` green / yellow / red / cyan |
/// | ``Palette/border`` | ``Color/ansi(_:)`` bright black |
///
/// The grounds are ``Color/clear`` rather than ``Color/default`` because a ground at
/// alpha 0 *is* whatever is behind it, and nothing is behind an app's page but the
/// terminal: both spellings end up as the terminal's own background, and `.clear` says
/// why. ``Palette/focusBackground`` and ``Palette/fieldBackground`` are left to their
/// derived defaults, which step off that page once it is known.
///
/// ## What it looks like before the terminal answers
///
/// TUIkit asks the terminal for its colours at startup (OSC 10, 11 and 4). A host that
/// does not answer — GNU screen, and Warp for its sixteen slots — leaves every one of
/// these roles *unmeasurable*: a colour with no RGB cannot be dimmed, tinted, blended or
/// checked for contrast. The framework then draws what it can state exactly rather than
/// guessing a value:
///
/// - the three text tiers are the terminal's plain foreground, SGR 39, undimmed;
/// - a control's face is the page, so it shows nothing, and a hover lifts the label's
///   ink up the ladder of names instead of tinting a fill;
/// - a highlight that would have been a tint — a cursor row, a text selection, a menu's
///   highlight bar — is drawn in reverse video over the palette's own pair;
/// - a focus breath holds still at its bright end.
///
/// Once the terminal answers, every one of those measures and the palette behaves like
/// any other: the tiers dim toward the reported page, faces are tints again and the
/// highlights are fills. The colours are still *emitted* as slots and 39/49, so they keep
/// following the user's profile; the report only says what they paint. See
/// `Documentation/Opacity as composition.md` §75–§91 and
/// `Documentation/Terminal-compatibility.md`.
///
/// ```swift
/// WindowGroup { ContentView() }
///     .palette(LiveTerminalPalette())
/// ```
public struct LiveTerminalPalette: Palette, Hashable {

    /// The palette's identifier, `"terminal.live"`.
    public let id = "terminal.live"

    /// The palette's display name, `"Terminal"`.
    public let name = "Terminal"

    // The three root grounds. Nothing inside the app is behind them, so at alpha 0 they
    // are the terminal's own page, and the framework spells them SGR 49.
    public let background = Color.clear
    public let statusBarBackground = Color.clear
    public let appHeaderBackground = Color.clear

    // Not a root: a modal's wash has the page behind it and keeps its alpha, so this is
    // stated as the terminal's own colour rather than as a clear ground.
    public let overlayBackground = Color.default

    // The text ladder. The dimmer tiers are shares of the same colour, which resolve
    // against whatever page the terminal reports — and are its plain foreground until
    // it reports one.
    public let foreground = Color.default
    public let foregroundSecondary = Color.default.opacity(0.75)
    public let foregroundTertiary = Color.default.opacity(0.55)
    public let foregroundQuaternary = Color.default.opacity(0.38)

    // The sixteen slots, by their conventional meanings: the accent is the terminal's
    // blue, and the status roles are the colours a terminal user already reads as
    // "good", "careful", "wrong" and "for information".
    public let accent = Color.ansi(.blue)
    public let success = Color.ansi(.green)
    public let warning = Color.ansi(.yellow)
    public let error = Color.ansi(.red)
    public let info = Color.ansi(.cyan)

    // Chrome: the slot every terminal theme keeps between its page and its text.
    public let border = Color.ansi(.brightBlack)

    /// Creates the palette. It has no options: every colour in it belongs to the
    /// terminal.
    public init() {}
}
