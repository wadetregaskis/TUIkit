//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollIndicatorClaimTests.swift
//
//  The "N more" lines — `.scrollIndicatorStyle(.text)` — are drawn in the
//  palette's tertiary and, focused, breathe to its accent. They went to the
//  emitter with no claims on every host: under a faded palette the still line
//  trapped in a debug build, and a focused line's breath under a faded tint put
//  a different alpha at each end. The still line is asserted on every host that
//  draws one — `List`, both of `Table`'s paths, and both of `ScrollView`'s — and
//  so is the ground a focused one spends against; the breath itself on a `List`.
//
//  Rendered through public views only, so the suite runs against any revision.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("The text scroll indicators owe what they painted")
struct ScrollIndicatorClaimTests {

    private struct Row: Identifiable, Hashable {
        let id: Int
        let name: String
    }

    private static let rows = (0..<30).map { Row(id: $0, name: "row\($0)") }
    private static let width = 30

    /// Every host of the text indicators, 30 rows each. The scroll view's lines are
    /// exactly one viewport wide, so none wraps short of the indicator's column and
    /// the overwritten row really did carry the content's claim (§50).
    private var hosts: [(name: String, view: AnyView)] {
        [
            ("List", AnyView(List(selection: .constant(Set<Int>())) { ForEach(Self.rows) { Text($0.name) } })),
            ("Table", AnyView(Table(Self.rows) { TableColumn("Name") { $0.name } })),
            (
                "multi-line Table",
                AnyView(Table(Self.rows) { TableColumn("Name") { "\($0.name)\nsecond" }.lineLimit(2) })
            ),
            (
                "ScrollView",
                AnyView(
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(0..<30, id: \.self) { _ in Text(String(repeating: "x", count: Self.width)) }
                        }
                    })
            ),
        ]
    }

    /// At rest, under `.automatic` (a ▼ only: the scroll view OVERWRITES its last
    /// line) and `.visible` (both, each on a line of its own: the scroll view
    /// RESERVES them). The arrow and the count's first digit owe the tertiary's
    /// alpha; the centring blank before the arrow owes nothing.
    @Test(
        "Every host's still indicator line owes the tertiary it is drawn in",
        arguments: [ScrollIndicatorVisibility.automatic, .visible])
    func stillLinesClaim(visibility: ScrollIndicatorVisibility) {
        // A tertiary that owes an alpha no other slot does, so a line drawn from the
        // wrong slot shows: under `FadedAll` the tertiary IS the foreground.
        let palette = FadedNavigation()
        let arrows: [Character] = visibility == .visible ? ["▲", "▼"] : ["▼"]
        let still = owed(palette.foregroundTertiary)
        for host in hosts {
            let drawn = render(host.view, palette: palette, visibility: visibility, focused: false)
            for arrow in arrows {
                let found = cells(of: arrow, in: drawn)
                #expect(found.count == 1, "[\(host.name)] \(arrow) drawn \(found.count) times: \(screen(drawn))")
                guard let cell = found.first else { continue }
                for column in [cell.column, cell.column + 2] {
                    let owes = owed(atColumn: column, row: cell.row, in: drawn)
                    #expect(
                        owes.ink == still && owes.field == 1,
                        "[\(host.name)] (\(column), \(cell.row)) owes \(owes): \(screen(drawn))")
                }
                let blank = owed(atColumn: cell.column - 1, row: cell.row, in: drawn)
                #expect(
                    blank.ink == 1 && blank.field == 1,
                    "[\(host.name)] the blank before \(arrow) owes \(blank): \(screen(drawn))")
            }
        }
    }

    /// Focused, the line breathes through a run, and both of its ends spend their
    /// alphas against the surface — so the line owes nothing, under a wholly faded
    /// palette and under a faded tint alone (whose ends disagreed: 255 and 128).
    @Test("A focused list's indicator breathes, and owes nothing")
    func focusedListIndicator() throws {
        let palettes: [any Palette] = [
            FadedAll(), TintedPalette(base: SystemPalette.default, tint: Color.red.opacity(0.5)),
        ]
        for palette in palettes {
            let drawn = render(
                List(selection: .constant(Set<Int>())) { ForEach(Self.rows) { Text($0.name) } },
                palette: palette, visibility: .automatic, focused: true)
            let arrow = try #require(cells(of: "▼", in: drawn).first, "\(palette.name): \(screen(drawn))")
            #expect(
                drawn.animatedCells.contains { $0.offsetY == arrow.row },
                "\(palette.name): the focused indicator does not breathe")
            let owes = owed(atColumn: arrow.column, row: arrow.row, in: drawn)
            #expect(owes.ink == 1 && owes.field == 1, "\(palette.name): the breathing ▼ owes \(owes)")
        }
    }

    /// Focused under `.selectionIndicatorStyle(.none)`, the line does not breathe — one
    /// frame, no run — and spends all the same: focus shows one colour, breathing or
    /// not, and a spent colour owes nothing.
    @Test("A focused list's indicator under .none is still, spends, and owes nothing")
    func focusedStillIndicator() throws {
        let context = makeRenderContext(width: Self.width, height: 10) { environment, _ in
            environment.palette = FadedAll()
            environment.scrollIndicatorStyle = .text
            environment.selectionIndicatorStyle = SelectionIndicatorStyle(animation: .none)
        }
        let drawn = renderToBuffer(
            List(selection: .constant(Set<Int>())) { ForEach(Self.rows) { Text($0.name) } },
            context: context)
        let arrow = try #require(cells(of: "▼", in: drawn).first, "\(screen(drawn))")
        #expect(
            !drawn.animatedCells.contains { $0.offsetY == arrow.row }, "a .none line breathes")
        let owes = owed(atColumn: arrow.column, row: arrow.row, in: drawn)
        #expect(owes.ink == 1 && owes.field == 1, "the focused ▼ owes \(owes)")
    }

    /// The ground a focused line spends against is the surface it sits on, not the
    /// page. Every host reads it from the environment, and with no surface set the two
    /// are one colour, so the tests above cannot tell them apart. Both visibilities, so
    /// `ScrollView`'s overwriting and reserving paths each read it.
    @Test(
        "Every host's focused indicator spends over the surface it sits on",
        arguments: [ScrollIndicatorVisibility.automatic, .visible])
    func focusedLinesSpendOverTheSurface(visibility: ScrollIndicatorVisibility) {
        withColorDepth(.truecolor) {
            let surface = Color.rgb(90, 20, 20)
            let palette = TintedPalette(base: SystemPalette.default, tint: Color.red.opacity(0.5))
            let page = palette.background.resolve(with: palette)
            for host in hosts {
                let context = makeRenderContext(width: Self.width, height: 10) { environment, _ in
                    environment.palette = palette
                    environment.surfaceBackground = surface
                    environment.scrollIndicatorStyle = .text
                    environment.verticalScrollIndicatorVisibility = visibility
                }
                let drawn = renderToBuffer(host.view, context: context)
                guard let arrow = cells(of: "▼", in: drawn).first else {
                    Issue.record("[\(host.name)] no ▼: \(screen(drawn))")
                    continue
                }
                let frames = drawn.animatedCells.first { $0.offsetY == arrow.row }?.frames ?? []
                #expect(
                    frames.contains { $0.contains(code(palette.accent.spendingAlpha(over: surface), palette)) },
                    "[\(host.name)] the breath does not reach the accent spent over the surface")
                #expect(
                    !frames.contains { $0.contains(code(palette.accent.spendingAlpha(over: page), palette)) },
                    "[\(host.name)] the breath spends over the page")
            }
        }
    }

    // MARK: - Helpers

    /// `view` under the text indicators and `palette`, 30×10. A sentinel registered
    /// first holds the focus when the host is to rest; without one, the fresh focus
    /// manager hands the focus to the host, the first thing to register.
    private func render(
        _ view: some View, palette: any Palette, visibility: ScrollIndicatorVisibility, focused: Bool
    ) -> FrameBuffer {
        let context = makeRenderContext(width: Self.width, height: 10) { environment, _ in
            environment.palette = palette
            environment.scrollIndicatorStyle = .text
            environment.verticalScrollIndicatorVisibility = visibility
        }
        if !focused { context.environment.focusManager?.register(FocusSentinel()) }
        return renderToBuffer(view, context: context)
    }

    private func screen(_ frame: FrameBuffer) -> [String] { frame.lines.map(\.stripped) }
}
