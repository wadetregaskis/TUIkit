//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KeyboardHelpSection.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// A DemoSection showing keyboard shortcut help lines.
///
/// Each string in the array is rendered as a dimmed text line.
///
/// # Example
///
/// ```swift
/// KeyboardHelpSection(shortcuts: [
///     "page.buttons.help.tab",
///     "page.buttons.help.enterSpace",
/// ])
/// ```
///
/// Title and shortcut lines are all display prose, so all of them are
/// localization keys — see ``DemoSection`` for the pattern. The lines are taken
/// as keys outright rather than as a disfavoured pair: every caller writes them
/// as literals, and an array is not a literal Swift will resolve an overload on.
struct KeyboardHelpSection: View {
    let title: String
    let shortcuts: [LocalizedStringKey]

    /// Creates a help section with a localized title.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the section title.
    ///   - shortcuts: The keys for the shortcut lines.
    init(_ titleKey: LocalizedStringKey = "demo.keyboardControls", shortcuts: [LocalizedStringKey]) {
        self.init(titleKey.localized, shortcuts: shortcuts)
    }

    /// Creates a help section titled as written.
    ///
    /// - Parameters:
    ///   - title: The section title.
    ///   - shortcuts: The keys for the shortcut lines.
    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, shortcuts: [LocalizedStringKey]) {
        self.title = String(title)
        self.shortcuts = shortcuts
    }

    var body: some View {
        DemoSection(title) {
            VStack(alignment: .leading) {
                ForEach(Array(shortcuts.enumerated()), id: \.offset) { _, shortcut in
                    Text(shortcut).dim()
                }
            }
        }
    }
}
