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
