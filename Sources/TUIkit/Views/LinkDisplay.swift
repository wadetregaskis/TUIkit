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
/// is useless on a terminal that cannot linkify it.
///
/// TUI-specific. SwiftUI's `Link` has no equivalent, because a browser is
/// always exactly one process away.
public enum LinkDisplay: Sendable, Equatable, CaseIterable {
    /// The cleanest thing this terminal supports. **The default.**
    ///
    /// A terminal measured to honour OSC 8 gets a clean label and the escape,
    /// so the destination is one hover or one ⌘-click away and no URL is on
    /// screen. A terminal that does not gets ``popover``, because on those the
    /// escape is not sent at all and a bare label would say nothing about
    /// where it goes.
    case automatic

    /// The label alone; activating the link shows its URL in a popover.
    ///
    /// What ``automatic`` falls back to. Choose it explicitly to get the same
    /// behaviour on every host, including the ones that would have linkified
    /// the label themselves.
    case popover

    /// The label, then its URL in parentheses.
    ///
    /// For a page where the destination is part of what the reader is reading
    /// — a list of references, a diagnostic — and for terminals with their own
    /// URL detection, which linkify the visible text whether or not OSC 8 ever
    /// arrives.
    case urlInParentheses

    /// The URL alone, in place of the label.
    ///
    /// The densest form, and the one to reach for when the URL *is* the
    /// content: a log line, a list of endpoints, anything the reader will copy
    /// rather than follow.
    case urlOnly

    /// Whether this mode puts the URL on screen as text, which decides both
    /// whether the label needs rewriting and whether a popover would be
    /// telling the reader something they can already see.
    var showsURLInline: Bool {
        self == .urlInParentheses || self == .urlOnly
    }

    /// ``automatic`` resolved against what the terminal will honour; every
    /// other case is already concrete.
    ///
    /// - Parameter hyperlinksSupported: whether OSC 8 is being emitted at all
    ///   — `TerminalHyperlink.isSupported`, which is the same value the
    ///   escape's own modifier ANDs against, so the two cannot disagree about
    ///   what this terminal was told.
    func resolved(hyperlinksSupported: Bool) -> Self {
        guard self == .automatic else { return self }
        return hyperlinksSupported ? .automatic : .popover
    }
}

// MARK: - Environment

private struct LinkDisplayKey: EnvironmentKey {
    static let defaultValue = LinkDisplay.automatic
}

extension EnvironmentValues {
    /// How a ``Link`` reveals its destination — see
    /// ``SwiftUICore/View/linkDisplay(_:)``.
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
    /// The default is ``LinkDisplay/automatic``. See ``LinkDisplay`` for why
    /// this is a choice at all rather than a fixed behaviour.
    ///
    /// TUI-specific: SwiftUI has no counterpart, because there a link is
    /// always one process call from a browser.
    public func linkDisplay(_ display: LinkDisplay) -> some View {
        environment(\.linkDisplay, display)
    }
}
