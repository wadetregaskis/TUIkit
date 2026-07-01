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
/// The `(URL) -> Result` handler form of SwiftUI's initializer is omitted; the
/// common `(URL) -> Void` form covers terminal use.
public struct OpenURLAction: Sendable {
    private let handler: @Sendable (URL) -> Void

    /// Creates an open-URL action with a custom handler.
    ///
    /// - Parameter handler: A closure invoked with the URL to open.
    public init(handler: @escaping @Sendable (URL) -> Void) {
        self.handler = handler
    }

    /// Opens the URL. Equivalent to writing `openURL(url)`.
    ///
    /// - Parameter url: The URL to open.
    public func callAsFunction(_ url: URL) {
        handler(url)
    }

    /// Hands `url` to the system opener. Tries `open` (macOS) then `xdg-open`
    /// (Linux) — whichever exists — passing the URL as a single argument (no
    /// shell, so nothing in the URL is interpreted). A no-op when neither
    /// opener is present.
    static func systemOpen(_ url: URL) {
        for opener in ["/usr/bin/open", "/usr/bin/xdg-open"]
        where FileManager.default.fileExists(atPath: opener) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: opener)
            process.arguments = [url.absoluteString]
            try? process.run()
            return
        }
    }
}

// MARK: - Environment Key

/// Environment key for the open-URL action.
private struct OpenURLActionKey: EnvironmentKey {
    static let defaultValue = OpenURLAction { url in OpenURLAction.systemOpen(url) }
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
