//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Link.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Link

/// A control that opens a URL when activated.
///
/// Mirrors SwiftUI's `Link`. In a terminal a link is focusable like a button:
/// Tab to it and press Enter/Space, or click it, to open its destination via
/// the environment's ``OpenURLAction`` (the system opener by default). The
/// label is tinted with the accent colour and underlined so it reads as a link
/// — regardless of the label form. Turn the underline off for a subtree with
/// ``SwiftUI/View/linkUnderline(_:)``.
///
/// ```swift
/// Link("Documentation", destination: URL(string: "https://example.com")!)
///
/// Link(destination: URL(string: "https://example.com")!) {
///     Label("Docs", systemImage: "book")
/// }
/// ```
///
/// > Note: SwiftUI's `Link` is accent-coloured but **not** underlined by
/// > default. Underlining by default is an intentional terminal-readability
/// > deviation — a hyperlink in a terminal has no hover/pointer affordance, so
/// > the underline is what marks it as a link. Opt out with `.linkUnderline(false)`.
///
/// > Note: The link does not emit an OSC 8 terminal-hyperlink escape — TUIkit's
/// > width/clip pipeline is CSI-only, and an embedded OSC sequence would corrupt
/// > layout. Activation is by keyboard and mouse click instead, which works in
/// > every terminal (including Terminal.app).
public struct Link<Label: View>: View {
    let destination: URL
    let label: Label

    /// Creates a link with a custom label.
    ///
    /// - Parameters:
    ///   - destination: The URL to open when the link is activated.
    ///   - label: A view builder producing the link's label.
    public init(destination: URL, @ViewBuilder label: () -> Label) {
        self.destination = destination
        self.label = label()
    }

    public var body: some View {
        _Link(destination: destination, label: label)
    }
}

// MARK: - String-titled convenience

extension Link where Label == Text {
    /// Creates a link with a string title.
    ///
    /// - Parameters:
    ///   - title: The title shown for the link.
    ///   - destination: The URL to open when the link is activated.
    public init<S: StringProtocol>(_ title: S, destination: URL) {
        self.destination = destination
        // The underline is applied uniformly in `_Link` from the environment,
        // so string- and view-labelled links look the same and both honour
        // `.linkUnderline(_:)`.
        self.label = Text(String(title))
    }
}

// MARK: - Underline styling

private struct LinkUnderlineKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether ``Link`` labels are underlined. Set via
    /// ``SwiftUI/View/linkUnderline(_:)``. Default: `true` — an intentional
    /// deviation from SwiftUI (whose links are accent-coloured only) so links
    /// read as links without a pointer/hover affordance.
    public var linkUnderline: Bool {
        get { self[LinkUnderlineKey.self] }
        set { self[LinkUnderlineKey.self] = newValue }
    }
}

extension View {
    /// Sets whether ``Link`` labels within this view are underlined.
    ///
    /// TUIkit underlines links by default so they read as links in a terminal.
    /// Turn it off for a whole subtree:
    ///
    /// ```swift
    /// VStack {
    ///     Link("Home", destination: home)
    ///     Link("Docs", destination: docs)
    /// }
    /// .linkUnderline(false)
    /// ```
    ///
    /// - Parameter enabled: Whether links are underlined (default `true`).
    /// - Returns: A view whose links honour the underline setting.
    public func linkUnderline(_ enabled: Bool = true) -> some View {
        environment(\.linkUnderline, enabled)
    }
}

// MARK: - Internal

/// Reads ``OpenURLAction`` from the environment and drives a plain, accent-tinted
/// button — reusing all of `Button`'s focus, keyboard, mouse, and disabled
/// handling — whose action opens the destination.
private struct _Link<Label: View>: View {
    let destination: URL
    let label: Label

    @Environment(\.openURL) private var openURL
    @Environment(\.linkUnderline) private var underline

    var body: some View {
        // Resolve the action and destination NOW, during render, and capture the
        // resolved values into the action closure. Reading `@Environment` inside
        // the closure — which fires later, on activation — would read it outside
        // a render pass, where it is invalid.
        let open = openURL
        let destination = self.destination
        // `.underline(_:)` cascades to every Text in the label subtree, so a
        // string title, a `Label`, or an SF-Symbol label all underline together.
        return Button(action: { open(destination) }, label: {
            label
                .underline(underline)
                .foregroundStyle(.palette.accent)
        })
        .buttonStyle(.plain)
    }
}
