//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StyleAttributes.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitStyling

// MARK: - Text case

/// A case transform applied to text, mirroring SwiftUI's `Text.Case`.
public enum TextCase: Sendable, Hashable {
    case uppercase
    case lowercase
}

// MARK: - Font weight

/// A font weight, mirroring SwiftUI's `Font.Weight`.
///
/// Terminals have no real font weights, so weight maps to the nearest SGR
/// emphasis: heavier-than-regular weights render **bold**, lighter-than-regular
/// weights render **faint** (dim), and `regular`/`medium` render normal.
public enum FontWeight: Sendable, Hashable {
    case ultraLight
    case thin
    case light
    case regular
    case medium
    case semibold
    case bold
    case heavy
    case black

    /// The text attributes this weight maps to on a terminal. Sets `bold` and
    /// `dim` explicitly (rather than leaving them `nil`) so that, e.g.,
    /// `.fontWeight(.regular)` actively clears an inherited bold/faint.
    var styleAttributes: StyleAttributes {
        switch self {
        case .semibold, .bold, .heavy, .black:
            return StyleAttributes(bold: true, dim: false)
        case .ultraLight, .thin, .light:
            return StyleAttributes(bold: false, dim: true)
        case .regular, .medium:
            return StyleAttributes(bold: false, dim: false)
        }
    }
}

// MARK: - Style attributes

/// The themeable subset of ``TextStyle``, expressed as a *partial* overlay:
/// every field is optional, where `nil` means "inherit / not set at this level".
///
/// `StyleAttributes` is the value carried by the scoped style cascade
/// (``StyleCascade``). Container-level modifiers like ``SwiftUI/View/bold(_:)``
/// and ``SwiftUI/View/style(_:_:)`` contribute these; ``Text`` merges the
/// resolved result beneath its own explicit attributes when it renders.
///
/// The tri-state (`Bool?`) lets a subtree turn an attribute **on** and a
/// descendant turn it **off** (e.g. `.bold()` then `.bold(false)` deeper),
/// matching SwiftUI.
public struct StyleAttributes: Sendable, Equatable {
    public var foreground: Color?
    public var background: Color?
    public var bold: Bool?
    public var italic: Bool?
    public var underline: Bool?
    public var strikethrough: Bool?
    public var dim: Bool?
    public var textCase: TextCase?

    public init(
        foreground: Color? = nil,
        background: Color? = nil,
        bold: Bool? = nil,
        italic: Bool? = nil,
        underline: Bool? = nil,
        strikethrough: Bool? = nil,
        dim: Bool? = nil,
        textCase: TextCase? = nil
    ) {
        self.foreground = foreground
        self.background = background
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
        self.dim = dim
        self.textCase = textCase
    }

    /// Whether no attribute is set (every field is `nil`).
    public var isEmpty: Bool {
        foreground == nil && background == nil && bold == nil && italic == nil
            && underline == nil && strikethrough == nil && dim == nil && textCase == nil
    }

    /// Returns a copy where `self`'s non-`nil` fields win over `base` — the
    /// merge primitive the cascade uses. Applying an inner (closer) entry's
    /// attributes `merged(over:)` the accumulated outer ones makes the closest
    /// setter of each property win (proximity, per property).
    public func merged(over base: Self) -> Self {
        Self(
            foreground: foreground ?? base.foreground,
            background: background ?? base.background,
            bold: bold ?? base.bold,
            italic: italic ?? base.italic,
            underline: underline ?? base.underline,
            strikethrough: strikethrough ?? base.strikethrough,
            dim: dim ?? base.dim,
            textCase: textCase ?? base.textCase)
    }
}
