//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DesignatedRowNotInDataTests.swift
//
//  `.anchorPosition(.row(id))` naming a row the data does not hold yet — a
//  position restored before its data loads. Nothing is held until the row
//  appears, as a `scrollTo` of the id moves nothing: the scroll view draws
//  what it draws with no designation, and adopts the row when it arrives.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// Which path the stack takes: one-line rows (the uniform window), or rows of
/// one to three lines, 40 of them (the exact walk) or 400 (the anchored window).
enum DesignationPath: CaseIterable, CustomTestStringConvertible {
    case uniform, exactWalk, anchored

    var testDescription: String { "\(self)" }
    var count: Int { self == .exactWalk ? 40 : 400 }
    func height(_ row: Int) -> Int { self == .uniform ? 1 : row % 3 + 1 }
}

@MainActor
@Suite("A designated row not in the data")
struct DesignatedRowNotInDataTests {
    /// One frame of `items` at 30x8, designating `row` when one is given, as
    /// the visible lines.
    private func frame(
        _ items: [Int], path: DesignationPath, designating row: Int?,
        position: Binding<ScrollPosition>, tuiContext: TUIContext, focusManager: FocusManager
    ) -> [String] {
        let list = ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(items, id: \.self) { i in
                    Text("row \(i)").frame(height: path.height(i))
                }
            }
        }
        .scrollPosition(position)
        .frame(height: 8)
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        if let row {
            environment.anchorPosition = AnchorPositionBinding(.constant(.row(AnyHashable(row))))
        }
        let context = RenderContext(
            availableWidth: 30, availableHeight: 8, environment: environment, tuiContext: tuiContext)
        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        let buffer = renderToBuffer(list, context: context)
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    /// The frames of a session of programmatic scrolls, designating `row`
    /// throughout, until `row` joins the data at its end: before, and after.
    private func session(
        path: DesignationPath, designating row: Int?
    ) -> (before: [[String]], after: [String]) {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        var items = Array(0..<path.count)
        func draw() -> [String] {
            frame(
                items, path: path, designating: row, position: binding,
                tuiContext: tuiContext, focusManager: focusManager)
        }
        var frames = [draw(), draw()]
        position.scrollTo(y: 30)
        frames += [draw(), draw()]
        position.scrollTo(edge: .top)
        frames += [draw(), draw()]
        position.scrollTo(y: 12)
        frames += [draw(), draw()]
        // Rows inserted above the top move the rows down, as with no
        // designation: a missing row holds no row in its place.
        items.insert(contentsOf: 1_000..<1_005, at: 0)
        frames += [draw(), draw()]
        items.append(9_999)
        _ = draw()
        return (frames, draw())
    }

    @Test(
        "A row designated before it is in the data holds nothing, and is revealed when it arrives",
        arguments: DesignationPath.allCases)
    func holdsNothingUntilItArrives(path: DesignationPath) {
        // Held on the anchored window, the row there stood in for the missing
        // one at the viewport's top, and the offset no longer moved it: each
        // scroll moved the scrollbar and not the rows. Not held but re-bound
        // by its key, as a held row is, the row at the top kept its place
        // through an insert above it, which with no designation moves it down.
        let designated = session(path: path, designating: 9_999)
        let plain = session(path: path, designating: nil)
        #expect(plain.before[2] != plain.before[0], "precondition: a scroll moves the rows: \(plain.before)")
        #expect(plain.before[8] != plain.before[7], "precondition: an insert above moves them: \(plain.before)")
        for (step, (held, free)) in zip(designated.before, plain.before).enumerated() {
            #expect(held == free, "frame \(step): \(held) where no designation draws \(free)")
        }
        #expect(
            designated.after.contains { $0.hasPrefix("row 9999") },
            "the row is revealed when it arrives: \(designated.after)")
    }

    @Test(
        "A row designated again after one not in the data is adopted where it sits",
        arguments: DesignationPath.allCases)
    func redesignatedRowIsAdoptedAfresh(path: DesignationPath) {
        // Between the two, nothing was held and the view scrolled: the row's
        // old line belongs to a viewport that no longer exists. Adopted
        // afresh, it stays where the scroll left it. Remembered as still
        // designated, it took the place of the row then at the top on the
        // anchored window, with the line of it the scroll had hidden, and went
        // off screen; on the other two paths it snapped back to its old line.
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        let items = Array(0..<path.count)
        func draw(_ row: Int?) -> [String] {
            frame(
                items, path: path, designating: row, position: binding,
                tuiContext: tuiContext, focusManager: focusManager)
        }
        _ = draw(nil)
        _ = draw(3)
        _ = draw(9_999)
        position.scrollTo(y: 2)
        let scrolled = draw(9_999)
        let again = draw(3)
        func rowThree(_ line: String) -> Bool { line.split(separator: " ").prefix(2) == ["row", "3"] }
        let line = scrolled.firstIndex(where: rowThree)
        #expect(line != nil && line != 0, "precondition: row 3 is on screen below the top: \(scrolled)")
        #expect(again.firstIndex(where: rowThree) == line, "\(scrolled) → \(again)")
    }

    @Test("A held row that leaves the data and returns comes back to its line", arguments: DesignationPath.allCases)
    func heldRowReturnsToItsLine(path: DesignationPath) {
        // Still designated while it is away, the row keeps its line: it is
        // not a new designation of a row not in the data, which is none and
        // forgets the line. Forgotten, it was adopted on its return at the
        // line the scroll meanwhile left its place on.
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        var items = Array(0..<path.count)
        func draw(_ row: Int?) -> [String] {
            frame(
                items, path: path, designating: row, position: binding,
                tuiContext: tuiContext, focusManager: focusManager)
        }
        func rowThree(_ line: String) -> Bool { line.split(separator: " ").prefix(2) == ["row", "3"] }
        _ = draw(nil)
        var held: [String] = []
        for _ in 0..<3 { held = draw(3) }
        items.remove(at: 3)
        _ = draw(3)
        position.scrollTo(y: 2)
        _ = draw(3)
        _ = draw(3)
        items.insert(3, at: 3)
        let back = draw(3)
        let line = held.firstIndex(where: rowThree)
        #expect(line != nil && line != 0, "precondition: row 3 is held below the top: \(held)")
        #expect(back.firstIndex(where: rowThree) == line, "\(held) → \(back)")
    }
}
