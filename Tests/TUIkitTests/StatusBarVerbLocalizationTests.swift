//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StatusBarVerbLocalizationTests.swift
//
//  The verbs the framework publishes for the two common keys — what Return does
//  to the focused control, what Escape does over the surface above it.
//
//  These are the framework's OWN words rather than the app's, so nothing in an
//  app's own translation table can fix them and nothing in `LocalizedTitleTests`
//  covers them: that suite checks that a title the CALLER wrote is looked up,
//  and these have no caller. They were hardcoded English literals, which is
//  invisible in an English-shaped review and wrong in six languages.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

@Suite("Status bar verb localization")
struct StatusBarVerbLocalizationTests {

    /// A service pointed at its own config directory, so setting a language
    /// here can never re-point the shared one every other suite reads.
    private func isolated(_ language: LocalizationService.Language) -> LocalizationService {
        let service = LocalizationService(
            configDirectoryPath: NSTemporaryDirectory() + "tuikit-verbs-\(UUID().uuidString)")
        service.setLanguage(language)
        return service
    }

    // Note on what this suite deliberately does NOT assert: "every verb
    // resolves to something other than its key, in every language". That
    // assertion looks like a completeness check and is not one, which is worth
    // recording because the first draft of this file made exactly that mistake.
    // `string(for:)` falls back to ENGLISH before falling back to the key, so
    // deleting `statusbar.goBack` from de.json still resolves — to "go back" —
    // and the check passes while a German app shows an English word. That was
    // mutation-tested, not reasoned about.
    //
    // Table completeness across all seven languages is therefore left where it
    // can actually be enforced, against the files rather than through the
    // service: `LocalizationKeyConsistencyTests.everyLanguageHasEnglishKeys`
    // and `.allStatusBarKeysExist`, which do catch that deletion. What is left
    // here is what those cannot see — whether the words are RIGHT, and whether
    // the composition around them works.

    /// The words themselves. A table can be complete and still wrong, and the
    /// consistency suite cannot tell: it compares key sets, never values.
    @Test("the verbs say what they mean")
    func verbsReadCorrectly() {
        #expect(isolated(.english).string(for: LocalizationKey.StatusBar.goBack) == "go back")
        #expect(isolated(.german).string(for: LocalizationKey.StatusBar.goBack) == "zurück")
        #expect(isolated(.japanese).string(for: LocalizationKey.StatusBar.goBack) == "戻る")
        #expect(isolated(.french).string(for: LocalizationKey.StatusBar.submit) == "envoyer")
        #expect(isolated(.spanish).string(for: LocalizationKey.StatusBar.dismiss) == "cerrar")
        #expect(isolated(.italian).string(for: LocalizationKey.StatusBar.toggle) == "commuta")
        #expect(
            isolated(.simplifiedChinese).string(for: LocalizationKey.StatusBar.clearSelection)
                == "清除选择")
    }

    /// The menu pair is a template plus a noun, and the point of the template is
    /// that a translation may put the noun anywhere — trailing in German,
    /// particle-marked in Japanese. Composing with `+` in Swift would have made
    /// every language use English word order.
    @Test("the menu verb puts the noun where the language wants it")
    func menuTemplateRespectsWordOrder() {
        func opened(_ language: LocalizationService.Language, noun: LocalizationKey.StatusBar)
            -> String
        {
            let service = isolated(language)
            return LocalizedStringKey.substituting(
                [service.string(for: noun)], into: service.string(for: .openMenu))
        }

        #expect(opened(.english, noun: .menuPopUp) == "open menu")
        #expect(opened(.english, noun: .menuDropDown) == "open drop-down menu")
        // The noun LEADS in both of these, which is the whole reason the
        // template exists rather than a concatenation.
        #expect(opened(.german, noun: .menuPopUp) == "Menü öffnen")
        #expect(opened(.japanese, noun: .menuDropDown) == "ドロップダウンメニューを開く")
    }

    /// ``MenuPresentationLabels`` resolves through the shared service, so this
    /// checks the composition rather than a language — the shared service is
    /// process-wide state other suites read, and re-pointing it would race them.
    @Test("the menu labels pair an open and a close verb over one noun")
    func menuLabelsComposeAsAPair() {
        let service = LocalizationService.shared
        let dropDown = service.string(for: LocalizationKey.StatusBar.menuDropDown)
        let popUp = service.string(for: LocalizationKey.StatusBar.menuPopUp)

        #expect(MenuPresentationLabels.dropDown.open.contains(dropDown))
        #expect(MenuPresentationLabels.dropDown.close.contains(dropDown))
        #expect(MenuPresentationLabels.popUp.open.contains(popUp))
        #expect(MenuPresentationLabels.popUp.close.contains(popUp))
        // Opening and closing must not read the same, which is what a template
        // that dropped its verb would produce.
        #expect(MenuPresentationLabels.popUp.open != MenuPresentationLabels.popUp.close)
        // No placeholder survives into what the user reads.
        #expect(!MenuPresentationLabels.dropDown.open.contains("%@"))
    }

    /// The two factories that had no key overload at all, so a literal could
    /// never be one — the last place in the status bar where that was true.
    @MainActor
    @Test("the Escape and Return entries take a title literal as a key")
    func commonKeyEntriesTakeAKey() {
        LocalizationService.shared.register(translations: [
            "en": ["test.statusbar.commonkey": "Localized!"]
        ])
        #expect(SystemStatusBarItem.escape(label: "test.statusbar.commonkey").label == "Localized!")
        #expect(
            SystemStatusBarItem.returnKey(label: "test.statusbar.commonkey").label == "Localized!")
        // …and a computed `String` is still shown as written.
        let computed = "test.statusbar" + ".commonkey"
        #expect(SystemStatusBarItem.escape(label: computed).label == computed)
        #expect(SystemStatusBarItem.returnKey(label: computed).label == computed)
    }
}
