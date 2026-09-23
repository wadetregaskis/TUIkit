//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Session.swift
//
//  A SESSION is an interaction script played against a page over time: keys
//  typed into it, rows inserted and moved under it, the terminal resized around
//  it — what a person does to an app, step after step, rather than one screen
//  drawn and drawn again. The scenarios measure a UI at rest; a session
//  measures one in use, and the bugs of a UI in use are the ones that need a
//  write, a scroll or a moved row between two frames.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// MARK: - A session

/// What one step of a session does: the input it delivers, and what the step
/// models, which its cost is reported under.
///
/// A step's DATA changes — a message arriving, a process's numbers moving —
/// are made by the session itself, in ``StressSession/step(_:)``, on the model
/// its page reads: that is a background update, and costs the app nothing
/// until it draws. Its INPUT goes through the app's own input chain, as a
/// keypress does, and reaches whatever the page wired to it.
struct SessionStep {
    /// What the step models — `type`, `newline`, `scroll` — which its cost is
    /// reported under.
    var action: String
    /// Keys to deliver, in order, before the frame.
    var keys: [KeyEvent] = []
    /// Mouse events to deliver, in order, after the keys.
    var mouse: [MouseEvent] = []
    /// A new terminal size, applied after the input.
    var resize: (width: Int, height: Int)?
}

/// An interaction script and the page it plays against.
///
/// Deterministic: two instances built from one configuration make the same
/// choices at every step, so one can be played against an app that keeps its
/// render cache and the other against one that clears it every frame, and
/// their frames compared (see ``SessionRunner``).
@MainActor
protocol StressSession: AnyObject {
    associatedtype Page: View

    /// The page, built once. What changes lives in a model the session owns
    /// and the page reads, or in the `@State` of the page's own controls.
    var page: Page { get }

    /// Advances the script to step `index`: makes that step's data changes on
    /// the session's own model and says what input to deliver.
    func step(_ index: Int) -> SessionStep
}

/// The app a session's page is the whole of.
///
/// `App` requires `init()`, for `@main`. A host is never launched, only handed
/// to a ``HeadlessApp`` with its page; the one `init()` builds is an app with
/// nothing on it.
struct SessionHost<Page: View>: App {
    let page: Page?

    init(page: Page) { self.page = page }

    init() { page = nil }

    var body: some Scene {
        WindowGroup {
            if let page { page }
        }
    }
}

/// A session playing against an app of its own — the unit ``SessionRunner``
/// drives, erased so the registry can hold every kind of session.
@MainActor
final class DrivenSession {
    let step: (Int) -> SessionStep
    let send: (KeyEvent) -> Void
    let sendMouse: (MouseEvent) -> Void
    let resize: (_ width: Int, _ height: Int) -> Void
    let frame: (_ nanos: Int64) -> Void
    let screen: () -> [String]
    let bytesWritten: () -> Int

    /// Plays `session` against its own ``HeadlessApp`` of `width` × `height`
    /// cells, clearing its render cache before every frame when `cold`.
    init<S: StressSession>(_ session: S, width: Int, height: Int, cold: Bool) {
        let app = HeadlessApp(SessionHost(page: session.page), width: width, height: height)
        app.clearsRenderCacheEachFrame = cold
        step = { session.step($0) }
        send = { app.send($0) }
        sendMouse = { app.send($0) }
        resize = { app.resize(width: $0, height: $1) }
        frame = { app.frame(atNanos: $0) }
        screen = { app.screen }
        bytesWritten = { app.bytesWritten }
    }
}

// MARK: - The registry

/// One registered session: what `--session <id>` plays.
struct SessionDescriptor {
    /// Stable id for `--session` and `--bench --scenario session/<id>`.
    let id: String
    /// What the session is, in a line.
    let summary: String
    /// What it exercises that a UI at rest does not.
    let exercises: String
    /// Builds one instance, playing against its own app.
    let make: @MainActor (_ config: StressConfig, _ width: Int, _ height: Int, _ cold: Bool) -> DrivenSession
}

/// Every session, in the order `--sessions` lists them.
enum Sessions {
    @MainActor
    static let all: [SessionDescriptor] = [
        EditorSession.descriptor,
        InboxSession.descriptor,
        ProcessesSession.descriptor,
        LogSession.descriptor,
        SettingsSession.descriptor,
        ChatSession.descriptor,
    ]

    @MainActor
    static func byID(_ id: String) -> SessionDescriptor? {
        all.first { $0.id == id }
    }

    /// The prefix that names a session where a scenario id is expected, so
    /// `ab_bench.py --scenarios session/editor` A/Bs a session unchanged.
    static let scenarioPrefix = "session/"
}

// MARK: - Deterministic choices

/// A seeded generator for a session's choices — SplitMix64, the same mix the
/// scenarios synthesise their data with, so a session is reproducible from
/// its seed alone.
struct SessionRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    /// The next 64 random bits.
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        return mix(state, 0)
    }

    /// A value in `0..<bound`.
    mutating func below(_ bound: Int) -> Int {
        Int(next() % UInt64(max(1, bound)))
    }

    /// A value in `range`.
    mutating func within(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + below(range.count)
    }

    /// One of `weighted`'s choices, each as likely as its weight.
    mutating func pick<T>(_ weighted: [(T, Int)]) -> T {
        var roll = below(weighted.reduce(0) { $0 + $1.1 })
        for (choice, weight) in weighted {
            if roll < weight { return choice }
            roll -= weight
        }
        return weighted[weighted.count - 1].0
    }
}
