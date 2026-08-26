//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MenuPresentationLabels.swift
//
//  What the status bar's Return and Escape items say over a menu.
//
//  Created by Wade Tregaskis
//  License: MIT

/// The paired verbs for one kind of menu: what Return does to open it, and
/// what Escape does to close it.
///
/// One value rather than two string literals at opposite ends of the codebase,
/// because the pair is read as a pair. The claims are published from different
/// places — the trigger publishes the opening verb while the menu is shut, the
/// presentation publishes the closing verb once it is up — and they drifted:
/// a `Picker` offered "open menu" and then "close drop-down menu", which reads
/// as two different surfaces rather than one opening and shutting.
struct MenuPresentationLabels {
    /// What Return does over the closed trigger.
    let open: String

    /// What Escape does while the menu is up.
    let close: String

    private init(noun: String) {
        self.open = "open \(noun)"
        self.close = "close \(noun)"
    }

    /// A `Picker`'s list of options, which drops out of the collapsed control.
    static let dropDown = Self(noun: "drop-down menu")

    /// A `Menu`'s pop-up, which is a menu and nothing more specific.
    static let popUp = Self(noun: "menu")
}
