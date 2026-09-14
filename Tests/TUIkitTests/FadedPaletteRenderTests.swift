//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FadedPaletteRenderTests.swift
//
//  A whole page rendered under a palette whose every slot is translucent — the
//  second tier of §16.1, which `Palette` being a public protocol of plain
//  `var …: Color { get }` members makes reachable in one type.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A page under a wholly faded palette")
struct FadedPaletteRenderTests {

    /// **These tests assert by not trapping, and that is deliberate.**
    ///
    /// A translucent colour reaching `ANSIRenderer` trips a debug assertion — which is
    /// a trap, not a throw, so an unmigrated paint site takes the whole suite down
    /// with a message naming the alpha. There is no way to `#expect` that and no need
    /// to: the run either completes or it does not.
    ///
    /// It matters most for the SURFACE colours. §39 made them carry a faded page's
    /// alpha, and the argument for leaving them dropping had been "no migrated paint
    /// site reaches them, so nothing is silently wrong today" — an argument from
    /// inspection. This is the same claim asserted by the suite instead, and it is the
    /// only thing standing between carrying the alpha and a debug build that traps on
    /// somebody's theme.
    ///
    /// The scrollbars were hidden here until a bar could claim (§40.2). They are drawn
    /// now, and asserted more closely than the rest: a bar's arrows say exactly where
    /// it is, so each arrow's cell is checked for owing the alpha of the colours
    /// painted in it — not merely for somebody having claimed something.
    private func render<V: View>(
        _ view: V, palette: any Palette = FadedAll(), width: Int = 40, height: Int = 14
    ) -> FrameBuffer {
        renderToBuffer(view, context: context(palette: palette, width: width, height: height))
    }

    /// Every glyph set's toggle, focused, as a checkbox and as a switch, under a pulse
    /// and a blink: each renders with its one run, and — since `IndicatorCycle.claims(at:)`
    /// claims while the indicator breathes — its frames agree about alpha, which that
    /// asserts in a debug build (§57, §58).
    @Test(
        "Focused toggles in every glyph set render under a faded palette",
        arguments: [TextCursorStyle.Animation.pulse, .blink])
    func focusedTogglesDraw(animation: TextCursorStyle.Animation) {
        func focused<V: View>(_ view: V) -> FrameBuffer {
            renderToBuffer(
                view,
                context: context(palette: FadedAll(), width: 30, height: 3) {
                    // A focus manager of its own, so the lone toggle takes the focus.
                    $0.focusManager = FocusManager()
                    $0.selectionIndicatorStyle = animation
                })
        }
        for glyphs in [ToggleCharacterSet.unicode, .ascii, .emoji] {
            for isSwitch in [false, true] {
                let toggle = Toggle("Enable", isOn: .constant(true)).toggleCharacterSet(glyphs)
                let drawn = isSwitch ? focused(toggle.toggleStyle(.switch)) : focused(toggle)
                #expect(
                    drawn.animatedCells.count == 1,
                    "\(glyphs) \(isSwitch ? "switch" : "checkbox"): not focused and breathing")
            }
        }
    }

    /// A caret on a selected character draws, in its blink-OFF frame, that character in
    /// the selection's text colour — `readableText(on:)`, a palette slot that keeps its
    /// alpha — and handed it to the emitter unspent (§60). Every shape and animation, so
    /// the frames that draw the character are all built; and the selected cell beside
    /// the caret still claims its text's alpha over the highlight's opaque field.
    @Test("A text field's caret on a selected character draws under a faded palette")
    func textFieldCaretOnSelectionDraws() throws {
        let palette = FadedAll()
        let surface = palette.fieldBackground.resolve(with: palette)
        let selection = TextFieldContentRenderer.selectionColors(palette: palette, background: surface)
        try #require(!selection.foreground.isOpaque, "the premise: the selection's text is faded")
        let renderer = TextFieldContentRenderer(
            prompt: nil, isDisabled: false, displayCharacter: { $0 }, surface: surface,
            contentForeground: nil)
        for shape in TextCursorStyle.Shape.allCases {
            for animation in TextCursorStyle.Animation.allCases {
                // The caret on "b", with "b" and "c" selected — as a leftward drag leaves it.
                let content = renderer.buildContent(
                    text: "abcdef", cursorPosition: 1, selectionRange: 1..<3, isFocused: true,
                    palette: palette, cursorStyle: TextCursorStyle(shape: shape, animation: animation),
                    cursorTimer: CursorTimer?.none, contentWidth: 10)
                let owes = content.claims
                    .filter { $0.offsetX <= 2 && 2 < $0.offsetX + $0.width }
                    .reduce((ink: 1.0, field: 1.0)) { ($0.ink * $1.inkOpacity, $0.field * $1.fieldOpacity) }
                #expect(
                    owes.ink == owed(selection.foreground) && owes.field == 1,
                    "\(shape) \(animation): the selected cell owes \(owes)")
            }
        }
    }

    private func context(
        palette: any Palette, width: Int, height: Int,
        configure: (inout EnvironmentValues) -> Void = { _ in }
    ) -> RenderContext {
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.palette = palette
        environment.applyRuntimeServices(from: tuiContext)
        configure(&environment)
        return RenderContext(
            availableWidth: width, availableHeight: height,
            environment: environment, tuiContext: tuiContext
        ).isolatingRenderCache()
    }

    /// `fieldBackground` is what a `TextField` draws its well in, and
    /// `liftedBackground` what a `TabView` body and the app header's strip use. Both
    /// are derived surfaces rather than stated slots, so both are new since §39.
    @Test("Fields, tab bodies and wells draw under a faded palette")
    func surfacesDraw() {
        let drawn = render(
            VStack(alignment: .leading) {
                TextField("name", text: .constant("value"))
                TabView(selection: .constant(0)) {
                    Tab("one", value: 0) { Text("first") }
                    Tab("two", value: 1) { Text("second") }
                }
                Toggle("switch", isOn: .constant(true))
                Slider(value: .constant(0.5), in: 0...1)
            })
        #expect(!drawn.lines.isEmpty)
        // Something must have claimed: a page whose every colour is at alpha 128 and
        // whose regions are empty would mean the alpha went nowhere at all.
        #expect(!drawn.opacityRegions.isEmpty, "nothing claimed under a faded palette")
    }

    /// The row paints — selection marks, fills, the cursor row — plus the chrome every
    /// container draws from `palette.border`.
    @Test("Lists, tables and boxes draw under a faded palette")
    func containersDraw() {
        struct Row: Identifiable, Hashable {
            let id: Int
            let name: String
        }
        let rows = (0..<3).map { Row(id: $0, name: "row\($0)") }
        let drawn = render(
            VStack(alignment: .leading) {
                List(selection: .constant(Set([0]))) {
                    ForEach(rows) { Text($0.name) }
                }
                Table(rows) { TableColumn("Name") { $0.name } }
                Text("boxed").padding().border()
            })
        #expect(!drawn.lines.isEmpty)
        #expect(!drawn.opacityRegions.isEmpty)
    }

    /// The one that would have caught a surface reaching a track: a `ProgressView` and
    /// a `Gauge` take three palette colours each, and a `Picker`'s popup draws chrome
    /// from `border` over a well from `fieldBackground`.
    @Test("Indicators and popups draw under a faded palette")
    func indicatorsDraw() {
        let drawn = render(
            VStack(alignment: .leading) {
                ProgressView(value: 0.4)
                ProgressView()
                Gauge(value: 0.6) { Text("load") }
                Gauge(value: 0.6) { Text("dial") }.gaugeStyle(.accessoryCircular)
                Picker("pick", selection: .constant(1)) {
                    Text("one").tag(1)
                    Text("two").tag(2)
                }
            })
        #expect(!drawn.lines.isEmpty)
        #expect(!drawn.opacityRegions.isEmpty)
    }

    // MARK: - The scrollbars

    /// Both of a scroll view's bars, and the corner where they meet — which is
    /// painted in the track colour with nothing drawn in it, so it owes a field and
    /// no ink.
    @Test("A scroll view's bars and their corner owe what they painted")
    func scrollViewBarsClaim() {
        let palette = FadedAll()
        let drawn = render(
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading) {
                    ForEach(0..<30, id: \.self) { index in
                        Text("row \(index) " + String(repeating: "x", count: 60))
                    }
                }
            }
            .scrollIndicators(.visible),
            palette: palette, width: 30, height: 10)
        expectArrowsClaimed(["▲", "▼", "◀", "▶"], in: drawn, palette: palette)
        let corner = owed(atColumn: drawn.width - 1, row: drawn.height - 1, in: drawn)
        #expect(
            corner.ink == 1 && corner.field == owed(ScrollbarColors.track(in: palette)),
            "the corner owes \(corner): \(drawn.lines.map(\.stripped))")
    }

    /// A list's bar and a table's, on both of the table's paths: the multi-line one
    /// meters its bar in lines and merges it through code of its own.
    @Test("List and table bars owe what they painted")
    func listAndTableBarsClaim() {
        struct Row: Identifiable, Hashable {
            let id: Int
            let name: String
        }
        let rows = (0..<30).map { Row(id: $0, name: "row\($0)") }
        let palette = FadedAll()
        let list = render(
            List(selection: .constant(Set<Int>())) { ForEach(rows) { Text($0.name) } },
            palette: palette, height: 10)
        expectArrowsClaimed(["▲", "▼"], in: list, palette: palette)
        let table = render(
            Table(rows) { TableColumn("Name") { $0.name } }, palette: palette, height: 10)
        expectArrowsClaimed(["▲", "▼"], in: table, palette: palette)
        let wrapped = render(
            Table(rows) { TableColumn("Name") { "\($0.name)\nsecond" }.lineLimit(2) },
            palette: palette, height: 10)
        expectArrowsClaimed(["▲", "▼"], in: wrapped, palette: palette)
    }

    /// A drop-down's bar, in both of the popup's arms.
    ///
    /// The breathing arm once stated none of its BORDER's claims — the border's alpha
    /// moved with the pulse, and a claim is one alpha for every frame — and the bar was
    /// nearly left out with it. The bar does not breathe, so its claim holds in every
    /// frame. That arm is asserted under a palette that fades only the track, so the
    /// bar's claims are the only ones in play; the border's breath is its own test.
    @Test("A drop-down's bar owes what it painted, still or breathing")
    func dropdownBarClaims() {
        for (palette, animation) in [
            (FadedAll() as any Palette, TextCursorStyle.Animation.none), (FadedTrack(), .pulse),
        ] {
            let popup = DropdownMenu.popup(
                DropdownMenu.Configuration(
                    rows: (0..<20).map { .option(" item \($0)", claims: []) }, highlightedRow: 0,
                    innerWidth: 12, scroll: ScrollAxis(), followHighlight: false,
                    autoRepeatToken: "faded-dropdown"),
                context: context(palette: palette, width: 30, height: 10) {
                    $0.selectionIndicatorStyle = animation
                    // Room for six of the twenty rows, so the popup scrolls and draws
                    // its bar. The default budget is 24 lines, and every row fits.
                    $0.overlayContentHeight = 8
                },
                onHover: { _ in }, onActivate: { _ in }, onDismiss: {})
            #expect(
                popup.animatedCells.isEmpty == (animation == TextCursorStyle.Animation.none),
                "the \(animation) arm is the one being asserted")
            expectArrowsClaimed(["▲", "▼"], in: popup, palette: palette)
        }
    }

    /// An open drop-down's border breathes toward the accent. Under a faded tint its
    /// bright end kept the tint's alpha while its dim end spent it, so no one claim could
    /// describe the breath, none was stated, and the frames replayed the raw accent at
    /// full strength (§64). Both ends are spent now: the bright frame is the accent
    /// spent over the page, and with every frame opaque the border claims nothing.
    @Test("A drop-down's breathing border spends a faded accent at both ends")
    func dropdownBorderBreathSpends() throws {
        try withColorDepth(.truecolor) {
            let palette = TintedPalette(base: SystemPalette.default, tint: Color.red.opacity(0.5))
            let popup = DropdownMenu.popup(
                DropdownMenu.Configuration(
                    rows: (0..<3).map { .option(" item \($0)", claims: []) }, highlightedRow: 0,
                    innerWidth: 12, scroll: ScrollAxis(), followHighlight: false,
                    autoRepeatToken: "faded-dropdown-border"),
                context: context(palette: palette, width: 30, height: 10) {
                    $0.selectionIndicatorStyle = .pulse
                },
                onHover: { _ in }, onActivate: { _ in }, onDismiss: {})
            let top = try #require(popup.animatedCells.first { $0.offsetY == 0 }, "the border breathes")
            let spent = code(palette.accent.spendingAlpha(over: palette.background), palette)
            #expect(top.frames[0].contains(spent), "the bright frame: \(top.frames[0].debugDescription)")
            #expect(popup.opacityRegions.isEmpty, "\(popup.opacityRegions)")
        }
    }

    /// The ✓ beside a drop-down's current value, drawn in the palette accent by the
    /// layer ABOVE the renderer — so it is neither the chrome's claim nor a row the
    /// renderer painted, and it reached the emitter with a faded accent's alpha on it.
    /// It trapped on six of the example's pages, every one of them a `Picker`, and no
    /// test here opened a menu through `attach` — the two cases above build a
    /// `Configuration` directly, which is the layer past where the marker is made.
    ///
    /// Asserted on the cell as well as by not trapping: the marker's own cell owes the
    /// accent's alpha, and no cell of the label beside it owes anything, so the claim
    /// is the marker's and not a rectangle thrown over the row.
    @Test("A drop-down option's selected marker owes the faded accent")
    func dropdownSelectedMarkerClaims() throws {
        let palette = FadedAll()
        var buffer = FrameBuffer(lines: [String(repeating: " ", count: 20)])
        DropdownMenu.attach(
            DropdownMenu.OptionMenu(
                entries: [
                    .option(label: "alpha", isSelected: false),
                    .option(label: "beta", isSelected: true),
                    .divider,
                    .option(label: "gamma", isSelected: false),
                ],
                highlightedOption: 0, scroll: ScrollAxis(), followHighlight: false,
                autoRepeatToken: "faded-marker", isEnabled: true),
            to: &buffer,
            context: context(palette: palette, width: 24, height: 10),
            onHover: { _ in }, onActivate: { _ in }, onDismiss: {})

        let popup = try #require(buffer.overlays.first?.content, "the menu is attached")
        let marker = cells(of: Character(DropdownMenu.selectedMarker), in: popup)
        #expect(
            marker.count == 1,
            "one row is selected:\n\(popup.lines.map(\.stripped).joined(separator: "\n"))")
        let cell = try #require(marker.first)
        #expect(
            owed(atColumn: cell.column, row: cell.row, in: popup).ink == owed(palette.accent),
            "the marker's cell owes the accent's alpha")
        // The label's first letter, two columns along, is drawn in nothing faded.
        #expect(
            owed(atColumn: cell.column + 2, row: cell.row, in: popup).ink == 1,
            "the claim covers the marker only")
    }

    /// A list row's badge is the one text the LIST draws itself — everything else on
    /// the row is a child buffer that claims for itself — and it is drawn in
    /// `foregroundTertiary`, which a faded palette fades by derivation. It trapped
    /// (§68.2), and the claim now comes from the same arithmetic that places the
    /// glyphs, because `max(1, …)` on the fill means a narrow row does not put the
    /// badge where counting back from the right edge says it does.
    @Test("A list row's badge owes its faded ink, on its own cells")
    func listBadgeClaims() throws {
        let palette = FadedAll()
        let drawn = render(
            List(selection: .constant(Int?.none)) {
                Text("alpha").badge(7)
                Text("beta")
            },
            palette: palette, width: 24, height: 6)

        let badge = try #require(cells(of: "7", in: drawn).first, """
            the badge is drawn:
            \(drawn.lines.map(\.stripped).joined(separator: "\n"))
            """)
        #expect(
            owed(atColumn: badge.column, row: badge.row, in: drawn).ink
                == owed(palette.foregroundTertiary),
            "the badge's cell owes the tertiary rung's alpha")
        // The cell after it is the row's trailing pad — a bare space, which must owe
        // no INK at all, or what is behind the row shows through where it drew a pad.
        #expect(
            owed(atColumn: badge.column + 1, row: badge.row, in: drawn).ink == 1,
            "the pad beside it owes no ink")
    }

    /// An `Image`'s placeholder centres a spinner glyph in `palette.accent` and its
    /// caption in `foregroundSecondary`; the failure path centres `palette.error`. All
    /// three reached the emitter faded (§68.3). The spinner is a composed `Spinner`
    /// now, which claims its own cell, and the frame that centres it carries the claim
    /// there; the pad beside it is still blank and claims nothing.
    ///
    /// Effects are pinned off, as `ImageRenderTests` explains: with them firing, a
    /// missing file's load can fail fast enough to land on the error path instead of
    /// the placeholder, which made the `"⠋"` assertions flake under contention.
    @Test("An image placeholder's spinner and caption owe what they were drawn in")
    func imagePlaceholderClaims() throws {
        let palette = FadedAll()
        var environment = EnvironmentValues()
        environment.palette = palette
        let tuiContext = TUIContext(
            lifecycle: LifecycleManager(firesEffects: false),
            keyEventDispatcher: KeyEventDispatcher(),
            preferences: PreferenceStorage())
        environment.applyRuntimeServices(from: tuiContext)
        let drawn = renderToBuffer(
            Image(.file("/does-not-exist.png")),
            context: RenderContext(
                availableWidth: 20, availableHeight: 6,
                environment: environment, tuiContext: tuiContext
            ).isolatingRenderCache())

        let screen = drawn.lines.map(\.stripped)
        let spinner = try #require(
            cells(of: "⠋", in: drawn).first, "the placeholder's spinner:\n\(screen.joined(separator: "\n"))")
        #expect(
            owed(atColumn: spinner.column, row: spinner.row, in: drawn).ink == owed(palette.accent),
            "the spinner's cell owes the accent's alpha")
        // Its pad, one cell to the left, is blank and claims nothing.
        #expect(
            owed(atColumn: spinner.column - 1, row: spinner.row, in: drawn).ink == 1,
            "the centring pad owes no ink")
    }

    /// A `DatePicker`'s field draws every component itself — separators in
    /// `foregroundSecondary`, the editable parts in `foreground`, and the focused
    /// component's glyph over a breathing accent block — and all of them went to the
    /// emitter with the palette's alpha on them (§68.4).
    ///
    /// Focused, so the active component's run is built too: its block breathes while
    /// its ink does not, so the one claim on that cell is true of every frame the run
    /// replays, which is what makes claiming it legal at all.
    @Test("A date picker's components owe what each was drawn in")
    func datePickerFieldClaims() throws {
        let palette = FadedAll()
        let drawn = renderToBuffer(
            DatePicker("When", selection: .constant(Date(timeIntervalSince1970: 86_400 * 400))),
            context: context(palette: palette, width: 30, height: 3) {
                $0.focusManager = FocusManager()
            })

        let screen = drawn.lines.map(\.stripped)
        #expect(!drawn.animatedCells.isEmpty, "the focused component breathes: \(screen)")
        // A separator: the "-" between the date's parts, drawn in the quieter rung.
        let dash = try #require(cells(of: "-", in: drawn).first, "a separator: \(screen)")
        #expect(
            owed(atColumn: dash.column, row: dash.row, in: drawn).ink
                == owed(palette.foregroundSecondary),
            "the separator owes the secondary rung's alpha")
        // The field's own digits are `foreground`, a different rung, so a single
        // rectangle over the whole field would resolve one of the two wrongly.
        let digits = screen[dash.row]
        let digit = try #require(
            digits.firstIndex(where: \.isNumber).map { digits.distance(from: digits.startIndex, to: $0) },
            "a digit: \(screen)")
        #expect(
            owed(atColumn: digit, row: dash.row, in: drawn).ink == owed(palette.foreground),
            "a component's digits owe the foreground's alpha")
    }

    /// The wash a modal dims its page with is drawn in `overlayBackground` and
    /// `foregroundTertiary`, both of which carry a faded theme's alpha since §39 — and
    /// both of which reached the emitter (§68.5). The two channels are answered
    /// differently, and this asserts that: the field is CLAIMED over everything the
    /// wash covers, and the ink is SPENT against it, so no cell owes any ink at all.
    @Test("A dimmed backdrop claims its wash and spends its ink")
    func dimmedBackdropClaims() throws {
        let palette = FadedAll()
        let drawn = render(
            VStack { Text("behind"); Text("the sheet") }.dimmed(),
            palette: palette, width: 20, height: 4)

        #expect(
            drawn.lines.contains { $0.stripped.contains("behind") },
            "the page is still there under the wash: \(drawn.lines.map(\.stripped))")
        let cell = owed(atColumn: 2, row: 0, in: drawn)
        #expect(
            cell.field == owed(palette.overlayBackground),
            "the wash owes the overlay background's alpha")
        #expect(cell.ink == 1, "its ink was spent against the wash, so nothing owes it")
        // One rectangle for the whole wash, not one per row.
        #expect(drawn.opacityRegions.count == 1, "\(drawn.opacityRegions)")
    }

    /// The bouncing spinner's trail lerps its colour into a different value in every
    /// cell of every frame, so no rectangle can describe it and the one static claim a
    /// run replays under cannot exist. It was left unhonoured for exactly that reason
    /// — and then trapped here, under the example's own faded palette (§68.6). Both
    /// ends of the ramp are spent now, so it claims nothing and states no translucent
    /// colour; `ForegroundStyleAlphaTests.bouncingSpinnerSpends` pins the colour, this
    /// pins that a faded PALETTE (rather than a tint) reaches the same place.
    @Test("A bouncing spinner draws under a faded palette")
    func bouncingSpinnerDraws() {
        let drawn = render(Spinner(style: .bouncing), palette: FadedAll(), width: 20, height: 1)
        #expect(!drawn.animatedCells.isEmpty, "the track animates")
        #expect(drawn.opacityRegions.isEmpty, "a spent ramp claims nothing: \(drawn.opacityRegions)")
    }

    /// A blinking caret over a translucent well is the case no rectangle can describe:
    /// its block frames show the caret's own opaque colour and its blink-off frames show
    /// the well, so a single claim on that cell is wrong for half the cycle. It used to
    /// state nothing at all and the cell rendered at full strength (§61.2); the alpha now
    /// rides on the run, one statement per frame (``AnimatedRunAlpha``).
    ///
    /// Asserted through the resolver rather than on the claim alone, because the point is
    /// the pixels: the block frame must come out unblended, the blink-off frame must be
    /// the well spent against what is behind it, and the LINE the render drew must agree
    /// with the frame it was drawn at.
    @Test("A caret over a faded well owes its field per frame")
    func caretFieldClaimsPerFrame() throws {
        let palette = FadedAll()
        // An OPAQUE ground, as a real page has: resolving any run against a translucent
        // surface trips a separate, pre-existing assertion — a plain `Spinner` does it
        // too — and that is not what this is about.
        let ground = Color.rgb(10, 10, 20)
        let drawn = renderToBuffer(
            TextField("label", text: .constant("abc")).textCursor(.block, animation: .blink),
            context: context(palette: palette, width: 20, height: 3) {
                $0.focusManager = FocusManager()
            })

        let run = try #require(drawn.animatedCells.first, "the caret leaves a run")
        let alpha = try #require(run.alpha, "carrying its per-frame field")
        // The producer's half of the rule the resolver cannot check (§70.3): the caret
        // states its field on the run and nowhere else. A static field claim under the
        // same cell would be folded with the payload and fade the well twice — and the
        // resolver, which sees every producer's claims summed, can no longer tell that
        // apart from an ancestor's `.background` legitimately covering it.
        let staticFieldUnderCaret = drawn.opacityRegions.contains { region in
            region.offsetY <= run.offsetY && run.offsetY < region.offsetY + region.height
                && region.offsetX < run.offsetX + run.width
                && run.offsetX < region.offsetX + region.width
                && region.fieldOpacity < 1
        }
        #expect(
            !staticFieldUnderCaret,
            "no static field claim under the caret's own cell: \(drawn.opacityRegions)")
        #expect(alpha.varies, "the frames disagree, which is the whole reason it exists")
        let hasSilentFrame = alpha.perFrame.contains { $0.isEmpty }
        let wellOwed = owed(palette.fieldBackground)
        let hasWellFrame = alpha.perFrame.contains { spans in
            spans.contains { $0.field == wellOwed }
        }
        #expect(hasSilentFrame, "the block frames own their colour and owe nothing")
        #expect(hasWellFrame, "the blink-off frames owe the well: \(alpha.perFrame)")

        let resolved = drawn.resolvingOpacity(surface: ground, palette: palette)
        #expect(resolved.animatedCells.first?.alpha == nil, "the payload is spent, not carried on")
        let frames = try #require(resolved.animatedCells.first?.frames)
        let rgb = try #require(
            palette.fieldBackground.spendingAlpha(over: ground).resolve(with: palette).rgbComponents)
        let spentWell = "48;2;\(rgb.red);\(rgb.green);\(rgb.blue)"
        let anyShowsWell = frames.contains { $0.contains(spentWell) }
        let anyDoesNot = frames.contains { !$0.contains(spentWell) }
        #expect(anyShowsWell, "a blink-off frame shows the well spent against the ground")
        #expect(anyDoesNot, "and a block frame does not — it is the caret's own opaque colour")

        // The line the render drew is the drawn frame, resolved the same way: both sets
        // of bytes exist and a reader must not be able to tell them apart. This is the
        // half that needs the drawn frame's claim to reach the LINE — without it the
        // first paint sits at full strength until the first replay tick.
        /// The background the cell ENDS in — the last one stated, not the first.
        /// `ansiAwareSlice` carries every code in force at the cut, so a slice of a
        /// styled row opens with the row's background and only then states its own.
        func backgroundCode(of text: String) -> String? {
            var search = text.startIndex..<text.endIndex
            var last: String?
            while let found = text.range(
                of: "48;2;[0-9]+;[0-9]+;[0-9]+", options: .regularExpression, range: search)
            {
                last = String(text[found])
                search = found.upperBound..<text.endIndex
            }
            return last
        }
        let cell = resolved.lines[run.offsetY].ansiAwareSlice(
            visibleStart: run.offsetX, visibleCount: run.width)
        let cellBackground = backgroundCode(of: cell)
        let frameBackground = backgroundCode(of: frames[alpha.drawnIndex])
        #expect(
            cellBackground == frameBackground,
            """
            the drawn line's caret cell and the drawn frame state the same background:
            cell \(cell.debugDescription) vs frame \(frames[alpha.drawnIndex].debugDescription)
            """)
    }

    /// A child's run is rebuilt by the List from its own `RowRun`, which carries only
    /// what it was told to. It already had to be told the frame duration — rebuilding
    /// with the defaults ran a `.dots` spinner 2.2× too fast — and the per-frame alpha
    /// is the same class of omission: a caret inside a row would render at full strength
    /// while the identical field outside one did not. Pinned so the round-trip keeps it.
    @Test("A caret inside a List row keeps its per-frame field")
    func caretInsideAListRowKeepsItsAlpha() throws {
        let palette = FadedAll()
        let drawn = renderToBuffer(
            List(selection: .constant(Int?.none)) {
                TextField("label", text: .constant("abc")).textCursor(.block, animation: .blink)
            },
            context: context(palette: palette, width: 24, height: 5) {
                // Its own focus manager, or nothing is focused and the caret never
                // blinks — there is no run to carry anything.
                $0.focusManager = FocusManager()
            })

        let carried = try #require(
            drawn.animatedCells.first { $0.alpha != nil },
            """
            the caret's run reached the list with its alpha:
            \(drawn.animatedCells.map { "x=\($0.offsetX) y=\($0.offsetY) alpha=\($0.alpha != nil)" })
            """)
        let alpha = try #require(carried.alpha)
        #expect(alpha.varies, "and it still says different things on different frames")
        let wellOwed = owed(palette.fieldBackground)
        let owesTheWell = alpha.perFrame.contains { spans in spans.contains { $0.field == wellOwed } }
        #expect(owesTheWell, "the blink-off frames still owe the well: \(alpha.perFrame)")
    }

    /// A text editor's bar, which has no arrows: every claim the editor makes must be
    /// on the bar's column, and a track cell there must owe the track's alpha. Under a
    /// palette that fades only the track, because the editor's well is painted in
    /// `fieldBackground`, which a wholly faded palette fades too — and the well is not
    /// what this asserts.
    @Test("A text editor's bar owes what it painted, and nothing else claims")
    func textEditorBarClaims() {
        let palette = FadedTrack()
        let drawn = render(
            TextEditor(text: .constant((0..<30).map { "line \($0)" }.joined(separator: "\n")))
                .frame(width: 20, height: 6),
            palette: palette)
        let column = drawn.width - 1
        #expect(!drawn.opacityRegions.isEmpty, "the bar claimed nothing")
        #expect(
            drawn.opacityRegions.allSatisfy { $0.offsetX == column && $0.width == 1 },
            "a claim off the bar's column \(column): \(drawn.opacityRegions)")
        let track = owed(ScrollbarColors.track(in: palette))
        #expect(
            (0..<drawn.height).contains { owed(atColumn: column, row: $0, in: drawn).field == track },
            "no cell of the bar owes the track's alpha: \(drawn.opacityRegions)")
    }

    // MARK: - The colour swatch

    /// A focused swatch's bullet under a faded palette, on opaque fills and a
    /// translucent one. Every frame is built with the run, so a translucent frame
    /// traps here; after the fix every frame is opaque. On the translucent fill the
    /// centre cell owes the fill's field and no ink, and the outer cells owe the fill
    /// as both (§48).
    @Test("A focused swatch breathes under a faded palette")
    func focusedSwatchBreathes() {
        withColorDepth(.truecolor) {
            let fills: [Color] = [.rgb(200, 40, 40), .white, .black, .rgb(128, 128, 128)]
            for fill in fills {
                let drawn = renderToBuffer(
                    Button("") {}.buttonStyle(_ColorSwatchButtonStyle(color: fill)),
                    context: makeRenderContext(width: 20, height: 2) { environment, _ in
                        environment.palette = FadedAll()
                    })
                expectAnimates(drawn, runs: 1, "a focused swatch on \(fill)")
                #expect(drawn.opacityRegions.isEmpty, "on \(fill): \(drawn.opacityRegions)")
            }
            let faded = Color.rgb(200, 40, 40).opacity(0.5)
            let drawn = renderToBuffer(
                Button("") {}.buttonStyle(_ColorSwatchButtonStyle(color: faded)),
                context: makeRenderContext(width: 20, height: 2) { environment, _ in
                    environment.palette = FadedAll()
                })
            expectAnimates(drawn, runs: 1, "a focused translucent swatch")
            let centre = owed(atColumn: 1, row: 0, in: drawn)
            #expect(centre.ink == 1 && centre.field == owed(faded), "the centre owes \(centre)")
            for column in [0, 2] {
                let outer = owed(atColumn: column, row: 0, in: drawn)
                #expect(
                    outer.ink == owed(faded) && outer.field == owed(faded),
                    "column \(column) owes \(outer)")
            }
        }
    }

    // MARK: - The navigation bar

    /// The probe that trapped, and then every cell of the trail under a palette whose
    /// rungs fade by DIFFERENT amounts — under `FadedAll` every slot owes 128, so a
    /// cell claimed from the wrong slot would pass. The crumb is at rest here: this
    /// suite's context installs no focus manager.
    @Test("A navigation bar's trail owes what each part painted")
    func navigationBarClaims() {
        let probe = NavigationStack(path: .constant([1])) {
            Text("root").navigationTitle("Root")
                .navigationDestination(for: Int.self) { Text("screen \($0)").navigationTitle("Next") }
        }
        #expect(!render(probe).lines.isEmpty)

        let palette = FadedNavigation()
        let drawn = render(probe, palette: palette, width: 40, height: 8)
        #expect(
            drawn.lines.first?.stripped.hasPrefix(" Root \(NavigationCrumbs.separator) Next") == true,
            "the trail, not the Back button: \(drawn.lines.map(\.stripped))")
        let spans: [(columns: Range<Int>, ink: Double)] = [
            (0..<5, owed(palette.foregroundSecondary)),  // " Root": the crumb, lead blank included
            (5..<7, owed(palette.foregroundTertiary)),  // " ›": the separator
            (7..<12, owed(palette.foreground)),  // " Next": the screen you are on
            (12..<40, 1),  // the spacer and the padding
        ]
        for span in spans {
            for column in span.columns {
                let owes = owed(atColumn: column, row: 0, in: drawn)
                #expect(
                    owes.ink == span.ink && owes.field == 1,
                    "row 0 column \(column) owes \(owes), painted at \(span.ink)")
            }
        }
        let rule = cells(of: "─", in: drawn).filter { $0.row == 1 }
        #expect(rule.count == 40, "the rule spans the bar: \(drawn.lines.map(\.stripped))")
        for cell in rule {
            let owes = owed(atColumn: cell.column, row: 1, in: drawn)
            #expect(owes.ink == owed(palette.border) && owes.field == 1, "rule \(cell) owes \(owes)")
        }
    }

    /// Asserts each of `glyphs` was drawn exactly once, and that its cell owes the
    /// arrow colour's alpha as ink and the track's as field — which is what a bar
    /// that is neither focused nor hovered paints there.
    private func expectArrowsClaimed(
        _ glyphs: [Character], in buffer: FrameBuffer, palette: any Palette
    ) {
        let expected = (
            ink: owed(palette.foregroundTertiary), field: owed(ScrollbarColors.track(in: palette)))
        for glyph in glyphs {
            let found = cells(of: glyph, in: buffer)
            #expect(found.count == 1, "'\(glyph)' is drawn once: \(buffer.lines.map(\.stripped))")
            for cell in found {
                let owes = owed(atColumn: cell.column, row: cell.row, in: buffer)
                #expect(
                    owes.ink == expected.ink && owes.field == expected.field,
                    "'\(glyph)' at \(cell) owes \(owes), and was painted at \(expected)")
            }
        }
    }
}

/// Every slot translucent. `Palette` requires nine and derives the rest, so this is
/// the smallest type that fades a whole theme — and the reason the second tier of
/// §16.1 exists: nothing normalises what a custom palette returns.
///
/// Internal rather than private: `ScrollbarBreathAlphaTests` sweeps it too, as the
/// palette the scrollbar's breath first came apart under.
struct FadedAll: Palette {
    let id = "faded-all"
    let name = "Faded all"
    let background = Color.rgb(10, 10, 20).opacity(0.5)
    let foreground = Color.rgb(230, 230, 240).opacity(0.5)
    let accent = Color.rgb(0, 180, 200).opacity(0.5)
    let success = Color.rgb(40, 200, 40).opacity(0.5)
    let warning = Color.rgb(220, 200, 40).opacity(0.5)
    let error = Color.rgb(220, 40, 40).opacity(0.5)
    let info = Color.rgb(40, 120, 220).opacity(0.5)
    let border = Color.rgb(120, 120, 130).opacity(0.5)
}

/// Every slot opaque but the quietest rung, which is where a scroll track's colour
/// comes from — so a bar can be asserted inside a control whose other paints are not
/// the subject.
private struct FadedTrack: Palette {
    let id = "faded-track"
    let name = "Faded track"
    let background = Color.rgb(10, 10, 20)
    let foreground = Color.rgb(230, 230, 240)
    let accent = Color.rgb(0, 180, 200)
    let success = Color.rgb(40, 200, 40)
    let warning = Color.rgb(220, 200, 40)
    let error = Color.rgb(220, 40, 40)
    let info = Color.rgb(40, 120, 220)
    let border = Color.rgb(120, 120, 130)
    let foregroundQuaternary = Color.rgb(110, 110, 120).opacity(0.5)
}

/// Every text rung faded by a different amount, so a claim can be traced to the slot
/// that painted it — under `FadedAll` every slot owes 128, and a cell claimed from the
/// wrong one would pass.
///
/// Internal rather than private: the scroll indicator suites trace their tertiary
/// with it too.
struct FadedNavigation: Palette {
    let id = "faded-navigation"
    let name = "Faded navigation"
    let background = Color.rgb(10, 10, 20)
    let foreground = Color.rgb(230, 230, 240).opacity(0.5)
    let foregroundSecondary = Color.rgb(200, 200, 210).opacity(0.7)
    let foregroundTertiary = Color.rgb(150, 150, 160).opacity(0.3)
    let accent = Color.rgb(0, 180, 200).opacity(0.6)
    let success = Color.rgb(40, 200, 40)
    let warning = Color.rgb(220, 200, 40)
    let error = Color.rgb(220, 40, 40)
    let info = Color.rgb(40, 120, 220)
    let border = Color.rgb(120, 120, 130).opacity(0.4)
}
