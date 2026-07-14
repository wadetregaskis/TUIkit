//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LocalizedStringTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// Tests for the `LocalizedString` view.
///
/// `LocalizedString` is a thin wrapper — its body is
/// `Text(LocalizationService.shared.string(for: key))` — so these verify it
/// faithfully surfaces whatever the (separately-tested) `LocalizationService`
/// resolves, including the missing-key fallback. The service is used as the
/// oracle so the tests don't hard-code specific translations.
@MainActor
@Suite("LocalizedString")
struct LocalizedStringTests {

    private func makeContext(width: Int = 40, height: Int = 3) -> RenderContext {
        let tui = TUIContext()
        var env = EnvironmentValues()
        env.focusManager = FocusManager()
        env.applyRuntimeServices(from: tui)
        return RenderContext(
            availableWidth: width, availableHeight: height, environment: env, tuiContext: tui)
    }

    @Test(
        "Renders exactly what the localization service resolves for the key",
        arguments: ["button.ok", "error.invalid_input", "totally.unknown.key.abc"]
    )
    func delegatesToService(key: String) {
        let expected = LocalizationService.shared.string(for: key)
        let buffer = renderToBuffer(LocalizedString(key), context: makeContext())
        let rendered = buffer.lines.joined().stripped
        #expect(rendered.contains(expected), "key \(key): expected '\(expected)' in '\(rendered)'")
    }

    @Test("An unknown key falls back to the key itself")
    func unknownKeyFallsBack() {
        let key = "no.such.key.xyz123"
        // The fallback contract is the service's; confirm it, then confirm
        // LocalizedString surfaces it.
        #expect(LocalizationService.shared.string(for: key) == key)
        let buffer = renderToBuffer(LocalizedString(key), context: makeContext())
        #expect(buffer.lines.joined().stripped.contains(key))
    }
}
