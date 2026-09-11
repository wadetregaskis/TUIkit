//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FadedPaletteRenderTests.swift
//
//  A whole page rendered under a palette whose every slot is translucent — the
//  second tier of §16.1, which `Palette` being a public protocol of plain
//  `var …: Color { get }` members makes reachable in one type.
//
//  Created by Wade Tregaskis
//  License: MIT

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
    /// The breathing arm states none of its BORDER's claims — the border's alpha moves
    /// with the pulse, and a claim is one alpha for every frame — and the bar was
    /// nearly left out with it. The bar does not breathe, so its claim holds in every
    /// frame. That arm is asserted under a palette that fades only the track, because
    /// a breathing border under a wholly faded palette is the popup's own open gap,
    /// and it is loud.
    @Test("A drop-down's bar owes what it painted, still or breathing")
    func dropdownBarClaims() {
        for (palette, animation) in [
            (FadedAll() as any Palette, TextCursorStyle.Animation.none), (FadedTrack(), .pulse),
        ] {
            let popup = DropdownMenu.popup(
                DropdownMenu.Configuration(
                    rows: (0..<20).map { .option(" item \($0)") }, highlightedRow: 0,
                    innerWidth: 12, scroll: ScrollAxis(), followHighlight: false,
                    autoRepeatToken: "faded-dropdown"),
                context: context(palette: palette, width: 30, height: 10) {
                    $0.selectionIndicatorStyle = SelectionIndicatorStyle(animation: animation)
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
