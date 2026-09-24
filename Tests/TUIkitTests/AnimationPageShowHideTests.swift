//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationPageShowHideTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// The Example's Animation page "Coming and going" demo, reduced to what it is
/// built from and nothing else: a button that toggles the panel inside
/// `withAnimation`, and the panel — an optional mapped through `.transition`,
/// under one `.frame(height:)` that is `nil` unless the space is kept — in a
/// page that scrolls, as every Example page does.
///
/// The Example is an executable and cannot be imported, so this is the page's
/// shape rather than the page; `AnimationPage.panelSlot` says the same thing.
private struct PanelPage: View {
    @State private var showsPanel = false
    let reservesSpace: Bool
    let transition: AnyTransition

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                Button("toggle") {
                    withAnimation(.linear(duration: 1)) { showsPanel.toggle() }
                }
                panelSlot
                Text("below")
            }
        }
        .scrollIndicators(.automatic)
    }

    @ViewBuilder private var panelSlot: some View {
        let panel = (showsPanel ? Text("PANEL") : nil)
            .map {
                $0.padding(1)
                    .border(.palette.accent)
                    .transition(transition)
            }
        panel.frame(height: reservesSpace ? 5 : nil, alignment: .top)
    }
}

private struct PanelApp: App {
    let reservesSpace: Bool
    let transition: AnyTransition

    init() {
        self.init(reservesSpace: false, transition: .opacity)
    }

    init(reservesSpace: Bool, transition: AnyTransition) {
        self.reservesSpace = reservesSpace
        self.transition = transition
    }

    var body: some Scene {
        WindowGroup { PanelPage(reservesSpace: reservesSpace, transition: transition) }
    }
}

/// The page in a ``HeadlessApp``, on a clock that only moves when told to.
///
/// Driven through the real render loop and input chain, so the change reaches
/// the frame the way the app delivers it: a key, a `withAnimation` in the
/// button's action, and a transaction consumed by the one pass that shows it.
@MainActor
private final class PanelDriver {
    private let app: HeadlessApp<PanelApp>
    /// The instant of the last frame drawn, on the frame clock.
    private(set) var now: Int64 = 0
    static let frameNanos: Int64 = 16_666_667

    init(reservesSpace: Bool, transition: AnyTransition) {
        app = HeadlessApp(
            PanelApp(reservesSpace: reservesSpace, transition: transition), width: 40, height: 20)
        app.frame(atNanos: now)
    }

    /// Presses the page's one button. Whether it took the key.
    func pressToggle() -> Bool { app.send(KeyEvent(key: .enter)) }

    /// Renders a frame every 1/60 s until `millis` have passed.
    func advance(byMillis millis: Int) {
        let target = now + Int64(millis) * 1_000_000
        while now < target {
            now += Self.frameNanos
            app.frame(atNanos: now)
        }
    }

    var screen: [String] { app.screen }

    /// Where `text` first appears on screen, styling stripped: row and column.
    /// Only the rows above `limit` are searched when one is given.
    func position(of text: String, above limit: Int? = nil) -> (row: Int, column: Int)? {
        for (row, line) in screen.map(\.stripped).enumerated() where row < (limit ?? screen.count) {
            if let range = line.range(of: text) {
                return (row, line.distance(from: line.startIndex, to: range.lowerBound))
            }
        }
        return nil
    }

    /// The 24-bit colours `text` is drawn in, where it first appears: the last
    /// foreground and the last background stated before it on its row.
    func colours(of text: String) -> (ink: [Int], page: [Int])? {
        guard let line = screen.first(where: { $0.contains(text) }),
            let range = line.range(of: text)
        else { return nil }
        let before = line[..<range.lowerBound]
        func lastColour(introducedBy introducer: String) -> [Int]? {
            guard let start = before.range(of: introducer, options: .backwards) else { return nil }
            let channels = before[start.upperBound...]
                .split(separator: ";", maxSplits: 3, omittingEmptySubsequences: false)
                .prefix(3)
                .compactMap { Int($0.prefix(while: \.isNumber)) }
            return channels.count == 3 ? channels : nil
        }
        guard let ink = lastColour(introducedBy: "38;2;"), let page = lastColour(introducedBy: "48;2;")
        else { return nil }
        return (ink, page)
    }

    /// The row the `below` line is on.
    var belowRow: Int? { position(of: "below")?.row }

    /// The panel's top-left corner: the first `╭` above the `below` line.
    /// Bounded because the status bar is drawn in the same rounded border, at
    /// column 0 — where the panel's own corner starts too.
    var panelCorner: (row: Int, column: Int)? {
        guard let below = belowRow else { return nil }
        return position(of: "╭", above: below)
    }
}

@MainActor
@Suite("The Animation page's Show / hide plays the removal")
struct AnimationPageShowHideTests {

    /// Whether `ink` is `original` with only `fraction` of its difference from
    /// `page` left, to within the one-unit rounding of 8-bit channels: the
    /// encoded-sRGB mix a fade draws (`OpacityFade`).
    private static func isBlend(
        _ ink: [Int], of original: [Int], toward page: [Int], keeping fraction: Double
    ) -> Bool {
        guard ink.count == 3, original.count == 3, page.count == 3 else { return false }
        return (0..<3).allSatisfy { channel in
            let expected = Double(page[channel]) + fraction * Double(original[channel] - page[channel])
            return abs(Double(ink[channel]) - expected) <= 1
        }
    }

    @Test("Hiding the panel slides it out in place, with the space kept or not",
        arguments: [false, true])
    func hidingSlidesOut(reservesSpace: Bool) {
        let page = PanelDriver(reservesSpace: reservesSpace, transition: .move(edge: .trailing))
        #expect(page.pressToggle(), "precondition: the button took the key")
        page.advance(byMillis: 1200)
        let shownCorner = page.panelCorner
        let shownBelow = page.belowRow
        #expect(shownCorner != nil && shownBelow != nil, "precondition: the panel arrived")
        guard let shownCorner, let shownBelow else { return }

        #expect(page.pressToggle(), "precondition: the button took the key")
        page.advance(byMillis: 17)
        #expect(
            page.panelCorner.map { $0 == shownCorner } == true,
            "the panel was gone on the first frame of its removal:\n\(page.screen.map(\.stripped))")
        #expect(page.belowRow == shownBelow, "the page closed up on the first frame of the removal")

        page.advance(byMillis: 500)
        #expect(
            page.panelCorner.map { $0.row == shownCorner.row && $0.column > shownCorner.column }
                == true,
            "not sliding out half-way:\n\(page.screen.map(\.stripped))")
        #expect(page.belowRow == shownBelow, "the page closed up before the removal finished")

        page.advance(byMillis: 700)
        #expect(page.panelCorner == nil, "still drawn after the removal ended")
    }

    /// The page's default transition, and the one whose failure the owner saw.
    ///
    /// A fade is the panel's ink blended toward the page by how far the
    /// removal has got, so that is what is checked, at two instants: not
    /// merely that the row changed, which a panel drawn in some other colour,
    /// or one frozen part-way, would pass as well. 24-bit colour so the blend
    /// can be read off the escapes without a palette's rounding.
    @Test("Hiding the panel fades it out, with the space kept or not", arguments: [false, true])
    func hidingFadesOut(reservesSpace: Bool) {
        ColorDepth.withCurrent(.truecolor) {
            let page = PanelDriver(reservesSpace: reservesSpace, transition: .opacity)
            #expect(page.pressToggle(), "precondition: the button took the key")
            page.advance(byMillis: 1200)
            let shownPanel = page.position(of: "PANEL")
            let shown = page.colours(of: "PANEL")
            #expect(shownPanel != nil && shown != nil, "precondition: the panel arrived")
            guard let shownPanel, let shown else { return }

            #expect(page.pressToggle(), "precondition: the button took the key")
            // The removal starts on the first frame after the key.
            let removedAt = page.now + PanelDriver.frameNanos
            for millis in [250, 250] {
                page.advance(byMillis: millis)
                let elapsed = Double(page.now - removedAt) / 1_000_000_000
                #expect(
                    page.position(of: "PANEL").map { $0 == shownPanel } == true,
                    "the panel was gone \(elapsed) s into its one-second removal")
                let drawn = page.colours(of: "PANEL")
                let fades = drawn.map {
                    Self.isBlend($0.ink, of: shown.ink, toward: shown.page, keeping: 1 - elapsed)
                }
                #expect(drawn?.page == shown.page, "the page under the panel changed colour")
                #expect(
                    fades == true,
                    "\(elapsed) s in, the panel's ink \(drawn?.ink ?? []) is not \(shown.ink) blended toward the page \(shown.page)")
            }

            page.advance(byMillis: 1000)
            #expect(page.position(of: "PANEL") == nil, "still drawn after the removal ended")
        }
    }
}
