//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LinkDisplay.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - How a link shows where it goes

/// How a ``Link`` reveals its destination.
///
/// A link in a terminal has a problem a link in a browser does not: **the
/// application cannot reliably open it.** `OpenURLAction` runs the system
/// opener on the machine the app is running on, which over ssh is the server —
/// the wrong browser, or on a headless box no browser at all. And a terminal
/// that honours OSC 8 opens a link only on a gesture it chooses (iTerm2:
/// ⌘-click), which a keyboard user never makes. So the destination has to be
/// something the user can *see and copy*, not only something the app promises
/// to act on.
///
/// This is the knob for that, because there is no single right answer:
/// showing every URL inline is noise on a page of prose, and hiding every URL
/// is a problem on a terminal that cannot linkify one.
///
/// TUI-specific. SwiftUI's `Link` has no equivalent, because a browser is
/// always exactly one process away.
public enum LinkDisplay: Sendable, Equatable, CaseIterable {
    /// The label alone; activating the link shows its URL in a popover. **The
    /// default.**
    ///
    /// The OSC 8 escape is emitted alongside it wherever the host honours one,
    /// so on those terminals the destination is also a hover or a ⌘-click
    /// away — but that is not this mode's doing and no mode turns it off (see
    /// ``View/terminalHyperlinks(_:)`` for that). The popover is
    /// what serves the keyboard, which no terminal gesture reaches.
    ///
    /// There WAS an `automatic` case that resolved to this one on a host
    /// without OSC 8 and to a "clean label" on one with it. It was deleted
    /// because those two are the same thing: the label is identical either
    /// way, the escape is emitted either way, and the popover is needed either
    /// way because a keyboard user never makes the terminal's gesture. A
    /// choice whose arms are indistinguishable is not a choice.
    case popover

    /// The label, then its URL in parentheses.
    ///
    /// For a page where the destination is part of what the reader is reading
    /// — a list of references, a diagnostic — and for terminals with their own
    /// URL detection, which linkify the visible text whether or not OSC 8 ever
    /// arrives. Activation opens the URL where the app permits and raises no
    /// popover: the destination is already on the row.
    case urlInParentheses

    /// The URL alone, in place of the label.
    ///
    /// The densest form, and the one to reach for when the URL *is* the
    /// content: a log line, a list of endpoints, anything the reader will copy
    /// rather than follow. As with ``urlInParentheses``, activation raises no
    /// popover — the row already says everything a popover would.
    case urlOnly
}

// MARK: - Environment

private struct LinkDisplayKey: EnvironmentKey {
    static let defaultValue = LinkDisplay.popover
}

extension EnvironmentValues {
    /// How a ``Link`` reveals its destination — see
    /// ``View/linkDisplay(_:)``.
    public var linkDisplay: LinkDisplay {
        get { self[LinkDisplayKey.self] }
        set { self[LinkDisplayKey.self] = newValue }
    }
}

extension View {
    /// Sets how every ``Link`` in this view's subtree reveals its destination.
    ///
    /// ```swift
    /// ContentView()
    ///     .linkDisplay(.urlInParentheses)
    /// ```
    ///
    /// The default is ``LinkDisplay/popover``. See ``LinkDisplay`` for why
    /// this is a choice at all rather than a fixed behaviour.
    ///
    /// TUI-specific: SwiftUI has no counterpart, because there a link is
    /// always one process call from a browser.
    public func linkDisplay(_ display: LinkDisplay) -> some View {
        environment(\.linkDisplay, display)
    }
}
