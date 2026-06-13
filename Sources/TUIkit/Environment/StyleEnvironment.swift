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
