//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AccumulateSession.swift
//
//  What an `@Observable` property that is read on every frame and never
//  written costs over a long run.
//
//  Every body evaluated under `withObservationTracking` arms one registration
//  on each property it read, and a registration is freed only when one of
//  those properties is written or every object it read from is
//  deinitialized. So a body evaluated on every frame that reads a property
//  nobody writes adds a registration every frame for as long as its model
//  lives — here, the whole run; about 1.2 KB each, as `--census` measured this
//  page, more for a deeper reader, since each holds its reader's identity
//  chain — and the first write, whenever it comes, runs every one of them on
//  the writer's thread. That is main's behaviour, for the one body it
//  observes. Option C observes more readers (a body read while measuring, a
//  style's body, a control's `Binding`), and each is a reader of this kind;
//  this session is the long run their cost is measured on, reader by reader,
//  against main's.
//
//  Created by Wade Tregaskis
//  License: MIT

import Dispatch
import Observation
import TUIkit

// MARK: - The model

/// A clock every step moves, and two properties the script never writes.
@Observable
@MainActor
final class AccumulateModel {
    /// Moved every step, and read by the page's body: the page is drawn again
    /// every frame, so everything below it is evaluated again, as under a
    /// spinner at 10 Hz.
    var tick = 0
    /// Read by each of the four readers, and written once, at the end of the
    /// run, when the write is timed.
    var never = 0
    /// Bound to the toggle; never written.
    var flag = false
}

// MARK: - The page

/// The clock over the four readers of `never`: a drawn body, a body that is
/// only measured (the candidate `ViewThatFits` measures and does not choose),
/// a custom button style's body, and a toggle bound through `@Bindable`.
struct AccumulatePage: View {
    let model: AccumulateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "step \(model.tick)")
            AccumulateReader(model: model)
            ViewThatFits(in: .horizontal) {
                AccumulateWideReader(model: model)
                Text(verbatim: "the wide reader does not fit")
            }
            Button("styled") {}.buttonStyle(AccumulateButtonStyle(model: model))
            Toggle(isOn: Bindable(model).flag) { Text(verbatim: "bound") }
        }
    }
}

/// A body that reads `never` and is drawn every frame.
private struct AccumulateReader: View {
    let model: AccumulateModel

    var body: some View {
        Text(verbatim: "never \(model.never)")
    }
}

/// A body that reads `never` and is only ever measured: wider than any
/// terminal the session is played at, so `ViewThatFits` measures it and draws
/// the next candidate.
private struct AccumulateWideReader: View {
    let model: AccumulateModel

    var body: some View {
        Text(verbatim: "never \(model.never) " + String(repeating: "·", count: 400))
    }
}

/// A button style whose body reads `never`. `Equatable`, as `ButtonStyle`'s
/// documentation asks, by the model it reads.
private struct AccumulateButtonStyle: ButtonStyle, Equatable {
    let model: AccumulateModel

    func makeBody(configuration: Configuration) -> some View {
        Text(verbatim: "[\(configuration.label) \(model.never)]")
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.model === rhs.model }
}

// MARK: - The script

/// A spinner's worth of frames: the clock moves every step and nothing else
/// does, until the run ends and `never` is written once.
@MainActor
final class AccumulateSession: StressSession {
    private let model = AccumulateModel()

    var page: AccumulatePage { AccumulatePage(model: model) }

    func step(_ index: Int) -> SessionStep {
        model.tick += 1
        return SessionStep(action: "tick")
    }

    /// Every 9,000 steps, the runner reports the run so far: at 10 Hz, a
    /// quarter of an hour.
    var checkpointEvery: Int? { 9_000 }

    /// Writes `never` for the first time, and says how long the write took:
    /// the registrations every reader armed since the page opened run inside
    /// it, on this thread.
    func finish() -> String? {
        let start = DispatchTime.now().uptimeNanoseconds
        model.never += 1
        let nanos = DispatchTime.now().uptimeNanoseconds &- start
        return String(format: "the first write of the never-written property took %.3f ms", Double(nanos) / 1e6)
    }

    /// The clock the page shows is the step count, and the four readers say
    /// what `never` holds.
    func check(_ screen: [String], after index: Int) -> String? {
        let clock = "step \(model.tick)"
        guard screen.contains(where: { $0.contains(clock) }) else { return "the page does not say \(clock)" }
        let reading = "never \(model.never)"
        return screen.contains { $0.contains(reading) } ? nil : "the reader does not say \(reading)"
    }

    static let descriptor = SessionDescriptor(
        id: "accumulate",
        summary: "a clock moving every step over four readers of a property nothing writes until the end",
        exercises:
            "observation registrations that nothing frees while their model lives: a drawn body, a body "
            + "only measured, a custom ButtonStyle's makeBody and a @Bindable-bound Toggle, each reading a "
            + "never-written @Observable property on every frame; resident size every 9,000 steps and the "
            + "time of the first write at the end",
        make: { _, width, height, cold in
            DrivenSession(AccumulateSession(), width: width, height: height, cold: cold)
        })
}
