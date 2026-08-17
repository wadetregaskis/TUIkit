//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Alert+Presets.swift
//
//  The four styled alerts — warning, error, info, success — split out of
//  Alert.swift, which is the view itself.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Preset Alert Styles

extension Alert {
    /// Creates a warning-style alert with palette warning colors.
    ///
    /// String **literals** bind here, so they are lookup keys — see
    /// ``LocalizedStringKey``. The default title is the framework's own
    /// `label.warning`, translated into every bundled language; the presets
    /// used to hard-code the English word.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the alert title (default: `label.warning`).
    ///   - messageKey: The key for the alert message.
    ///   - actions: The action views.
    /// - Returns: A warning-styled alert.
    public static func warning(
        title titleKey: LocalizedStringKey = LocalizedStringKey(
            LocalizationKey.Label.warning.rawValue),
        message messageKey: LocalizedStringKey,
        @ViewBuilder actions: () -> Actions
    ) -> Alert {
        warning(
            title: titleKey.localized, message: messageKey.localized, actions: actions)
    }

    /// Creates a warning-style alert with text displayed as written.
    ///
    /// - Parameters:
    ///   - title: The alert title (default: the localized `label.warning`).
    ///   - message: The alert message.
    ///   - actions: The action views.
    /// - Returns: A warning-styled alert.
    @_disfavoredOverload
    public static func warning(
        title: String = LocalizationService.shared.string(for: LocalizationKey.Label.warning),
        message: String,
        @ViewBuilder actions: () -> Actions
    ) -> Alert {
        Self(
            title: title,
            message: message,
            titleColor: .palette.warning,
            actions: actions
        )
    }

    /// Creates an error-style alert with palette error title color.
    ///
    /// String **literals** bind here, so they are lookup keys — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the alert title (default: `label.error`).
    ///   - messageKey: The key for the alert message.
    ///   - actions: The action views.
    /// - Returns: An error-styled alert.
    public static func error(
        title titleKey: LocalizedStringKey = LocalizedStringKey(
            LocalizationKey.Label.error.rawValue),
        message messageKey: LocalizedStringKey,
        @ViewBuilder actions: () -> Actions
    ) -> Alert {
        error(title: titleKey.localized, message: messageKey.localized, actions: actions)
    }

    /// Creates an error-style alert with text displayed as written.
    ///
    /// - Parameters:
    ///   - title: The alert title (default: the localized `label.error`).
    ///   - message: The alert message.
    ///   - actions: The action views.
    /// - Returns: An error-styled alert.
    @_disfavoredOverload
    public static func error(
        title: String = LocalizationService.shared.string(for: LocalizationKey.Label.error),
        message: String,
        @ViewBuilder actions: () -> Actions
    ) -> Alert {
        Self(
            title: title,
            message: message,
            titleColor: .palette.error,
            actions: actions
        )
    }

    /// Creates an info-style alert with palette info title color.
    ///
    /// String **literals** bind here, so they are lookup keys — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the alert title (default: `label.info`).
    ///   - messageKey: The key for the alert message.
    ///   - actions: The action views.
    /// - Returns: An info-styled alert.
    public static func info(
        title titleKey: LocalizedStringKey = LocalizedStringKey(
            LocalizationKey.Label.info.rawValue),
        message messageKey: LocalizedStringKey,
        @ViewBuilder actions: () -> Actions
    ) -> Alert {
        info(title: titleKey.localized, message: messageKey.localized, actions: actions)
    }

    /// Creates an info-style alert with text displayed as written.
    ///
    /// - Parameters:
    ///   - title: The alert title (default: the localized `label.info`).
    ///   - message: The alert message.
    ///   - actions: The action views.
    /// - Returns: An info-styled alert.
    @_disfavoredOverload
    public static func info(
        title: String = LocalizationService.shared.string(for: LocalizationKey.Label.info),
        message: String,
        @ViewBuilder actions: () -> Actions
    ) -> Alert {
        Self(
            title: title,
            message: message,
            titleColor: .palette.info,
            actions: actions
        )
    }

    /// Creates a success-style alert with palette success title color.
    ///
    /// String **literals** bind here, so they are lookup keys — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the alert title (default: `label.success`).
    ///   - messageKey: The key for the alert message.
    ///   - actions: The action views.
    /// - Returns: A success-styled alert.
    public static func success(
        title titleKey: LocalizedStringKey = LocalizedStringKey(
            LocalizationKey.Label.success.rawValue),
        message messageKey: LocalizedStringKey,
        @ViewBuilder actions: () -> Actions
    ) -> Alert {
        success(title: titleKey.localized, message: messageKey.localized, actions: actions)
    }

    /// Creates a success-style alert with text displayed as written.
    ///
    /// - Parameters:
    ///   - title: The alert title (default: the localized `label.success`).
    ///   - message: The alert message.
    ///   - actions: The action views.
    /// - Returns: A success-styled alert.
    @_disfavoredOverload
    public static func success(
        title: String = LocalizationService.shared.string(for: LocalizationKey.Label.success),
        message: String,
        @ViewBuilder actions: () -> Actions
    ) -> Alert {
        Self(
            title: title,
            message: message,
            titleColor: .palette.success,
            actions: actions
        )
    }
}

// MARK: - Preset Alerts without Actions

extension Alert where Actions == EmptyView {
    /// Creates a warning-style alert without actions. Literals are keys.
    public static func warning(
        title titleKey: LocalizedStringKey = LocalizedStringKey(
            LocalizationKey.Label.warning.rawValue),
        message messageKey: LocalizedStringKey
    ) -> Alert<EmptyView> {
        warning(title: titleKey.localized, message: messageKey.localized)
    }

    /// Creates a warning-style alert without actions, shown as written.
    @_disfavoredOverload
    public static func warning(
        title: String = LocalizationService.shared.string(for: LocalizationKey.Label.warning),
        message: String
    ) -> Alert<EmptyView> {
        Alert<EmptyView>(title: title, message: message, titleColor: .palette.warning)
    }

    /// Creates an error-style alert without actions. Literals are keys.
    public static func error(
        title titleKey: LocalizedStringKey = LocalizedStringKey(
            LocalizationKey.Label.error.rawValue),
        message messageKey: LocalizedStringKey
    ) -> Alert<EmptyView> {
        error(title: titleKey.localized, message: messageKey.localized)
    }

    /// Creates an error-style alert without actions, shown as written.
    @_disfavoredOverload
    public static func error(
        title: String = LocalizationService.shared.string(for: LocalizationKey.Label.error),
        message: String
    ) -> Alert<EmptyView> {
        Alert<EmptyView>(title: title, message: message, titleColor: .palette.error)
    }

    /// Creates an info-style alert without actions. Literals are keys.
    public static func info(
        title titleKey: LocalizedStringKey = LocalizedStringKey(
            LocalizationKey.Label.info.rawValue),
        message messageKey: LocalizedStringKey
    ) -> Alert<EmptyView> {
        info(title: titleKey.localized, message: messageKey.localized)
    }

    /// Creates an info-style alert without actions, shown as written.
    @_disfavoredOverload
    public static func info(
        title: String = LocalizationService.shared.string(for: LocalizationKey.Label.info),
        message: String
    ) -> Alert<EmptyView> {
        Alert<EmptyView>(title: title, message: message, titleColor: .palette.info)
    }

    /// Creates a success-style alert without actions. Literals are keys.
    public static func success(
        title titleKey: LocalizedStringKey = LocalizedStringKey(
            LocalizationKey.Label.success.rawValue),
        message messageKey: LocalizedStringKey
    ) -> Alert<EmptyView> {
        success(title: titleKey.localized, message: messageKey.localized)
    }

    /// Creates a success-style alert without actions, shown as written.
    @_disfavoredOverload
    public static func success(
        title: String = LocalizationService.shared.string(for: LocalizationKey.Label.success),
        message: String
    ) -> Alert<EmptyView> {
        Alert<EmptyView>(title: title, message: message, titleColor: .palette.success)
    }
}
