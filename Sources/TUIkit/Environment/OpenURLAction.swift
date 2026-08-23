//  🖥️ TUIKit — Terminal UI Kit for Swift
//  OpenURLAction.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkitCore

// MARK: - Open URL Action

/// An action that opens a URL, mirroring SwiftUI's `OpenURLAction`.
///
/// Read it from the environment with `@Environment(\.openURL)` and call it like
/// a function. It backs ``Link``, and can be called directly:
///
/// ```swift
/// struct HelpButton: View {
///     @Environment(\.openURL) private var openURL
///
///     var body: some View {
///         Button("Docs") { openURL(URL(string: "https://example.com")!) }
///     }
/// }
/// ```
///
/// The default action hands the URL to the operating system's opener — `open`
/// on macOS, `xdg-open` on Linux — so it launches in the user's browser (or
/// whatever app is registered), the same as SwiftUI's default. Override it for
/// a scope by putting a custom action in the environment:
///
/// ```swift
/// content.environment(\.openURL, OpenURLAction { url in log("would open \(url)") })
/// ```
///
/// Both handler forms ship: SwiftUI's `(URL) -> Result`, and a `(URL) -> Void`
/// convenience with no SwiftUI counterpart for the common case of a handler
/// that always handles.
public struct OpenURLAction: Sendable {
    /// What a custom handler did with the URL.
    ///
    /// The reason a handler returns something rather than returning nothing:
    /// **`systemAction` lets it decline**. An app that wants to intercept its
    /// own scheme and leave every other URL alone has no way to say so
    /// otherwise — it would have to re-implement the system opener to hand the
    /// rest on, and then it is the thing deciding what "open" means for URLs it
    /// never wanted.
    ///
    /// A struct with static members rather than an enum, matching SwiftUI, so
    /// cases can be added without breaking a `switch` nobody should be writing
    /// over it anyway.
    public struct Result: Sendable, Equatable {
        /// What the action does after the handler returns.
        enum Disposition: Sendable, Equatable {
            /// Nothing: the handler dealt with it.
            case handled
            /// Nothing: the handler decided it should not be opened.
            case discarded
            /// Hand this URL to the system opener.
            case system(URL?)
        }

        let disposition: Disposition

        /// The handler opened the URL itself.
        public static let handled = Self(disposition: .handled)

        /// The URL should not be opened at all.
        public static let discarded = Self(disposition: .discarded)

        /// Let the system open the URL the handler was given.
        public static let systemAction = Self(disposition: .system(nil))

        /// Let the system open a DIFFERENT URL — a rewrite, most usefully:
        /// canonicalise or sign a link and hand the result on.
        ///
        /// - Parameter url: The URL to open instead.
        /// - Returns: A result deferring to the system opener.
        public static func systemAction(_ url: URL) -> Self {
            Self(disposition: .system(url))
        }
    }

    private let handler: @Sendable (URL) -> Result

    /// Creates an open-URL action with a custom handler — SwiftUI's spelling.
    ///
    /// - Parameter handler: A closure invoked with the URL to open, returning
    ///   what it did with it.
    public init(handler: @escaping @Sendable (URL) -> Result) {
        self.handler = handler
    }

    /// Creates an open-URL action from a handler that always handles.
    ///
    /// No SwiftUI counterpart, and kept because it is what most overrides
    /// actually want to say — a logger, a redirect to an in-app help screen.
    /// Returning nothing is the same statement as returning ``Result/handled``.
    ///
    /// - Parameter handler: A closure invoked with the URL to open.
    @_disfavoredOverload
    public init(handler: @escaping @Sendable (URL) -> Void) {
        self.handler = { url in
            handler(url)
            return .handled
        }
    }

    /// Opens the URL. Equivalent to writing `openURL(url)`.
    ///
    /// - Parameter url: The URL to open.
    public func callAsFunction(_ url: URL) {
        switch result(for: url).disposition {
        case .handled, .discarded:
            return
        case .system(let replacement):
            Self.systemOpen(replacement ?? url)
        }
    }

    /// What the handler says to do with `url`, without doing it.
    ///
    /// The test seam, and it has to exist because the alternative is not
    /// testable: deferring to the system opener LAUNCHES A PROCESS, so a case
    /// that called the action could only assert what did not happen. Internal —
    /// an app has no use for the answer, having just written the handler that
    /// produces it.
    func result(for url: URL) -> Result {
        handler(url)
    }

    /// Hands `url` to the system opener. Tries `open` (macOS) then `xdg-open`
    /// (Linux) — whichever exists — passing the URL as a single argument (no
    /// shell, so nothing in the URL is interpreted). A no-op when neither
    /// opener is present.
    ///
    /// The child's output goes to `/dev/null`. It inherits this process's
    /// descriptors otherwise, and stdout/stderr here are the terminal the app
    /// is drawing on: `xdg-open`'s "no method available for opening" (or
    /// `open`'s own complaints) would land in the middle of the frame, at
    /// whatever cursor position the renderer was using, with nothing to
    /// repaint over it until the next full redraw.
    static func systemOpen(_ url: URL) {
        for opener in ["/usr/bin/open", "/usr/bin/xdg-open"]
        where FileManager.default.fileExists(atPath: opener) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: opener)
            process.arguments = [url.absoluteString]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            return
        }
    }
}

// MARK: - Environment Key

/// Environment key for the open-URL action.
private struct OpenURLActionKey: EnvironmentKey {
    // `.systemAction`, not a handler that calls `systemOpen` itself: the
    // default IS "let the system open it", and saying so means the fallback
    // lives in exactly one place — `callAsFunction` — rather than in the
    // default handler and in every `.systemAction` a custom one returns.
    static let defaultValue = OpenURLAction { _ in .systemAction }
}

extension EnvironmentValues {
    /// An action that opens a URL (see ``OpenURLAction``).
    ///
    /// Read it with `@Environment(\.openURL)` and call it like a function.
    /// The default hands the URL to the system opener (`open` / `xdg-open`).
    public var openURL: OpenURLAction {
        get { self[OpenURLActionKey.self] }
        set { self[OpenURLActionKey.self] = newValue }
    }
}
