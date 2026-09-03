//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ControlSymbolInitializerTests.swift
//
//  `Button("Save", systemImage: …) { }` and its siblings on Toggle, Picker and
//  ContentUnavailableView.
//
//  The assertions are deliberately host-independent. Whether an SF Symbol
//  becomes a glyph depends on the platform and the terminal's font
//  (``SFSymbol/canRender(named:)``), so a test that expected to see one would
//  pass on this machine and fail in CI. What CAN be pinned everywhere:
//
//  * a name no font will ever carry renders EXACTLY the plain control — the
//    fallback is the whole reason these initializers are allowed to exist, and
//    it is what stops an unrenderable icon from leaving a hole or a stray gap;
//  * the title survives, whichever overload the call binds to.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Control systemImage initializers")
struct ControlSymbolInitializerTests {

    /// A symbol name no SF Symbols release has ever had, so `canRender` is
    /// `false` on every host including one with the font installed.
    private static let absentSymbol = "tuikit.no.such.symbol"

    private func rendered(_ view: some View, width: Int = 40, height: Int = 8) -> [String] {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: width, availableHeight: height,
            environment: environment, tuiContext: tui)
        return renderToBuffer(view, context: context).lines.map(\.stripped)
    }

    // MARK: - The fallback

    @Test("An unrenderable symbol leaves the control exactly as it was")
    func absentSymbolMatchesPlainControl() {
        #expect(
            !SFSymbol.canRender(named: Self.absentSymbol),
            "the premise: this name must not resolve anywhere")

        #expect(
            rendered(Button("Save", systemImage: Self.absentSymbol) {})
                == rendered(Button("Save") {}),
            "Button")

        #expect(
            rendered(Toggle("Wi-Fi", systemImage: Self.absentSymbol, isOn: .constant(true)))
                == rendered(Toggle("Wi-Fi", isOn: .constant(true))),
            "Toggle")

        #expect(
            rendered(
                Picker("Theme", systemImage: Self.absentSymbol, selection: .constant(1)) {
                    Text("Dark").tag(1)
                })
                == rendered(
                    Picker("Theme", selection: .constant(1)) { Text("Dark").tag(1) }),
            "Picker")

        #expect(
            rendered(ContentUnavailableView("Nothing here", systemImage: Self.absentSymbol))
                == rendered(ContentUnavailableView("Nothing here")),
            "ContentUnavailableView")
    }

    @Test("A role still reaches the button")
    func roleSurvives() {
        #expect(
            rendered(Button("Delete", systemImage: Self.absentSymbol, role: .destructive) {})
                == rendered(Button("Delete", role: .destructive) {}),
            "Button(role:)")
    }

    @Test("The description still reaches ContentUnavailableView")
    func descriptionSurvives() {
        let lines = rendered(
            ContentUnavailableView(
                "Nothing here", systemImage: Self.absentSymbol,
                description: Text("Add something to get started.")),
            width: 44)
        #expect(lines.contains { $0.contains("Nothing here") })
        #expect(lines.contains { $0.contains("Add something") })
    }

    // MARK: - A renderable symbol reaches the label

    /// Host-dependent by nature — the SF Symbols font is absent by default and
    /// never present on Linux — so the assertion is the AGREEMENT between what
    /// was drawn and what ``SFSymbol/canRender(named:)`` says can be, rather
    /// than a hard-coded glyph. That makes it mean something on either kind of
    /// machine: where a symbol resolves it pins that the icon really appears,
    /// and where it does not, that the control is byte-identical to the plain
    /// one. Same shape as `ImageTests.symbolDrawsWhenRenderable`; a `#require`
    /// here would report a *failure* on every Linux run instead.
    @Test("A renderable symbol widens the control by its icon")
    func renderableSymbolAddsAnIcon() {
        let withIcon = rendered(Button("Save", systemImage: "star") {})
        let without = rendered(Button("Save") {})
        #expect(
            (withIcon != without) == SFSymbol.canRender(named: "star"),
            "the icon appears exactly where it can be drawn")
        #expect(
            withIcon.contains { $0.contains("Save") },
            "and the title must survive beside it")
    }
}
