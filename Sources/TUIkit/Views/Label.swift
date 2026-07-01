//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Label.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Label

/// A standard label for user-interface items: an icon paired with a title.
///
/// Mirrors SwiftUI's `Label`. The general form takes a title and an icon view;
/// the convenience ``init(_:systemImage:)`` pairs a string title with an SF
/// Symbol.
///
/// ```swift
/// Label("Favourites", systemImage: "star.fill")
///
/// Label {
///     Text("Inbox")
/// } icon: {
///     Text("\u{1F4E5}")
/// }
/// ```
///
/// The icon and title are laid out horizontally with a one-cell gap.
///
/// ## SF Symbols render only in very limited circumstances
///
/// ``init(_:systemImage:)`` resolves the symbol through ``SFSymbol``, which only
/// produces a glyph on **Apple platforms** in a **terminal whose font carries
/// the SF Symbol glyphs** (Terminal.app with SF Mono and the SF Symbols font
/// installed). When the symbol can't be resolved — a non-Apple platform, or an
/// unknown name — the label renders **just its title**, with no icon column and
/// no stray gap, so the call site stays correct everywhere. See ``SFSymbol``.
public struct Label<Title: View, Icon: View>: View {
    let title: Title
    let icon: Icon
    /// When `false`, only the title is rendered (no icon, no leading gap). Set
    /// by ``init(_:systemImage:)`` when the symbol can't be resolved.
    let iconIsVisible: Bool

    /// Creates a label with a custom title and icon.
    ///
    /// - Parameters:
    ///   - title: A view builder producing the title.
    ///   - icon: A view builder producing the icon.
    public init(@ViewBuilder title: () -> Title, @ViewBuilder icon: () -> Icon) {
        self.title = title()
        self.icon = icon()
        self.iconIsVisible = true
    }

    /// Internal designated initializer; lets ``init(_:systemImage:)`` suppress
    /// the icon when the symbol can't be resolved.
    init(title: Title, icon: Icon, iconIsVisible: Bool) {
        self.title = title
        self.icon = icon
        self.iconIsVisible = iconIsVisible
    }

    public var body: some View {
        if iconIsVisible {
            HStack(spacing: 1) {
                icon
                title
            }
        } else {
            title
        }
    }
}

// MARK: - SF Symbol convenience

extension Label where Title == Text, Icon == Text {
    /// Creates a label with a string title and an SF Symbol icon.
    ///
    /// On a terminal that can render the symbol (see ``SFSymbol``) the glyph is
    /// shown before the title; otherwise only the title is shown. This matches
    /// SwiftUI's `Label(_:systemImage:)` signature — the icon is modelled as a
    /// terminal glyph (a Private-Use character) rather than a raster image,
    /// because a terminal can only place symbols as text, not size them.
    ///
    /// - Parameters:
    ///   - title: The title shown beside the icon.
    ///   - systemImage: The SF Symbol name, e.g. `"star.fill"`.
    public init<S: StringProtocol>(_ title: S, systemImage systemName: String) {
        let resolved = SFSymbol.glyph(named: systemName)
        self.init(
            title: Text(String(title)),
            icon: Text(resolved ?? ""),
            iconIsVisible: resolved != nil)
    }
}
