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
/// label is tinted with the accent colour; a string-titled link is also
/// underlined to read as a link.
///
/// ```swift
/// Link("Documentation", destination: URL(string: "https://example.com")!)
///
/// Link(destination: URL(string: "https://example.com")!) {
///     Label("Docs", systemImage: "book")
/// }
/// ```
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
    ///   - title: The title shown for the link (underlined).
    ///   - destination: The URL to open when the link is activated.
    public init<S: StringProtocol>(_ title: S, destination: URL) {
        self.destination = destination
        self.label = Text(String(title)).underline()
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

    var body: some View {
        // Resolve the action and destination NOW, during render, and capture the
        // resolved values into the action closure. Reading `@Environment` inside
        // the closure — which fires later, on activation — would read it outside
        // a render pass, where it is invalid.
        let open = openURL
        let destination = self.destination
        return Button(action: { open(destination) }, label: {
            label.foregroundStyle(.palette.accent)
        })
        .buttonStyle(.plain)
    }
}
