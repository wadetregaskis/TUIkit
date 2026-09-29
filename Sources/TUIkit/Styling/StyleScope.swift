//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StyleScope.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitStyling

// MARK: - Control kind

/// A built-in interactive control, used to scope a style entry to controls of
/// that kind (and, with a variant, to a specific mode of one).
public enum ControlKind: Sendable, Hashable {
    case button
    case toggle
    case slider
    case picker
    case stepper
    case textField
    case secureField
    case radioButton
    case list
    case table
    case colorPicker
}

// MARK: - Chrome role

/// A non-control structural element that draws text (so it can be styled by the
/// theme), e.g. a `Section`'s header.
public enum ChromeRole: Sendable, Hashable {
    case sectionHeader
    case sectionFooter
    case listRow

    /// The text attributes this role renders with by default — the baseline the
    /// style cascade overrides. Preserves TUIkit's established look: section
    /// headers are bold + dim, footers dim.
    public var defaultTextAttributes: StyleAttributes {
        switch self {
        case .sectionHeader: return StyleAttributes(bold: true, dim: true)
        case .sectionFooter: return StyleAttributes(dim: true)
        case .listRow: return StyleAttributes()
        }
    }
}

// MARK: - Style scope

/// *What* a scoped style entry applies to — its reach, not its priority.
///
/// A view matches a set of scopes (its "scope path"): a plain ``Text`` matches
/// `.all` and `.text` (plus `.semanticColor(role)` when it draws with a palette
/// role); a default button's label additionally matches `.control(.button)` and
/// `.controlVariant(.button, "default")`. Resolution (see ``StyleCascade``) is
/// **proximity-dominant** — the entry applied closest to the view wins — so a
/// scope governs *reach*; precedence between ancestors is decided by position,
/// matching SwiftUI's environment.
///
/// Specificity (below) is used only to order entries that live at the *same*
/// place — within one `Theme` bundle or a single multi-scope application — where
/// the more specific entry should win.
public enum StyleScope: Sendable, Hashable {
    /// Everything.
    case all
    /// Any rendered text.
    case text
    /// Text drawn with a specific palette role, e.g. `.foregroundSecondary`.
    case semanticColor(SemanticColor)
    /// Any control of a kind.
    case control(ControlKind)
    /// A specific mode of a control, e.g. a default vs. bordered button. The
    /// variant token is type-erased to a `String`; typed convenience modifiers
    /// (e.g. per-control `Variant` enums) map to it.
    case controlVariant(ControlKind, String)
    /// A structural chrome element, e.g. a section header.
    case chrome(ChromeRole)
    /// Text carrying a semantic ``Font/TextStyle``, e.g. `.headline`. Lets a
    /// theme redefine what a semantic style looks like, since the mapping in
    /// ``Font`` is only a default.
    case font(Font.TextStyle)

    /// How narrow this scope is. Used only to order entries within a single
    /// application point (a `Theme` bundle); across the view tree, proximity
    /// decides (see ``StyleCascade``).
    public var specificity: Int {
        switch self {
        case .all: return 0
        case .text, .control: return 1
        case .semanticColor, .controlVariant, .chrome, .font: return 2
        }
    }
}

// MARK: - Value Hash

/// Read by a `switch` — `controlVariant` holds a string, so the enum is not
/// trivial and its bytes cannot be read whole — and each case's payload by its
/// own plan. See `_ValueHashing`.
extension StyleScope: _ValueHashing {
    package static func _mixValueHash(
        at pointer: UnsafeRawPointer, into hash: inout UInt64, plans: ValueHashPlans
    ) -> Bool {
        switch pointer.assumingMemoryBound(to: Self.self).pointee {
        case .all: plans.mixCase(0, (), into: &hash)
        case .text: plans.mixCase(1, (), into: &hash)
        case .semanticColor(let color): plans.mixCase(2, color, into: &hash)
        case .control(let kind): plans.mixCase(3, kind, into: &hash)
        case .controlVariant(let kind, let variant): plans.mixCase(4, (kind, variant), into: &hash)
        case .chrome(let role): plans.mixCase(5, role, into: &hash)
        case .font(let style): plans.mixCase(6, style, into: &hash)
        }
    }
}
