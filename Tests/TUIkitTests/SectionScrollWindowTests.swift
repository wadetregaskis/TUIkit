//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SectionScrollWindowTests.swift
//
//  A `Section` draws its content at its own identity, between its header and
//  its footer, so a lazy stack in the content of a section at a scroll view's
//  content origin is still reached by single-child steps and still bands
//  itself against the scroll window. The section relays that window moved
//  below its header (`ScrollWindowRelay`) and moves the stack's reply back.
//
//  Withheld instead, the stack was drawn whole, correctly, and everything that
//  rides the window was lost: seeks (`scrollTo`, a `.scrollPosition` write)
//  into lazy and eager content alike, `.scrollPosition` read-back, a held
//  `.anchorPosition(.row)`, and the band — every row's `onAppear` fired on the
//  first frame. These hold each of them — the held row in
//  `SectionHeldRowTests` — and every seek to where the same rows in one flat
//  eager column put it: a column with no window to misread, whose seek is
//  exact.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// Which path the stack in the section takes.
enum SectionContentPath: CaseIterable, CustomTestStringConvertible {
    /// One-line rows: the uniform arithmetic window.
    case uniform
    /// Forty rows of one to three lines: the exact walk under 256 rows.
    case exactWalk
    /// Three hundred rows of one to three lines: the anchored window.
    case anchored
    /// An eager `VStack`, which draws whole and answers a seek from its slots.
    case eager

    var testDescription: String { "\(self)" }

    var count: Int {
        switch self {
        case .uniform, .anchored: 300
        case .exactWalk, .eager: 40
        }
    }

    var variable: Bool { self == .exactWalk || self == .anchored }
}

/// What the section draws around its content.
enum SectionChrome: CaseIterable, CustomTestStringConvertible {
    case header
    case footer
    case both
    /// A footer of ten lines, taller than the eight-line viewport: at the
    /// content's end no row is on screen.
    case tallFooter

    var testDescription: String { "\(self)" }
    var hasHeader: Bool { self == .header || self == .both }
    var hasFooter: Bool { self != .header }

    /// The footer's text.
    var footer: String {
        self == .tallFooter ? (0..<10).map { "footer \($0)" }.joined(separator: "\n") : "footer"
    }
}

/// Holds the reader's proxy, and the scroll position, for a test to move at
/// "event time".
final class SectionProxyBox: @unchecked Sendable {
    var proxy: ScrollViewProxy?
    var position = ScrollPosition()
}

/// One move of the seek script: a seek to a row, or a scroll to a line.
private enum SeekStep: CustomStringConvertible {
    case row(Int, UnitPoint?)
    case line(Int)

    var description: String {
        switch self {
        case let .row(row, anchor): "scrollTo(\(row), \(String(describing: anchor)))"
        case let .line(line): "scrollTo(y: \(line))"
        }
    }

    @MainActor func apply(to box: SectionProxyBox) {
        switch self {
        case let .row(row, anchor): box.proxy?.scrollTo(row, anchor: anchor)
        case let .line(line): box.position.scrollTo(y: line)
        }
    }
}

/// A section with a control in its header or in its footer, around 300 rows
/// that take no focus — one line each (the uniform window) or one to three
/// (the anchored one). Not both controls: a section draws its header and
/// footer at its own identity, so two controls there would share one focus id.
private struct SectionControlsApp: App {
    let controlInHeader: Bool
    let variable: Bool

    init() { self.init(controlInHeader: true, variable: false) }
    init(controlInHeader: Bool, variable: Bool) {
        self.controlInHeader = controlInHeader
        self.variable = variable
    }

    var body: some Scene {
        WindowGroup {
            ScrollView {
                if controlInHeader {
                    Section { rows } header: { Button("top") {} }
                } else {
                    Section { rows } header: { Text("header") } footer: { Button("bottom") {} }
                }
            }
        }
    }

    private var rows: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<300, id: \.self) { sectionRow($0, variable: variable) }
        }
    }
}

/// Row `index`: one line, or with `variable` one to three.
@MainActor
func sectionRow(_ index: Int, variable: Bool) -> Text {
    guard variable else { return Text("row \(index)") }
    return Text(
        (["row \(index)"] + Array(repeating: "  of \(index)", count: index % 3))
            .joined(separator: "\n"))
}

/// The section, its content taking `path`.
private struct SectionPage: View {
    let path: SectionContentPath
    let chrome: SectionChrome

    var body: some View {
        switch chrome {
        case .header:
            Section("header") { rows }
        case .footer, .tallFooter:
            Section { rows } footer: { Text(chrome.footer) }
        case .both:
            Section { rows } header: { Text("header") } footer: { Text(chrome.footer) }
        }
    }

    @ViewBuilder private var rows: some View {
        if path == .eager {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<path.count, id: \.self) { sectionRow($0, variable: true) }
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<path.count, id: \.self) { sectionRow($0, variable: path.variable) }
            }
        }
    }
}

/// The same lines in one flat eager column: header, rows, footer.
private struct FlatPage: View {
    let path: SectionContentPath
    let chrome: SectionChrome

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if chrome.hasHeader { Text("header") }
            ForEach(0..<path.count, id: \.self) {
                sectionRow($0, variable: path == .eager || path.variable)
            }
            if chrome.hasFooter { Text(chrome.footer) }
        }
    }
}

@MainActor
private func sectionFrame<V: View>(
    _ view: V, tui: TUIContext, focusManager: FocusManager, height: Int = 8
) -> [String] {
    var environment = EnvironmentValues()
    environment.focusManager = focusManager
    environment.applyRuntimeServices(from: tui)
    let context = RenderContext(
        availableWidth: 30, availableHeight: height, environment: environment, tuiContext: tui)
    tui.preferences.beginRenderPass()
    tui.stateStorage.beginRenderPass()
    tui.renderCache.beginRenderPass()
    focusManager.beginRenderPass()
    let buffer = renderToBuffer(view, context: context)
    focusManager.endRenderPass()
    tui.stateStorage.endRenderPass()
    tui.renderCache.removeInactive()
    return buffer.lines.map { line in
        // Without the scrollbar's column, whose thumb a windowed stack places
        // from an estimate by design, or the padding before it.
        let text = String(
            line.stripped.reversed().drop { $0 == " " || isScrollbarGlyph($0) }.reversed())
        // The "N more" count is the stack's estimate on the anchored path.
        return text.contains(" more ") ? "<more>" : text
    }
}

private func isScrollbarGlyph(_ character: Character) -> Bool {
    guard let scalar = character.unicodeScalars.first else { return false }
    return (0x2500...0x259F).contains(scalar.value) || scalar == "▲" || scalar == "▼"
}

/// The number of the first row that starts on `screen`.
private func firstRow(on screen: [String]) -> Int? {
    screen.lazy.compactMap { $0.firstMatch(of: /^row (\d+)/).flatMap { Int($0.1) } }.first
}

/// The number of the row on `screen`'s first line, which may continue a row
/// that starts above it.
private func topRow(on screen: [String]) -> Int? {
    screen.first?.firstMatch(of: /^(?:row|  of) (\d+)/).flatMap { Int($0.1) }
}

/// A scroll view over `content` that shows "N more" in its first and last
/// lines, so every seek near an edge has to leave room for them.
private struct SeekPage<Content: View>: View {
    let box: SectionProxyBox
    let content: Content

    var body: some View {
        ScrollViewReader { proxy in
            // swiftlint:disable:next redundant_discardable_let
            let _ = box.proxy = proxy
            ScrollView { content }
                .scrollPosition(Binding(get: { box.position }, set: { box.position = $0 }))
                .scrollIndicatorStyle(.text)
                .frame(height: 8)
        }
    }
}

/// Counts how often a footer's body is asked for: the relay measures the
/// footer before the content is drawn.
private final class FooterBodies: @unchecked Sendable {
    var count = 0
}

private struct CountedFooter: View {
    let bodies: FooterBodies

    var body: some View {
        bodies.count += 1
        return Text("footer")
    }
}

@MainActor
@Suite("A section relays the scroll window to its content")
struct SectionScrollWindowTests {
    @Test(
        "Every seek into a section's stack lands where it lands in the flat eager column",
        arguments: SectionContentPath.allCases, SectionChrome.allCases)
    func seeksLandAsInTheFlatColumn(path: SectionContentPath, chrome: SectionChrome) {
        // The edges are the point: a `.top` seek to the first row under a
        // header must leave the "more above" line on the header, not on the
        // row; a seek to the last row over a footer must be free to scroll the
        // footer into view. Asked of the stack alone, each was a line off.
        //
        // Before: every seek did nothing, the view staying at its top.
        let last = path.count - 1
        let middle = path.count / 2
        // `.line(100_000)` from the top is a jump past the content's end that
        // is not glued to it, as End is: it lands on the end the scroll view
        // last knew, and must show the footer there — repeated, it must not
        // move. `.row(5, .top), .row(0, nil)` is the minimal-movement seek to
        // a row just above the viewport, which must bring the header back with
        // it; `.line(1), .row(0, nil)` the same with the header's line
        // scrolled off and the first row under the "more above" line.
        var script: [SeekStep] = [
            .line(100_000), .line(100_000), .row(middle, .top), .row(0, .top),
            .row(last, .bottom), .row(last, .top), .row(0, .bottom), .row(1, .center),
            .row(middle, nil), .row(middle + 1, nil), .row(last, nil), .row(last - 8, .top),
            .row(last, nil), .row(5, .top), .row(0, nil), .line(1), .row(0, nil),
        ]
        if path == .anchored {
            // The anchored window seeks by ESTIMATE (§5e): the row lands exactly
            // where the anchor walk puts it, but a bottom-edge clamp is priced
            // at the running pitch, and near the tail it is not the column's.
            script = [
                .line(100_000), .line(100_000), .row(middle, .top), .row(0, .top),
                .row(1, .center), .row(middle, nil), .row(5, .top), .row(0, nil), .line(1),
                .row(0, nil), .row(last - 10, .top), .row(last, nil),
            ]
        }
        let sectionBox = SectionProxyBox()
        let flatBox = SectionProxyBox()
        let section = SeekPage(box: sectionBox, content: SectionPage(path: path, chrome: chrome))
        let flat = SeekPage(box: flatBox, content: FlatPage(path: path, chrome: chrome))
        let (sectionTUI, sectionFocus) = (TUIContext(), FocusManager())
        let (flatTUI, flatFocus) = (TUIContext(), FocusManager())
        _ = sectionFrame(section, tui: sectionTUI, focusManager: sectionFocus)
        _ = sectionFrame(flat, tui: flatTUI, focusManager: flatFocus)
        var diverged: [String] = []
        for step in script {
            step.apply(to: sectionBox)
            step.apply(to: flatBox)
            let inSection = sectionFrame(section, tui: sectionTUI, focusManager: sectionFocus)
            let inFlat = sectionFrame(flat, tui: flatTUI, focusManager: flatFocus)
            if inSection != inFlat {
                diverged.append("\(step): \(inSection) vs \(inFlat)")
            }
        }
        #expect(diverged.isEmpty, "\(diverged.count) seeks differ: \(diverged.prefix(2))")
    }

    @Test("A section's lazy stack draws its band: onAppear fires for the rows on screen, not all 2,000")
    func onlyTheBandAppears() {
        // Drawn whole, every row's `onAppear` fired on the first frame, so an
        // `onAppear` at the last row that loads the next page loaded page after
        // page until the data ran out.
        var appeared = 0
        let view = ScrollView {
            Section("header") {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<2_000, id: \.self) { index in
                        Text("row \(index)").onAppear { appeared += 1 }
                    }
                }
            }
        }
        let (tui, focusManager) = (TUIContext(), FocusManager())
        _ = sectionFrame(view, tui: tui, focusManager: focusManager, height: 10)
        let screen = sectionFrame(view, tui: tui, focusManager: focusManager, height: 10)
        #expect(screen.contains("row 8"), "precondition: the rows are drawn: \(screen)")
        #expect(appeared < 40, "appeared \(appeared) times")
    }

    @Test(
        "scrollPosition(id:) reads back the row under a section's header, and writes a seek into it",
        arguments: [SectionContentPath.uniform, .exactWalk, .anchored])
    func readBackUnderAHeader(path: SectionContentPath) {
        // At the top the sample line is the header's, above the stack's first
        // row: the first row is reported, as a stack with no header reports it.
        var visible: Int?
        let binding = Binding<Int?>(get: { visible }, set: { visible = $0 })
        let view = ScrollView {
            Section("header") {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<path.count, id: \.self) { sectionRow($0, variable: path.variable) }
                }
            }
        }
        .scrollPosition(id: binding)
        .frame(height: 6)
        let (tui, focusManager) = (TUIContext(), FocusManager())
        _ = sectionFrame(view, tui: tui, focusManager: focusManager, height: 6)
        #expect(visible == 0, "the first row is reported: \(String(describing: visible))")

        visible = 25
        let after = sectionFrame(view, tui: tui, focusManager: focusManager, height: 6)
        #expect(after.contains { $0.hasPrefix("row 25") }, "the write seeks: \(after)")
        #expect(visible == topRow(on: after), "the top row is read back: \(after)")
    }

    @Test("Read-back under the \"more above\" line over a header reports the first row a person can see")
    func readBackUnderTheTopIndicator() {
        // Scrolled one line, the header is gone and the indicator covers row 0:
        // the content is scrolled though the stack is at its top, and the
        // sample steps past the indicator as it would with no header.
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        let view = ScrollView {
            Section("header") {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<40, id: \.self) { Text("row \($0)") }
                }
            }
        }
        .scrollPosition(binding)
        .scrollIndicatorStyle(.text)
        .frame(height: 6)
        let (tui, focusManager) = (TUIContext(), FocusManager())
        _ = sectionFrame(view, tui: tui, focusManager: focusManager, height: 6)
        position.scrollTo(id: 1, anchor: .top)
        let screen = sectionFrame(view, tui: tui, focusManager: focusManager, height: 6)
        #expect(screen.first == "<more>" && firstRow(on: screen) == 1, "precondition: \(screen)")
        #expect(position.viewID(type: Int.self) == 1, "\(screen)")
    }

    @Test("Read-back over the \"more below\" line above a footer reports the last row a person can see")
    func readBackOverTheBottomIndicator() {
        // The stack's last row on the viewport's last line, the footer below
        // it: the content continues though the stack does not, so the
        // indicator covers that row.
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        let view = ScrollView {
            Section {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<40, id: \.self) { Text("row \($0)") }
                }
            } footer: {
                Text("footer")
            }
        }
        .scrollPosition(binding, anchor: .bottom)
        .scrollIndicatorStyle(.text)
        .frame(height: 6)
        let (tui, focusManager) = (TUIContext(), FocusManager())
        _ = sectionFrame(view, tui: tui, focusManager: focusManager, height: 6)
        position.scrollTo(id: 35, anchor: .top)
        let screen = sectionFrame(view, tui: tui, focusManager: focusManager, height: 6)
        #expect(screen.last == "<more>" && screen.contains("row 38"), "precondition: \(screen)")
        #expect(position.viewID(type: Int.self) == 38, "\(screen)")
    }

    @Test(
        "At the very bottom over a footer, read-back reports the rows on screen, not the stack's last screenful",
        arguments: [UnitPoint.top, .bottom], [SectionContentPath.uniform, .exactWalk, .anchored])
    func readBackOverAFooter(anchor: UnitPoint, path: SectionContentPath) {
        // The footer is room to scroll past the stack's last screenful, so the
        // top row there is one the stack's own extent would never put at the
        // top — and the bottom line is the footer, below every row, which on
        // the anchored window named no row at all.
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        let view = ScrollView {
            Section {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<path.count, id: \.self) { sectionRow($0, variable: path.variable) }
                }
            } footer: {
                Text("footer")
            }
        }
        .scrollPosition(binding, anchor: anchor)
        .scrollIndicatorStyle(.text)
        .frame(height: 6)
        let (tui, focusManager) = (TUIContext(), FocusManager())
        _ = sectionFrame(view, tui: tui, focusManager: focusManager, height: 6)
        position.scrollTo(edge: .bottom)
        _ = sectionFrame(view, tui: tui, focusManager: focusManager, height: 6)
        let bottom = sectionFrame(view, tui: tui, focusManager: focusManager, height: 6)
        #expect(bottom.last == "footer", "precondition: the footer is on screen: \(bottom)")
        // The first line is the "more above" indicator's.
        let expected = anchor == .top ? topRow(on: Array(bottom.dropFirst())) : path.count - 1
        #expect(position.viewID(type: Int.self) == expected, "\(bottom)")
    }

    @Test(
        "At the end of a footer taller than the viewport, read-back reports the last row",
        arguments: [SectionContentPath.uniform, .exactWalk, .anchored])
    func readBackPastTheLastRow(path: SectionContentPath) {
        // No row is on screen: the line sampled is the footer's, below every
        // row, and the row reported is the last one, as a line past the rows
        // is everywhere else.
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        let view = ScrollView {
            Section {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<path.count, id: \.self) { sectionRow($0, variable: path.variable) }
                }
            } footer: {
                Text(SectionChrome.tallFooter.footer)
            }
        }
        .scrollPosition(binding, anchor: .top)
        .scrollIndicatorStyle(.text)
        .frame(height: 6)
        let (tui, focusManager) = (TUIContext(), FocusManager())
        _ = sectionFrame(view, tui: tui, focusManager: focusManager, height: 6)
        position.scrollTo(edge: .bottom)
        _ = sectionFrame(view, tui: tui, focusManager: focusManager, height: 6)
        let bottom = sectionFrame(view, tui: tui, focusManager: focusManager, height: 6)
        #expect(bottom.last == "footer 9", "precondition: the footer's end is on screen: \(bottom)")
        #expect(topRow(on: bottom) == nil, "precondition: no row is on screen: \(bottom)")
        #expect(position.viewID(type: Int.self) == path.count - 1, "\(bottom)")
    }

    @Test(
        "A footer that draws blank is not counted: at the end, read-back reports the last row, as with no footer",
        arguments: [SectionContentPath.uniform, .exactWalk, .anchored])
    func readBackOverABlankFooter(path: SectionContentPath) {
        // The section drops a blank footer, so the content ends at the last
        // row, which is on the viewport's last line with no "more below" line
        // over it. Counted, the footer's line was content below the viewport,
        // the sample was charged that indicator's line, and it named the row
        // above. The anchored window's last row is one line here too, so a
        // line too high lands on the row above it.
        let count = path == .anchored ? path.count + 1 : path.count
        func bottom(blankFooter: Bool) -> (screen: [String], id: Int?) {
            var position = ScrollPosition()
            let binding = Binding(get: { position }, set: { position = $0 })
            let rows = LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<count, id: \.self) { sectionRow($0, variable: path.variable) }
            }
            let view = ScrollView {
                if blankFooter {
                    Section { rows } footer: { Text(" ") }
                } else {
                    Section { rows }
                }
            }
            .scrollPosition(binding, anchor: .bottom)
            .scrollIndicatorStyle(.text)
            .frame(height: 8)
            let (tui, focusManager) = (TUIContext(), FocusManager())
            _ = sectionFrame(view, tui: tui, focusManager: focusManager)
            position.scrollTo(edge: .bottom)
            _ = sectionFrame(view, tui: tui, focusManager: focusManager)
            return (sectionFrame(view, tui: tui, focusManager: focusManager), position.viewID(type: Int.self))
        }
        let blank = bottom(blankFooter: true)
        let bare = bottom(blankFooter: false)
        #expect(bare.id == count - 1, "precondition: \(bare.screen)")
        #expect(blank.screen == bare.screen, "\(blank.screen) where no footer draws \(bare.screen)")
        #expect(blank.id == count - 1, "\(blank.screen)")
    }

    @Test("Tab onto a section's footer control scrolls it into view", arguments: [false, true])
    func focusRevealsTheFootersControl(variable: Bool) {
        // Out of the band the footer is not drawn, but its controls are
        // carried where they belong, as an off-band row's are: a focus move
        // onto one finds where to scroll.
        let app = HeadlessApp(
            SectionControlsApp(controlInHeader: false, variable: variable), width: 30, height: 10)
        app.frame(atNanos: 0)
        var screen: [String] = []
        for step in 1...3 {
            app.send(KeyEvent(key: .tab))
            app.frame(atNanos: Int64(step) * 16_666_667)
            screen = app.screen.map(\.stripped)
            if screen.contains(where: { $0.contains("bottom") }) { break }
        }
        #expect(screen.contains { $0.contains("bottom") }, "the footer's control is revealed: \(screen)")
        #expect(screen.contains { $0.hasPrefix("row 299 ") }, "…below the last row: \(screen)")
    }

    @Test(
        "Shift-Tab onto a section's header control from the end scrolls it into view",
        arguments: [false, true])
    func focusRevealsTheHeadersControl(variable: Bool) {
        let app = HeadlessApp(
            SectionControlsApp(controlInHeader: true, variable: variable), width: 30, height: 10)
        app.frame(atNanos: 0)
        // The header's control, then the scroll view, which End scrolls.
        app.send(KeyEvent(key: .tab))
        app.frame(atNanos: 16_666_667)
        app.send(KeyEvent(key: .end))
        app.frame(atNanos: 33_333_334)
        let atEnd = app.screen.map(\.stripped)
        #expect(atEnd.contains { $0.contains("row 299") }, "precondition: at the end: \(atEnd)")
        app.send(KeyEvent(key: .tab, shift: true))
        app.frame(atNanos: 50_000_001)
        let screen = app.screen.map(\.stripped)
        #expect(screen.contains { $0.contains("top") }, "the header's control is revealed: \(screen)")
        #expect(screen.contains { $0.hasPrefix("row 0 ") }, "…above the first row: \(screen)")
    }

    @Test("A full-height reply's drawn lines are moved below the header: every line it names is drawn")
    func drawnLinesAreTheSections() {
        // The exact walk draws only the rows around the offset into a canvas
        // of every row and names the lines it drew, so the scroll view can see
        // that an offset it moves after the render — a re-glue, a focus snap —
        // shows lines never drawn, and draw them. Named in the stack's lines,
        // they were a header off: lines the section's canvas holds blank
        // placeholders on, reported drawn.
        let reply = ScrollContentReply()
        var context = makeBareRenderContext(width: 30, height: 200)
        context.environment.scrollContentWindow = ScrollContentWindow(
            offset: 30, viewportHeight: 6, contentIdentity: nil, reply: reply)
        let view = Section {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<40, id: \.self) { sectionRow($0, variable: true) }
            }
        } header: {
            Text("header\nsecond\nthird")
        }
        let lines = renderToBuffer(view, context: context).lines.map(\.stripped)
        guard let drawn = reply.drawnLines else {
            Issue.record("precondition: a full-height reply names its drawn lines")
            return
        }
        #expect(drawn.lowerBound > 0, "precondition: the band starts below the top: \(drawn)")
        let blank = drawn.clamped(to: 0..<lines.count).filter {
            lines[$0].trimmingCharacters(in: .whitespaces).isEmpty
        }
        #expect(blank.isEmpty, "named drawn, but blank: \(blank) of \(drawn)")
    }

    @Test("A section that is not the scroll content's origin relays nothing: its footer is not measured for the window")
    func sectionBesideASiblingDoesNotRelay() {
        // `ScrollView { VStack { Section {…} footer: {…}; Text("…") } }` hands
        // every child of the column the window, and no stack in the section
        // can consume it, a sibling among several: the relay measured the
        // footer for it on every render all the same.
        let bodies = FooterBodies()
        func footerBodies(windowed: Bool, atOrigin: Bool) -> Int {
            bodies.count = 0
            var context = makeBareRenderContext(width: 30, height: 40)
            if windowed {
                context.environment.scrollContentWindow = ScrollContentWindow(
                    offset: 0, viewportHeight: 6, contentIdentity: context.identity,
                    reply: ScrollContentReply())
            }
            let section = Section {
                Text("row")
            } header: {
                Text("header")
            } footer: {
                CountedFooter(bodies: bodies)
            }
            _ = renderToBuffer(
                section,
                context: atOrigin
                    ? context.withChildIdentity(type: type(of: section))
                    : context.withChildIdentity(type: type(of: section), index: 1))
            return bodies.count
        }
        #expect(
            footerBodies(windowed: true, atOrigin: true) > footerBodies(windowed: false, atOrigin: true),
            "precondition: at the origin, the relay measures the footer")
        #expect(
            footerBodies(windowed: true, atOrigin: false) == footerBodies(windowed: false, atOrigin: false))
    }

    @Test("A section with neither header nor footer leaves its lazy stack the window as it is: scrollTo reaches row 500")
    func bareSectionPassesTheWindowThrough() {
        // Nothing drawn around the content: it sits at the section's origin,
        // and there is nothing to relay.
        let box = SectionProxyBox()
        let view = ScrollViewReader { proxy in
            // swiftlint:disable:next redundant_discardable_let
            let _ = box.proxy = proxy
            ScrollView {
                Section {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<1_000, id: \.self) { Text("row \($0)") }
                    }
                }
            }
            .frame(height: 6)
        }
        let (tui, focusManager) = (TUIContext(), FocusManager())
        _ = sectionFrame(view, tui: tui, focusManager: focusManager, height: 6)
        box.proxy?.scrollTo(500, anchor: .top)
        let screen = sectionFrame(view, tui: tui, focusManager: focusManager, height: 6)
        #expect(screen.contains { $0.hasPrefix("row 500") }, "the seek landed: \(screen)")
    }
}
