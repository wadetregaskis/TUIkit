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

    /// Composes the pair from the localized verb and the localized noun.
    ///
    /// A verb template with `%@` rather than two whole phrases per menu kind,
    /// which keeps the pairing this type exists for AND lets a translation put
    /// the noun where its own grammar wants it — German trails the verb
    /// (`"%@ öffnen"`) and Japanese needs a particle (`"%@を開く"`), so building
    /// `"open " + noun` in Swift would have been English word order wearing a
    /// translation. Substitution goes through ``LocalizedStringKey`` rather
    /// than a local `replacingOccurrences`, so these read `%@` exactly as every
    /// other interpolated key does, positional `%1$@` included.
    private init(noun: LocalizationKey.StatusBar) {
        let service = LocalizationService.shared
        let name = [service.string(for: noun)]
        self.open = LocalizedStringKey.substituting(name, into: service.string(for: .openMenu))
        self.close = LocalizedStringKey.substituting(name, into: service.string(for: .closeMenu))
    }

    // Computed, not `static let`. These used to be constants, which was right
    // while they were English literals and wrong the moment they became
    // lookups: a `static let` resolves once, so an app that switched language
    // at runtime would keep the menu verbs it started with while every other
    // string followed. The tree is rebuilt every frame, so resolving per access
    // is what makes the switch land on the next one — the same eagerness rule
    // the controls follow. Two lookups per focused menu per frame, each a
    // dictionary hit under a lock already taken for every other label.

    /// A `Picker`'s list of options, which drops out of the collapsed control.
    static var dropDown: Self { Self(noun: .menuDropDown) }

    /// A `Menu`'s pop-up, which is a menu and nothing more specific.
    static var popUp: Self { Self(noun: .menuPopUp) }
}
