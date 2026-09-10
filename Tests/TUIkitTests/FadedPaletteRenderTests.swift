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
    /// **The scrollbars are deliberately hidden here, and that is a gap rather than a
    /// tidy-up.** `ScrollbarRenderer.styledCell` and `_ListCore`'s `emptyCell` paint a
    /// bar cell in `ScrollbarColors.track(in:)`, which carries the palette's alpha, and
    /// neither can claim it: a bar is `[String]` — one styled cell per line — handed to
    /// nine call sites that each place it at a column of their own. Closing it means the
    /// bar becoming a claim-bearing type, exactly as `TrackRenderer.render` became
    /// `ClaimingRow`, and that is its own commit. §40.2 records it; until then this
    /// suite covers everything else and the emitter's assertion is the standing net.
    private func render<V: View>(_ view: V, width: Int = 40, height: Int = 14) -> FrameBuffer {
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.palette = FadedAll()
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: width, availableHeight: height,
            environment: environment, tuiContext: tuiContext
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context)
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
                .scrollIndicators(.hidden)
                Table(rows) { TableColumn("Name") { $0.name } }
                    .scrollIndicators(.hidden)
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
}

/// Every slot translucent. `Palette` requires nine and derives the rest, so this is
/// the smallest type that fades a whole theme — and the reason the second tier of
/// §16.1 exists: nothing normalises what a custom palette returns.
private struct FadedAll: Palette {
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
