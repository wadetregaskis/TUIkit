//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HoverWithoutAFillTests.swift
//
//  Hovers that answer the pointer with a fill, where the fill cannot be measured. A
//  standard button's face, a menu picker's face and a menu row's wash are accent tints
//  over the page, and so is a Stepper's or Slider's hovered arrow. Where the accent or
//  the page has no RGB, that tint is the page (Opacity as composition §75): the face
//  showed nothing, and the arrows were drawn in the page's colour, which the foreground
//  slot spells as 39 while unreported. There the label's or arrow's own ink lifts up the
//  ladder instead (`Palette.hoveredForeground(_:)`), and two other hovers that re-spell
//  a slot, a scrollbar's hovered arrow and a resize grip, stay slots rather than RGB.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

/// The terminal's page, with every ink a slot.
private struct SlotPagePalette: Palette {
    let id = "hover-slot-page"
    let name = "Slot page"
    let background = Color(value: .terminalBackground)
    let foreground = Color.ansi(.white)
    let accent = Color.ansi(.blue)
    let success = Color.ansi(.green)
    let warning = Color.ansi(.yellow)
    let error = Color.ansi(.red)
    let info = Color.ansi(.cyan)
    let border = Color.ansi(.brightBlack)
}

/// An RGB page with slot inks: the tint snaps to the page, which measures, and nothing
/// between it and the accent does.
private struct SlotInkRGBPagePalette: Palette {
    let id = "hover-slot-ink-rgb-page"
    let name = "Slot ink, RGB page"
    let background = Color.rgb(20, 20, 30)
    let foreground = Color.ansi(.white)
    let accent = Color.ansi(.blue)
    let success = Color.ansi(.green)
    let warning = Color.ansi(.yellow)
    let error = Color.ansi(.red)
    let info = Color.ansi(.cyan)
    let border = Color.ansi(.brightBlack)
}

@MainActor
@Suite("A hover whose fill cannot be measured lifts its ink instead")
struct HoverWithoutAFillTests {

    /// The controls whose hover is a fill.
    enum Site: String, CaseIterable, Sendable {
        case button, buttonView, picker, menuRow, stepper, slider
    }

    private static func rgb(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> TerminalColors.RGB {
        TerminalColors.RGB(red: red, green: green, blue: blue)
    }

    /// Apple Terminal "Basic" as it reports itself (Terminal-compatibility.md, measured
    /// 2026-09-14): black on white, and its sixteen.
    private static let appleTerminal = TerminalColors(
        foreground: rgb(0, 0, 0), background: rgb(255, 255, 255),
        slots: TerminalColors.Slots([
            rgb(0, 0, 0), rgb(153, 0, 0), rgb(0, 166, 0), rgb(153, 153, 0),
            rgb(0, 0, 179), rgb(179, 0, 179), rgb(0, 166, 179), rgb(191, 191, 191),
            rgb(102, 102, 102), rgb(230, 0, 0), rgb(0, 217, 0), rgb(230, 230, 0),
            rgb(0, 0, 255), rgb(230, 0, 230), rgb(0, 230, 230), rgb(230, 230, 230),
        ]))

    @ViewBuilder
    private func view(_ site: Site) -> some View {
        switch site {
        case .button:
            Button("Save") {}
        case .buttonView:
            Button {} label: { Text("Save") }
        case .picker:
            Picker("Fruit", selection: .constant("a")) {
                Text("Apple").tag("a")
                Text("Banana").tag("b")
            }
        case .menuRow:
            Button("Open") {}.buttonStyle(_MenuItemButtonStyle())
        case .stepper:
            Stepper("Count", value: .constant(3), in: 0...10)
        case .slider:
            Slider(value: .constant(0.5), in: 0...1)
        }
    }

    /// The glyphs whose ink the site's hover changes.
    private func marks(_ site: Site) -> Set<Character> {
        switch site {
        case .button, .buttonView: ["S"]
        case .picker: ["A"]
        case .menuRow: ["O"]
        case .stepper, .slider: ["◀", "▶"]
        }
    }

    /// Where the pointer goes, from the resting frame's plain text.
    private func point(_ site: Site, _ lines: [String]) -> (x: Int, y: Int) {
        let row = lines[0]
        func column(_ character: Character, plus offset: Int = 0) -> Int {
            guard let index = row.firstIndex(of: character) else { return 1 }
            return row.distance(from: row.startIndex, to: index) + offset
        }
        switch site {
        case .button, .buttonView, .menuRow: return (2, 0)
        case .picker: return (column("▐", plus: 2), 0)
        case .stepper: return (column("3"), 0)
        case .slider: return (column("◀", plus: 3), 0)
        }
    }

    /// Renders `view` unfocused in 24-bit colour, points the pointer at `at`, and renders
    /// again: the resting and hovered frames.
    private func hovering(
        _ view: some View, palette: any Palette, width: Int = 40, height: Int = 2,
        at: ([String]) -> (x: Int, y: Int)
    ) -> (resting: FrameBuffer, hovered: FrameBuffer) {
        let context = makeRenderContext(width: width, height: height) { environment, _ in
            environment.palette = palette
        }
        context.environment.focusManager!.register(FocusSentinel())
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.full)
        return ColorDepth.withCurrent(.truecolor) {
            let resting = renderToBuffer(view, context: context)
            dispatcher.setRegions(resting.hitTestRegions)
            let target = at(resting.lines.map(\.stripped))
            _ = dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: target.x, y: target.y))
            return (resting, renderToBuffer(view, context: context))
        }
    }

    /// The SGR state each glyph in `marks` is drawn in, over every row, in order.
    private func states(of marks: Set<Character>, in buffer: FrameBuffer) -> [SGRState] {
        buffer.lines.flatMap { line in
            var state = SGRState()
            var found: [SGRState] = []
            for segment in line.ansiSegments() {
                switch segment {
                case .ansi(let sequence, _):
                    state.apply(sequence)
                case .visible(let character):
                    if marks.contains(character) { found.append(state) }
                }
            }
            return found
        }
    }

    /// Whether `state`'s foreground is `colour` at 24-bit: stating it again changes nothing.
    private func draws(_ state: SGRState, in colour: Color) -> Bool {
        let codes = colour.foregroundCodes(depth: .truecolor)
        var restated = state
        // A parsed 39 is no foreground at all, where the parameter list 39 is a named colour.
        restated.setForeground(parameters: codes == ["39"] ? nil : codes)
        return restated == state
    }

    private func expectInk(
        _ buffer: FrameBuffer, marks: Set<Character>, in colour: Color, _ what: Comment,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let found = states(of: marks, in: buffer)
        let text = buffer.lines.map(\.debugDescription).joined(separator: "\n")
        #expect(!found.isEmpty, "\(what): no \(marks) in \(text)", sourceLocation: sourceLocation)
        #expect(
            found.allSatisfy { draws($0, in: colour) }, "\(what): \(text)", sourceLocation: sourceLocation)
    }

    // MARK: - The sites whose hover is a fill

    @Test("Unreported, a hover whose tint cannot be measured lifts the ink to its bright twin",
        arguments: Site.allCases)
    func unmeasurableTintLiftsTheInk(_ site: Site) {
        TerminalColors.withCurrent(.unknown) {
            for palette in [SlotPagePalette() as any Palette, SlotInkRGBPagePalette()] {
                let frames = hovering(view(site), palette: palette) { point(site, $0) }
                #expect(frames.resting.lines != frames.hovered.lines, "\(site) under \(palette.id): no hover")
                expectInk(frames.resting, marks: marks(site), in: .ansi(.white), "\(site) at rest, \(palette.id)")
                expectInk(frames.hovered, marks: marks(site), in: .ansi(.brightWhite), "\(site) hovered, \(palette.id)")
            }
        }
    }

    /// Keyed on what can be measured: once the terminal reports its page and slots, the
    /// tint is a colour again, and a Stepper's or Slider's hovered arrows are that tint.
    @Test("Reported, a Stepper's and a Slider's hovered arrows are the accent tint again",
        arguments: [Site.stepper, .slider])
    func reportedArrowsAreTheTint(_ site: Site) {
        TerminalColors.withCurrent(Self.appleTerminal) {
            let palette = SlotPagePalette()
            #expect(palette.accentTintIsMeasurable, "the fixture")
            let frames = hovering(view(site), palette: palette) { point(site, $0) }
            let tint = GroundedPalette.grounding(palette).accent
                .opacity(ViewConstants.hoverBackground, over: palette.background)
            expectInk(frames.hovered, marks: marks(site), in: tint, "\(site) hovered")
        }
    }

    /// Every built-in palette states RGB roles, so its tint measures and its hover is the
    /// one it had: the arrows are the 0.32 wash, and a button's label is unlifted.
    @Test("A built-in palette's Stepper and Slider arrows are still the wash under the pointer",
        arguments: [Site.stepper, .slider])
    func builtInArrowsKeepTheWash(_ site: Site) {
        TerminalColors.withCurrent(.unknown) {
            for palette in PaletteRegistry.all {
                let frames = hovering(view(site), palette: palette) { point(site, $0) }
                let seen = GroundedPalette.grounding(palette)
                let wash = seen.accent.opacity(ViewConstants.hoverBackground, over: seen.background)
                expectInk(frames.hovered, marks: marks(site), in: wash, "\(site) under \(palette.id)")
            }
        }
    }

    // MARK: - Hovers that re-spell a slot

    /// A box's resize grips, hovered at the right edge.
    private func grips(_ palette: any Palette) -> (resting: FrameBuffer, hovered: FrameBuffer) {
        hovering(
            Text("hello").frame(width: 12, height: 3).border().userResizable(),
            palette: palette, width: 30, height: 6
        ) { lines in (lines[1].count - 1, 1) }
    }

    /// A scroll view's bar, hovered on its up arrow.
    private func scrollbar(_ palette: any Palette) -> (resting: FrameBuffer, hovered: FrameBuffer) {
        hovering(
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<40, id: \.self) { Text("line \($0)") }
                }
            }.frame(width: 20, height: 6),
            palette: palette, width: 20, height: 6
        ) { _ in (19, 0) }
    }

    @Test("A hovered resize grip in a slot climbs the ladder: 39 over 90, never RGB")
    func gripStaysASlot() {
        for terminal in [TerminalColors.unknown, Self.appleTerminal] {
            TerminalColors.withCurrent(terminal) {
                let frames = grips(SlotPagePalette())
                expectInk(frames.resting, marks: ["║"], in: .ansi(.brightBlack), "at rest")
                expectInk(frames.hovered, marks: ["║"], in: .default, "hovered")
                #expect(
                    !frames.hovered.lines.contains { $0.contains("38;2;") },
                    "hovered: \(frames.hovered.lines.map(\.debugDescription))")
            }
        }
    }

    /// Unfocused, the hovered arrow is the secondary tier lifted. Unreported that is the
    /// twin; on Apple's white page the twin (230) reads worse than slot 7 (191), so 39.
    @Test("A scrollbar's hovered arrow in a slot climbs the ladder, never RGB")
    func scrollbarArrowStaysASlot() {
        TerminalColors.withCurrent(.unknown) {
            let frames = scrollbar(SlotPagePalette())
            expectInk(frames.hovered, marks: ["▲"], in: .ansi(.brightWhite), "unreported")
        }
        TerminalColors.withCurrent(Self.appleTerminal) {
            let frames = scrollbar(SlotPagePalette())
            expectInk(frames.hovered, marks: ["▲"], in: .default, "reported")
        }
    }

    /// The thumb's third answer (`ScrollbarColors.separated`) is a hover step. A slot only
    /// reaches it unreported, where a floor leaves it as asked; there it stays a slot.
    @Test("The scrollbar thumb's lift from a slot is a slot", arguments: ANSIColor.allCases)
    func scrollbarThumbStepStaysASlot(_ slot: ANSIColor) {
        TerminalColors.withCurrent(.unknown) {
            let palette = SlotPagePalette()
            #expect(ScrollbarColors.separated(.ansi(slot), in: palette).isTerminalDefined)
            #expect(ScrollbarColors.pulseLift(palette).isTerminalDefined)
        }
    }
}
