//  🖥️ TUIkit — Terminal UI Kit for Swift
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
/// ``View/linkUnderline(_:)``.
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
/// > Note: On a terminal measured to honour them, the label also carries a real
/// > **OSC 8 hyperlink** (see ``TUIkitCore/TerminalHyperlink``), which tells the
/// > terminal where those cells point — so the URL can be shown on hover and
/// > copied, even though the label says "Documentation" and the destination is
/// > nowhere on screen. That is the part keyboard and mouse activation cannot
/// > give a link. Whether the terminal will also OPEN it on a modified click
/// > depends on the host, because a TUIkit app holds mouse reporting open and
/// > iTerm2 is measured to forward ⌘-click to the application instead — see
/// > ``TUIkitCore/TerminalHyperlink``. Everything else still works everywhere,
/// > Terminal.app included. Turn the escape off with
/// > ``View/terminalHyperlinks(_:)``, which an app that intercepts its own URL
/// > scheme in ``OpenURLAction`` may well want.
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
    /// Creates a link with a localized title.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the title shown for the link.
    ///   - destination: The URL to open when the link is activated.
    public init(_ titleKey: LocalizedStringKey, destination: URL) {
        self.init(titleKey.localized, destination: destination)
    }

    /// Creates a link with a string title, shown as written.
    ///
    /// - Parameters:
    ///   - title: The title shown for the link.
    ///   - destination: The URL to open when the link is activated.
    @_disfavoredOverload
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
    /// ``View/linkUnderline(_:)``. Default: `true` — an intentional
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

// MARK: - Terminal hyperlinks

private struct TerminalHyperlinksKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether ``Link`` also emits an OSC 8 terminal hyperlink. Set via
    /// ``View/terminalHyperlinks(_:)``. Default: `true` — which still emits
    /// nothing on a host not measured to honour them, because the two
    /// conditions are ANDed (see ``TUIkitCore/TerminalHyperlink/isSupported``).
    public var terminalHyperlinks: Bool {
        get { self[TerminalHyperlinksKey.self] }
        set { self[TerminalHyperlinksKey.self] = newValue }
    }
}

extension View {
    /// Sets whether ``Link`` views within this view attach a real terminal
    /// hyperlink to their labels.
    ///
    /// The escape tells the TERMINAL where a label points, which is how a URL
    /// nobody can see becomes one anybody can copy — and the reason an app
    /// might still want it off is the other half: wherever the terminal opens
    /// a link itself, it does so over the top of ``OpenURLAction``, so an app
    /// that intercepts its own URL scheme would find those links handled by
    /// somebody else:
    ///
    /// ```swift
    /// VStack {
    ///     Link("Open ticket", destination: URL(string: "myapp://ticket/42")!)
    /// }
    /// .terminalHyperlinks(false)   // this scheme is ours to open
    /// ```
    ///
    /// - Parameter enabled: Whether links carry the escape (default `true`).
    /// - Returns: A view whose links honour the setting.
    public func terminalHyperlinks(_ enabled: Bool = true) -> some View {
        environment(\.terminalHyperlinks, enabled)
    }
}

/// Attaches an OSC 8 hyperlink to every line of the content's rendered buffer.
///
/// **One balanced pair per LINE**, rather than one spanning the whole buffer,
/// and that is the load-bearing choice. A hyperlink is a property of cells,
/// and a buffer's lines are laid out and clipped independently — so a pair
/// that opened on the first row and closed on the last would be split by any
/// container that clipped between them, leaving the link open at a row's end
/// and running under everything drawn after it. Per line, every row is
/// self-contained: the pair survives compositing, padding and alignment
/// because none of those can put anything between an opening sequence and its
/// close on the same row, and the clip walks close it at the cut
/// (`HyperlinkScan`).
///
/// The cost is that a label spanning several rows becomes several links, which
/// is what the `id` parameter is for — a host that implements it treats runs
/// sharing an id as one link and highlights them together. It is emitted only
/// when there IS more than one row: a single-run link needs no identity, and
/// the parameter is bytes on every frame.
private struct TerminalHyperlinkModifier: ViewModifier {
    let destination: URL
    let enabled: Bool

    func modify(buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
        guard enabled, TerminalHyperlink.isSupported, !buffer.lines.isEmpty else { return buffer }
        let link = TerminalHyperlink(
            destination: destination.absoluteString,
            id: buffer.lines.count > 1 ? context.identity.path : nil)
        let opening = link.opening
        let lines = buffer.lines.map { line in
            // An empty row has no cells to carry the link, so it gets no
            // sequences: they would be bytes on every frame saying nothing.
            line.isEmpty ? line : opening + line + TerminalHyperlink.closing
        }
        // The widths are unchanged by construction — every scan in this
        // framework counts an escape as the zero cells it paints — so they are
        // carried across rather than re-measured.
        return buffer.replacingLines(
            lines, width: buffer.width, uniformWidth: buffer.linesAreUniformWidth,
            lineWidths: buffer.lineWidths)
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
    @Environment(\.terminalHyperlinks) private var terminalHyperlinks

    var body: some View {
        // Resolve the action and destination NOW, during render, and capture the
        // resolved values into the action closure. Reading `@Environment` inside
        // the closure — which fires later, on activation — would read it outside
        // a render pass, where it is invalid.
        let open = openURL
        let destination = self.destination
        // `.underline(_:)` cascades to every Text in the label subtree, so a
        // string title, a `Label`, or an SF-Symbol label all underline together.
        //
        // The accent arrives through the button's own text style rather than as
        // a `.foregroundStyle` on the label. Both put the same colour on screen,
        // but a colour written on the label wins over the one the style hands
        // down — and it is the STYLE that knows whether the pointer is over the
        // link. Routed this way, `.plain`'s hover lift applies to a link like
        // any other plain button, which is the whole affordance a link has.
        return Button(action: { open(destination) }, label: {
            label.underline(underline)
        })
        .buttonStyle(.plain)
        .buttonTextStyle { $0.foreground = .palette.accent }
        // Outermost, so the link covers everything the button style drew —
        // its hover prefix included. The control IS the link; a hyperlink over
        // only the letters would leave the cells beside them inert while
        // looking identical.
        .modifier(
            TerminalHyperlinkModifier(destination: destination, enabled: terminalHyperlinks))
    }
}
