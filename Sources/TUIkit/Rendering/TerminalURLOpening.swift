//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalURLOpening.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore

// MARK: - Whether this process may launch a browser

/// Whether ``OpenURLAction`` may hand a URL to the system opener.
///
/// The render path and the activation path are not main-actor isolated and
/// cannot go asking a terminal anything, so the answer is published here and
/// read from there — the same shape as ``TUIkitCore/TerminalHyperlink/isSupported``.
enum TerminalURLOpening {
    /// `false` unless something turned it on. See ``TerminalClient/urlOpeningSupport``.
    ///
    /// `nonisolated(unsafe)` for the reason `TerminalHyperlink.isSupported` is:
    /// written once at startup, before anything renders, and read from paths
    /// that have no actor.
    nonisolated(unsafe) static var isEnabled = false
}

extension TerminalClient {

    /// Whether TUIkit may open a URL by launching a browser on **this**
    /// machine. `nil` (the default) means no.
    ///
    /// ## Why the default is no
    ///
    /// `OpenURLAction`'s system opener runs `/usr/bin/open` or
    /// `/usr/bin/xdg-open` **on the machine the application is running on**.
    /// Locally that is the user's own browser and is exactly right. Over ssh it
    /// is the server's — and a server is either headless, where `xdg-open`
    /// ships in a desktop package most server images do not carry and the
    /// launch is a silent no-op, or it is somebody's desktop, where the URL
    /// lands in a browser in front of a person who did not ask for it and stays
    /// in their history.
    ///
    /// **And the framework cannot tell which it is.** `SSH_CONNECTION`,
    /// `SSH_TTY` and `SSH_CLIENT` are reliable when PRESENT and prove nothing
    /// when absent: they are gone under `sudo` and `su`, and a tmux, screen or
    /// zellij session started before the hop — or reattached after it — carries
    /// the environment of whenever it began rather than of the client now
    /// looking at it. There is no query that asks a terminal which machine it
    /// is on. So "am I local?" has no answer this framework can trust, and the
    /// cost of the two wrong answers is not symmetric: guessing local when
    /// remote sends somebody's URL to a machine they are not at, and guessing
    /// remote when local costs a copy and paste.
    ///
    /// A `Link` is not silent as a result — that is what makes this bearable.
    /// It carries an OSC 8 hyperlink where the terminal honours one, so the
    /// terminal (which IS on the user's machine) can open it; and activating
    /// one raises a popover with the destination to read and copy. See
    /// ``LinkDisplay``.
    ///
    /// ## Turning it on
    ///
    /// `true` for a tool that knows it is local — a local-only developer
    /// utility, an app whose own launcher guarantees it. `TUIKIT_OPEN_URLS=1`
    /// in the environment does the same, which is how a USER answers for their
    /// own session without the application knowing anything about it, and
    /// `TUIKIT_OPEN_URLS=0` forces it off against an app that turned it on.
    ///
    /// An app that wants to open URLs its own way needs none of this: an
    /// `OpenURLAction` handler that does the work and returns
    /// ``OpenURLAction/Result/handled`` is untouched by this setting. What is
    /// gated is only the framework launching a process on the user's behalf.
    @MainActor public static var urlOpeningSupport: Bool? {
        didSet {
            guard urlOpeningSupport != oldValue else { return }
            applyURLOpeningSupport()
        }
    }

    /// Whether a URL handed to the system opener would actually be launched —
    /// the override, then the environment, then `false`.
    @MainActor public static var urlOpeningEnabled: Bool {
        if let urlOpeningSupport { return urlOpeningSupport }
        switch ProcessInfo.processInfo.environment["TUIKIT_OPEN_URLS"] {
        case "1": return true
        case "0": return false
        default: return false
        }
    }

    /// Publishes ``urlOpeningEnabled`` to the flag the activation path reads.
    ///
    /// Called once at startup — before anything can be activated — and again
    /// from the setter, whose whole point is changing it.
    @MainActor
    public static func applyURLOpeningSupport() {
        TerminalURLOpening.isEnabled = urlOpeningEnabled
    }
}
