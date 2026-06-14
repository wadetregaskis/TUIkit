//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StyleEnvironment.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Style cascade environment

/// Environment key carrying the scoped style cascade (see ``StyleCascade``).
///
/// Container-level style modifiers (`.bold()`, `.style(_:_:)`, …) append to it;
/// views resolve their effective attributes from `context.environment.styleCascade`.
private struct StyleCascadeKey: EnvironmentKey {
    static let defaultValue = StyleCascade()
}

extension EnvironmentValues {
    /// The scoped style cascade contributed by ancestor style modifiers.
    public var styleCascade: StyleCascade {
        get { self[StyleCascadeKey.self] }
        set { self[StyleCascadeKey.self] = newValue }
    }
}

// MARK: - Chrome role

/// Environment key marking the structural chrome role a subtree renders (e.g. a
/// `Section` header). `Text` reads it to apply the role's default attributes and
/// to match `.chrome(role)` style-cascade entries.
private struct ChromeRoleKey: EnvironmentKey {
    static let defaultValue: ChromeRole? = nil
}

extension EnvironmentValues {
    /// The chrome role of the current subtree, if any (set by `Section` around
    /// its header/footer). Drives chrome text styling (see ``ChromeRole``).
    public var chromeRole: ChromeRole? {
        get { self[ChromeRoleKey.self] }
        set { self[ChromeRoleKey.self] = newValue }
    }
}

// MARK: - Control identity

/// Environment keys marking that a subtree renders a control's label, so its
/// `Text` resolves `.control(kind)` / `.controlVariant(kind, variant)` style
/// entries. Controls whose labels are rendered via `Text` (Toggle, Picker, …)
/// set these around the label; controls that render their label procedurally
/// (Button) resolve the same scopes directly.
private struct ControlKindKey: EnvironmentKey {
    static let defaultValue: ControlKind? = nil
}

private struct ControlVariantKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// The control kind whose label the current subtree renders, if any.
    public var controlKind: ControlKind? {
        get { self[ControlKindKey.self] }
        set { self[ControlKindKey.self] = newValue }
    }

    /// The control variant token for the current subtree's label, paired with
    /// ``controlKind`` to match `.controlVariant(kind, variant)` entries.
    public var controlVariant: String? {
        get { self[ControlVariantKey.self] }
        set { self[ControlVariantKey.self] = newValue }
    }
}
