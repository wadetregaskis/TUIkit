//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MainActorBox.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// A value a test's view closures write and its expectations read, isolated
/// to the main actor.
///
/// Being main-actor isolated makes the box `Sendable`, and that is what it is
/// for. Swift 6.3.3 rejects a common test shape at `-O`, but not at `-Onone`.
/// Swift 6.2.4 accepts a reduced copy of it at both. The shape is a nested `func` in a
/// `@MainActor` test that captures a non-`Sendable` local (a `var` array, or an
/// instance of a plain class) and at least one other local, and passes a
/// closure capturing the first to a main-actor API:
///
///     var seen: [Int] = []
///     var width = 4
///     func view() -> some View {
///         Text(String(repeating: "x", count: width))
///             .onGeometryChange(for: Int.self) { $0.size.width } action: { seen.append($0) }
///     }
///
/// The error is "sending 'seen' risks causing data races", with the note
/// "task-isolated 'seen' is captured by a main actor-isolated closure". It is a
/// false positive. The test, the nested `func` and the closure all run on the
/// main actor, and nothing nonisolated touches `seen`. Marking the nested
/// `func` `@MainActor` does not silence it. A `Sendable` capture gives the
/// region checker nothing to send, so this box compiles at both levels.
///
/// Debug builds never report it, so `swift test` and CI never saw it. A release
/// test build does: `swift build -c release --build-tests -Xswiftc -enable-testing`.
@MainActor
final class MainActorBox<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
