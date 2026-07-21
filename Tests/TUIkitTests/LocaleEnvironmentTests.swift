//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LocaleEnvironmentTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

private struct LocaleProbe: View {
    @Environment(\.locale) var locale
    var body: some View { Text(locale.identifier) }
}

@MainActor
@Suite("locale environment")
struct LocaleEnvironmentTests {
    @Test("Defaults to autoupdatingCurrent and is a settable stored key")
    func defaultAndSettable() {
        var environment = EnvironmentValues()
        #expect(environment.locale == Locale.autoupdatingCurrent)
        environment.locale = Locale(identifier: "fr_FR")
        #expect(environment.locale.identifier == "fr_FR", "the key stores an override")
    }

    @Test("An .environment(\\.locale) override reaches the subtree")
    func overrideReachesSubtree() {
        let context = makeBareRenderContext(width: 40, height: 3)
        let view = LocaleProbe().environment(\.locale, Locale(identifier: "fr_FR"))
        let buffer = renderToBuffer(view, context: context)
        #expect(
            buffer.lines.joined().contains("fr_FR"),
            "a subtree reads the overridden locale — so Table/List number chrome re-locales")
    }
}
