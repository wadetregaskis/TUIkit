//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DragAndDropStormTests.swift
//
//  A seeded storm over drag-and-drop: random press/drag/release streams
//  interleaved with re-renders that shift handler ids (an extra draggable
//  appears) and add/remove the drop zones themselves, with two payload
//  types in play. Invariants: every drop lands on exactly the zone under
//  the cursor in the CURRENT frame (or cancels) — never a stale or wrong
//  zone; `isTargeted` strictly alternates per zone and always closes out
//  when the drag ends; and the session is idle whenever no captured drag
//  is in flight. This storm generalises the two pinned mid-drag re-render
//  bugs in DragAndDropTests (and, pre-fix, also caught a third variant:
//  a stale id delivering a drop while the cursor was outside every zone).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

private final class DragStormLog {
    var stringDrops: [String] = []
    var intDrops: [Int] = []
    var stringTargeted: [Bool] = []
    var intTargeted: [Bool] = []
}

/// One trial's storm state: the rendered tree's flags, the in-flight
/// interaction model (what the storm believes is captured), and the seeded
/// RNG — one method per random operation, with the delivery oracle beside
/// the release op.
@MainActor
private final class DragStormDriver {
    // Fixed geometry (VStack spacing 0, leading): chip row 0, optional extra
    // draggable row 1, string zone row 3, int zone row 5 — absent zones are
    // replaced by same-size blanks so rows never shift, only handler ids do.
    private static let stringZoneRect = (x: 0..<12, y: 3)
    private static let intZoneRect = (x: 0..<12, y: 5)

    private var seed: UInt64
    private let trial: Int
    private var step = 0
    private(set) var violations: [String] = []

    private let log = DragStormLog()
    private let tui = TUIContext()
    private let context: RenderContext
    private let dispatcher: MouseEventDispatcher
    private let session: DragAndDropSession

    // The flags of the most recent render — the oracle's frame.
    private var extraRow = false
    private var stringZone = true
    private var intZone = true

    // The model of the in-flight interaction.
    private var payload: Any?  // set while a press is captured
    private var dragBegun = false

    init(trial: Int, seed: UInt64) {
        self.trial = trial
        self.seed = seed
        var env = EnvironmentValues()
        env.focusManager = FocusManager()
        env.applyRuntimeServices(from: tui)
        context = RenderContext(
            availableWidth: 30, availableHeight: 8, environment: env, tuiContext: tui)
        dispatcher = tui.mouseEventDispatcher
        session = tui.dragAndDropSession
        dispatcher.setActiveSupport(.standard)
        render()
    }

    private func rand(_ bound: Int) -> Int {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Int((seed >> 33) % UInt64(max(1, bound)))
    }

    private func fail(_ message: String) {
        violations.append("trial \(trial) step \(step): \(message)")
    }

    @ViewBuilder
    private func tree() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CHIP").draggable("apple")
            if extraRow {
                Text("XTRA").draggable(7)
            } else {
                Text("").frame(width: 4, height: 1)
            }
            Text("").frame(width: 1, height: 1)
            if stringZone {
                Text("SZONE=======")
                    .dropDestination(for: String.self) { [log] items, _ in
                        log.stringDrops.append(contentsOf: items)
                        return true
                    } isTargeted: { [log] in log.stringTargeted.append($0) }
            } else {
                Text("").frame(width: 12, height: 1)
            }
            Text("").frame(width: 1, height: 1)
            if intZone {
                Text("IZONE=======")
                    .dropDestination(for: Int.self) { [log] items, _ in
                        log.intDrops.append(contentsOf: items)
                        return true
                    } isTargeted: { [log] in log.intTargeted.append($0) }
            } else {
                Text("").frame(width: 12, height: 1)
            }
        }
    }

    private func render() {
        dispatcher.beginRenderPass()
        session.beginFrame()
        let buffer = renderToBuffer(tree(), context: context)
        dispatcher.setRegions(buffer.hitTestRegions)
    }

    func run(steps: Int) {
        for current in 0..<steps {
            step = current
            performRandomOp()
            checkUniversalInvariants()
            if !violations.isEmpty { return }
        }
    }

    private func performRandomOp() {
        switch rand(8) {
        case 0..<3 where payload == nil: press(kind: rand(3))
        case 0..<5: drag()
        case 5: rerender()
        default: release()
        }
    }

    /// A press on the chip, the (maybe-absent) extra draggable, or the void.
    private func press(kind: Int) {
        switch kind {
        case 0:
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
            payload = "apple"
        case 1:
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 1, y: 1))
            payload = extraRow ? 7 : nil  // absent → blank row, nothing captured
        default:
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 25, y: 7))
        }
    }

    private func drag() {
        guard payload != nil else { return }
        _ = dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: rand(30), y: rand(8)))
        dragBegun = true
    }

    /// A re-render with churned shape: the extra row shifts every later
    /// handler id, and the zones themselves come and go.
    private func rerender() {
        extraRow = rand(2) == 0
        stringZone = rand(4) != 0
        intZone = rand(4) != 0
        render()
    }

    /// Release at a random cell — with the delivery oracle: the drop must
    /// land iff a drag was in flight AND the release cell is inside a
    /// type-compatible zone that exists in the CURRENT frame.
    private func release() {
        guard payload != nil else { return }
        let x = rand(30)
        let y = rand(8)
        let stringBefore = log.stringDrops.count
        let intBefore = log.intDrops.count
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))

        let overString =
            dragBegun && stringZone && payload is String
            && y == Self.stringZoneRect.y && Self.stringZoneRect.x.contains(x)
        let overInt =
            dragBegun && intZone && payload is Int
            && y == Self.intZoneRect.y && Self.intZoneRect.x.contains(x)
        if (log.stringDrops.count - stringBefore) != (overString ? 1 : 0) {
            fail("string zone drops \(stringBefore)→\(log.stringDrops.count), expected over=\(overString) at (\(x),\(y))")
        }
        if (log.intDrops.count - intBefore) != (overInt ? 1 : 0) {
            fail("int zone drops \(intBefore)→\(log.intDrops.count), expected over=\(overInt) at (\(x),\(y))")
        }
        if session.active != nil {
            fail("the session survived a release")
        }
        payload = nil
        dragBegun = false
    }

    private func checkUniversalInvariants() {
        if session.active != nil && !dragBegun {
            fail("a drag session exists without a captured drag")
        }
        for (name, targeted) in [("string", log.stringTargeted), ("int", log.intTargeted)] {
            for index in 1..<max(1, targeted.count) where targeted[index] == targeted[index - 1] {
                fail("\(name) zone isTargeted did not alternate: \(targeted)")
                return
            }
            if session.active == nil, targeted.last == true {
                fail("\(name) zone left targeted after the drag ended: \(targeted)")
            }
        }
    }
}

@MainActor
@Suite("Drag-and-drop storm", .serialized)
struct DragAndDropStormTests {

    @Test("Random drags across re-renders always drop on the zone under the cursor")
    func dragAndDropStorm() {
        var violations: [String] = []
        for trial in 0..<25 {
            let driver = DragStormDriver(
                trial: trial, seed: 0xFEED_FACE_0BAD_F00D &+ UInt64(trial) &* 0x9E3779B97F4A7C15)
            driver.run(steps: 120)
            violations.append(contentsOf: driver.violations)
            if !violations.isEmpty { break }
        }

        if !violations.isEmpty {
            print("=== DRAG-AND-DROP VIOLATIONS ===")
            for violation in violations.prefix(10) { print(violation) }
        }
        #expect(violations.isEmpty)
    }
}
