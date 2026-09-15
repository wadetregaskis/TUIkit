//  🖥️ TUIkit — Terminal UI Kit for Swift
//  IndeterminateGradientThemeTests.swift
//
//  The indeterminate `.gradient` motion's default stops come from the palette,
//  and every cache in front of the bar sees them change when the palette does.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("An indeterminate gradient's default follows the palette")
struct IndeterminateGradientThemeTests {

    private static func freshContext() -> TUIContext {
        TUIContext(
            lifecycle: LifecycleManager(firesEffects: false), keyEventDispatcher: KeyEventDispatcher(),
            preferences: PreferenceStorage(), stateStorage: StateStorage())
    }

    /// `view` drawn under `palette` in truecolor, `width` cells wide and one row tall,
    /// keeping its state in `tui` at one identity, so a second call with the same
    /// `tui` is the same bar rendered again.
    private func bar(
        _ view: some View, palette: any Palette, width: Int = 12, pictures: Bool = false, tui: TUIContext
    ) -> FrameBuffer {
        var environment = EnvironmentValues()
        environment.palette = palette
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.imageCellPixels = TerminalCellPixels(width: 16, height: 34)
        let context = RenderContext(
            availableWidth: width, availableHeight: 1, environment: environment,
            tuiContext: tui, identity: ViewIdentity(path: "Root"))
        tui.stateStorage.beginRenderPass()
        defer { tui.stateStorage.endRenderPass() }
        return ColorDepth.withCurrent(.truecolor) {
            guard pictures else { return renderToBuffer(view, context: context) }
            return KittyGraphics.withSupport(true) { renderToBuffer(view, context: context) }
        }
    }

    /// Every truecolor foreground of a line, in cell order. The same reader as
    /// `GradientPaletteResolutionTests`' `inks`.
    private func inks(_ line: String) -> [String] {
        var found: [String] = []
        var rest = Substring(line)
        while let start = rest.range(of: "\u{1B}[38;2;") {
            rest = rest[start.upperBound...]
            guard let end = rest.firstIndex(of: "m") else { break }
            found.append(String(rest[rest.startIndex..<end]))
            rest = rest[rest.index(after: end)...]
        }
        return found
    }

    /// The probe with its error role moved, and nothing else.
    private var editedProbe: ThemeProbePalette {
        var palette = ThemeProbePalette()
        palette.error = .rgb(200, 0, 200)
        return palette
    }

    @Test("A default .gradient bar starts at the palette's error colour, not the old rainbow")
    func defaultStartsAtTheErrorRole() {
        let line =
            bar(
                ProgressView().indeterminateStyle(.gradient()).frame(width: 12),
                palette: ThemeProbePalette(), tui: Self.freshContext()
            ).lines.first ?? ""
        let painted = inks(line)
        #expect(painted.first == "230;50;50", "\(painted)")
        #expect(!painted.contains("180;30;80"), "the rainbow's first stop: \(painted)")
    }

    @Test("The default stops are the palette's error, warning, success, info and accent")
    func defaultStopsAreTheRoles() {
        let palette = ThemeProbePalette()
        #expect(
            IndeterminateRenderer.defaultGradient(in: palette).stops.map(\.color)
                == [palette.error, palette.warning, palette.success, palette.info, palette.accent])
    }

    @Test("A bar's kept cycle is rebuilt when the palette's error role changes")
    func keptCycleFollowsARoleEdit() {
        let tui = Self.freshContext()
        let view = ProgressView().indeterminateStyle(.gradient())
        let first = inks(bar(view, palette: ThemeProbePalette(), tui: tui).lines.first ?? "")
        #expect(first.first == "230;50;50", "\(first)")
        let second = inks(bar(view, palette: editedProbe, tui: tui).lines.first ?? "")
        #expect(second.first == "200;0;200", "\(second)")
    }

    /// The same hole for a caller's own stops: the kept cycle was keyed on the style
    /// as written, where a role is a name and not a colour.
    @Test("A bar's kept cycle is rebuilt when a role the caller's stops name changes")
    func keptCycleFollowsACallersRoleStop() {
        let tui = Self.freshContext()
        let view = ProgressView().indeterminateStyle(
            .gradient(Gradient(colors: [.palette.error, .palette.info])))
        let first = inks(bar(view, palette: ThemeProbePalette(), tui: tui).lines.first ?? "")
        #expect(first.first == "230;50;50", "\(first)")
        let second = inks(bar(view, palette: editedProbe, tui: tui).lines.first ?? "")
        #expect(second.first == "200;0;200", "\(second)")
    }

    /// A picture is reused whenever its signature is unchanged, so the signature has
    /// to carry the stops the default filled in, not the `nil` the style was written
    /// with; rebuilding the cycle alone would draw the old palette's pictures again.
    @Test("A picture bar sends new pictures when the palette's error role changes")
    func pictureBarFollowsARoleEdit() {
        let tui = Self.freshContext()
        let view = ProgressView().indeterminateStyle(.gradient())
        let first = bar(view, palette: ThemeProbePalette(), width: 20, pictures: true, tui: tui)
        #expect(
            first.lines.first?.unicodeScalars.contains(.terminalImagePlaceholder) == true,
            "the picture path was not taken")
        #expect(tui.terminalImageStore.takePending().contains("a=t,"))
        _ = bar(view, palette: editedProbe, width: 20, pictures: true, tui: tui)
        #expect(tui.terminalImageStore.takePending().contains("a=t,"), "the old palette's pictures were kept")
    }

    /// Every other default a bar draws with carries its role's alpha, and so does this
    /// one, so a faded palette's status roles send a default `.gradient` bar down the
    /// per-frame path, where each frame claims its own alpha.
    @Test("A default .gradient bar under a faded palette is not opaque throughout")
    func fadedDefaultIsNotOpaque() {
        #expect(
            !IndeterminateRenderer.isOpaqueThroughout(
                style: .gradient(), fillColor: .rgb(1, 1, 1), backgroundColor: .rgb(2, 2, 2),
                accentColor: .rgb(3, 3, 3), palette: FadedAll()))
    }
}
