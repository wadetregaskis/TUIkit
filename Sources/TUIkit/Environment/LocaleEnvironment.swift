//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LocaleEnvironment.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

/// EnvironmentKey for the current locale.
private struct LocaleKey: EnvironmentKey {
    static let defaultValue = Locale.autoupdatingCurrent
}

extension EnvironmentValues {
    /// The locale for the view subtree.
    ///
    /// Matches SwiftUI's `\.locale`. It is populated each frame from the app's
    /// localization service (`applyRuntimeServices(from:)`), so by default it
    /// tracks the app language — but because it's a stored, settable key, a
    /// subtree can override it with `.environment(\.locale, _)` to format its
    /// numbers and dates in a different locale than the surrounding UI.
    ///
    /// `Table`, `List`, and `ScrollView`'s number chrome read it, so an override
    /// re-locales their formatted output.
    public var locale: Locale {
        get { self[LocaleKey.self] }
        set { self[LocaleKey.self] = newValue }
    }
}
