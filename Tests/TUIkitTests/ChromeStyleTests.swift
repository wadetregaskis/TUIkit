//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ChromeStyleTests.swift
//
//  The app header and the status bar are drawn by two different renderers, out
//  of the view tree, from two different state objects — and they are looked at
//  together. So the thing worth pinning is not either renderer but the RELATION:
//  same rule, mirrored, and the same number of rows reserved as drawn.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Chrome style")
struct ChromeStyleTests {

    private func header(_ style: ChromeStyle, rows: Int = 1, width: Int = 40) -> FrameBuffer {
        let content = FrameBuffer(lines: (0..<rows).map { "Header \($0)" })
        return renderToBuffer(
            AppHeader(contentBuffer: content, style: style),
            context: makeRenderContext(width: width, height: 10))
    }

    private func statusBar(_ style: ChromeStyle, width: Int = 40) -> FrameBuffer {
        let bar = StatusBar(
            items: [StatusBarItem(shortcut: "q", label: "quit")], style: style)
        return renderToBuffer(bar, context: makeRenderContext(width: width, height: 10))
    }

    // MARK: - Reserved space is drawn space

    @Test("Every style draws exactly the rows it reserves")
    func heightsMatchWhatIsDrawn() {
        // The layout subtracts these heights from the page BEFORE either bar
        // renders, so a style that reserved one number and drew another would
        // overlap the content or leave a gap — and only on the styles nobody
        // ran.
        for style in ChromeStyle.allCases {
            for rows in 1...3 {
                #expect(
                    header(style, rows: rows).height == style.barHeight(contentRows: rows),
                    "\(style) header with \(rows) content rows")
            }
            let state = StatusBarState()
            state.style = style
            state.setItems([StatusBarItem(shortcut: "x", label: "test")])
            #expect(
                statusBar(style).height == state.height,
                "\(style) status bar: rendered \(statusBar(style).height), reserved \(state.height)")
        }
    }

    // MARK: - The two bars mirror each other

    @Test("The default rule is one rule, drawn on the page-facing side of each bar")
    func theRuleMirrors() {
        // The whole reason `ChromeStyle` is one type for both bars. The header's
        // rule is its LAST row and the status bar's is its FIRST, and they are
        // the same string — which is what makes a header and a footer read as
        // one frame rather than two unrelated bars.
        let head = header(.rule)
        let foot = statusBar(.rule)
        #expect(head.lines.last == foot.lines.first)
        #expect(head.lines.last?.stripped.allSatisfy { $0 == "─" } == true)
    }

    @Test("Compact draws no chrome at all")
    func compactIsBare() {
        let head = header(.compact)
        #expect(head.height == 1)
        #expect(head.lines[0].stripped.hasPrefix("Header 0"))
        #expect(statusBar(.compact).height == 1)
    }

    @Test("Bordered boxes both bars")
    func borderedBoxes() {
        for buffer in [header(.bordered), statusBar(.bordered)] {
            let first = buffer.lines.first?.stripped ?? ""
            let last = buffer.lines.last?.stripped ?? ""
            #expect(first.hasPrefix("╭") && first.hasSuffix("╮"), "\(first)")
            #expect(last.hasPrefix("╰") && last.hasSuffix("╯"), "\(last)")
            #expect(buffer.lines.allSatisfy { $0.strippedLength == 40 })
        }
    }

    @Test("Both bars default to the box")
    func theDefaultIsBordered() {
        // The default is a property of the app's look, and the two bars have
        // separate defaults in separate types — so it is exactly the kind of
        // thing that drifts apart unnoticed (a boxed header over a ruled
        // footer looks like a bug).
        #expect(AppHeaderState().style == .bordered)
        #expect(StatusBarState().style == .bordered)
        #expect(StatusBar(items: []).style == .bordered)
    }

    @Test("A boxed header lays its content out inside the walls")
    func borderedHeaderContentIsNotClippedByTheWall() {
        // Two halves that have to agree about one number, and used not to: the
        // modifier proposes the width the content lays out at, the renderer
        // boxes what comes back. Proposing the full terminal width and boxing
        // afterwards fed the last two cells of every header to the right wall
        // — on the Example, "TUIkit v0.6" for "TUIkit v0.6.0". So this drives
        // both halves, and looks at TRAILING text, which is where it shows.
        let width = 40
        for style in ChromeStyle.allCases {
            let state = AppHeaderState()
            state.style = style
            let context = makeRenderContext(width: width, height: 10) { environment, _ in
                environment.appHeader = state
            }
            _ = renderToBuffer(
                Text("page").appHeader {
                    HStack {
                        Text("Title")
                        Spacer()
                        Text("v1.0.0")
                    }
                },
                context: context)

            let boxed = renderToBuffer(
                AppHeader(contentBuffer: state.contentBuffer ?? FrameBuffer(), style: style),
                context: makeRenderContext(width: width, height: 10))
            let row = boxed.lines[style == .bordered ? 1 : 0].stripped
            #expect(row.contains("v1.0.0"), "\(style) clipped the trailing text: \(row)")
            #expect(boxed.lines.allSatisfy { $0.strippedLength == width }, "\(style)")
        }
    }

    /// The header is drawn across the terminal, but the modifier that lays its
    /// content out sits inside the view tree, where padding on the way down has
    /// already narrowed the context. Taking the width from there and padding to
    /// the drawn width leaves a trailing gap the size of that padding — the
    /// Example's one-column gutter put two columns of air on the right of every
    /// header and one on the left.
    @Test("A page's own padding does not push the header's content off centre")
    func headerIgnoresPaddingAboveIt() {
        let width = 40
        for gutter in [0, 1, 3] {
            let state = AppHeaderState()
            state.style = .bordered
            state.renderWidth = width
            let context = makeRenderContext(width: width, height: 10) { environment, _ in
                environment.appHeader = state
            }
            _ = renderToBuffer(
                Text("page")
                    .appHeader {
                        HStack {
                            Text("Left")
                            Spacer()
                            Text("Right")
                        }
                    }
                    .padding(.horizontal, gutter),
                context: context)

            let boxed = renderToBuffer(
                AppHeader(contentBuffer: state.contentBuffer ?? FrameBuffer(), style: .bordered),
                context: makeRenderContext(width: width, height: 10))
            let row = boxed.lines[1].stripped
            // Both ends flush against their walls, whatever the gutter was.
            #expect(row.hasPrefix("\u{2502}Left"), "gutter \(gutter): \(row)")
            #expect(row.hasSuffix("Right\u{2502}"), "gutter \(gutter): \(row)")
        }
    }

    @Test("A boxed header shifts its content's click targets inside the wall")
    func borderedHeaderShiftsRegions() {
        // The header content can hold a Button; boxing it moves those cells
        // right one and down one, and a region left where it was would take
        // clicks meant for the border.
        var content = FrameBuffer(lines: ["Header"])
        content.hitTestRegions = [
            HitTestRegion(offsetX: 0, offsetY: 0, width: 6, height: 1, handlerID: HitTestRegion.HandlerID(1))
        ]
        let ruled = renderToBuffer(
            AppHeader(contentBuffer: content, style: .rule),
            context: makeRenderContext(width: 40, height: 10))
        let boxed = renderToBuffer(
            AppHeader(contentBuffer: content, style: .bordered),
            context: makeRenderContext(width: 40, height: 10))
        #expect(ruled.hitTestRegions.first?.offsetX == 0)
        #expect(ruled.hitTestRegions.first?.offsetY == 0)
        #expect(boxed.hitTestRegions.first?.offsetX == 1)
        #expect(boxed.hitTestRegions.first?.offsetY == 1)
    }

    // MARK: - The scene modifiers

    @Test("One call sets both bars")
    func oneCallSetsBoth() {
        let scene = WindowGroup { Text("x") }.chromeStyle(.bordered)
        let resolved = (scene as? any RootChromeStyleProvidingScene)?.rootChromeStyle()
        #expect(resolved?.appHeader == .bordered)
        #expect(resolved?.statusBar == .bordered)
    }

    @Test("The two-argument spelling sets them apart")
    func twoArgumentsDiffer() {
        let scene = WindowGroup { Text("x") }
            .chromeStyle(appHeader: .compact, statusBar: .bordered)
        let resolved = (scene as? any RootChromeStyleProvidingScene)?.rootChromeStyle()
        #expect(resolved?.appHeader == .compact)
        #expect(resolved?.statusBar == .bordered)
    }

    @Test("Innermost wins, per bar")
    func innermostWinsPerBar() {
        // An inner call that only names one bar must not shadow an outer call
        // for the other — the two are resolved independently, which is what
        // lets `.chromeStyle(.rule)` act as a base with one bar overridden.
        let scene = WindowGroup { Text("x") }
            .chromeStyle(appHeader: .compact, statusBar: .compact)
            .chromeStyle(.bordered)
        let resolved = (scene as? any RootChromeStyleProvidingScene)?.rootChromeStyle()
        #expect(resolved?.appHeader == .compact, "the inner call is closer to the content")
        #expect(resolved?.statusBar == .compact)
    }

    @Test("It composes with palette, appearance and mouse support in either order")
    func composesWithTheOtherSceneModifiers() {
        let palette = SystemPalette(.amber)
        let appearance = Appearance(id: Appearance.ID(rawValue: "test"), borderStyle: .doubleLine)

        let chromeOutermost = WindowGroup { Text("x") }
            .palette(palette)
            .appearance(appearance)
            .mouseSupport(.standard)
            .chromeStyle(.bordered)
        let chromeInnermost = WindowGroup { Text("x") }
            .chromeStyle(.bordered)
            .palette(palette)
            .appearance(appearance)
            .mouseSupport(.standard)

        for scene in [AnySceneProbe(chromeOutermost), AnySceneProbe(chromeInnermost)] {
            #expect(scene.chrome?.appHeader == .bordered)
            #expect(scene.palette?.id == palette.id)
            #expect(scene.appearance?.id == appearance.id)
            #expect(scene.mouse != nil)
        }
    }
}

/// Reads every root-level scene override off one scene, so the composition test
/// asserts on all of them without repeating four casts per case.
@MainActor
private struct AnySceneProbe {
    let chrome: (appHeader: ChromeStyle?, statusBar: ChromeStyle?)?
    let palette: (any Palette)?
    let appearance: Appearance?
    let mouse: MouseSupport?

    init(_ scene: some Scene) {
        chrome = (scene as? any RootChromeStyleProvidingScene)?.rootChromeStyle()
        palette = (scene as? any RootPaletteOverrideProvidingScene)?.rootPaletteOverride()
        appearance = (scene as? any RootAppearanceOverrideProvidingScene)?.rootAppearanceOverride()
        mouse = (scene as? any MouseSupportProvidingScene)?.resolvedMouseSupport()
    }
}
