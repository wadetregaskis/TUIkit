//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StorageSendabilityTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// `@AppStorage` and `@SceneStorage` are `Sendable` exactly when their value is.
///
/// Both used to be spelled `@unchecked Sendable` with no constraint, which is
/// neither sound nor SwiftUI parity — SwiftUI's own conformances are
/// conditional (`extension AppStorage: Sendable where Value: Sendable`).
///
/// Half of that claim is testable and half is not, and the untestable half is
/// the interesting one. `Sendable` is a *marker* protocol: it leaves no runtime
/// conformance record, so nothing here can ask whether
/// `AppStorage<SomeClass>` is `Sendable` and be told no — `as? any Sendable`
/// is not even expressible. The compiler is the only thing that checks it, so
/// what this file can do is pin the POSITIVE direction: that the conformance
/// still holds for a value that qualifies, which is what keeps the constraint
/// from being a source break for ordinary use. These cases assert by
/// compiling; the `#expect`s below only give the harness something to run.
///
/// The negative direction was checked by hand, once, with a throwaway file:
///
///     final class NotSendableBox: Codable { var v = 0 }
///     struct MustNotCompile: Sendable { let s: AppStorage<NotSendableBox> }
///
/// which now fails with "stored property 's' of 'Sendable'-conforming struct
/// 'MustNotCompile' contains non-Sendable type 'NotSendableBox'" and compiled
/// silently before the conformance was constrained. Recorded here rather than
/// committed, because a file whose purpose is to fail to compile cannot live in
/// a target that has to build.
@Suite("Storage wrappers are conditionally Sendable")
struct StorageSendabilityTests {

    /// A `Codable` value that is also `Sendable` — the ordinary case.
    private struct Settings: Codable, Sendable, Equatable {
        var theme: String
        var fontSize: Int
    }

    /// Holding one in a `Sendable` aggregate is the assertion: this type only
    /// compiles if `AppStorage<Settings>: Sendable` holds.
    private struct AppHolder: Sendable {
        let scalar: AppStorage<Int>
        let composite: AppStorage<Settings>
    }

    private struct SceneHolder: Sendable {
        let scalar: SceneStorage<String>
        let composite: SceneStorage<Settings>
    }

    @Test("A Sendable value keeps the wrapper Sendable")
    func sendableValueConforms() {
        let store = MockStorageBackend()
        let holder = AppHolder(
            scalar: AppStorage(wrappedValue: 7, "count", store: store),
            composite: AppStorage(
                wrappedValue: Settings(theme: "dark", fontSize: 12), "settings", store: store))
        #expect(holder.scalar.wrappedValue == 7)
        #expect(holder.composite.wrappedValue.theme == "dark")

        let scene = SceneHolder(
            scalar: SceneStorage(wrappedValue: "list", "tab", store: store),
            composite: SceneStorage(
                wrappedValue: Settings(theme: "light", fontSize: 10), "restore", store: store))
        #expect(scene.scalar.wrappedValue == "list")
        #expect(scene.composite.wrappedValue.fontSize == 10)
    }

    /// And it crosses a concurrency boundary for real, rather than only
    /// satisfying a constraint: a `@Sendable` closure captures the wrapper and
    /// is run on another isolation domain.
    @Test("The wrapper can be captured by a @Sendable closure")
    func crossesAnIsolationBoundary() async {
        let store = MockStorageBackend()
        let storage = AppStorage(wrappedValue: 3, "captured", store: store)
        let read = await Task.detached { @Sendable in storage.wrappedValue }.value
        #expect(read == 3)
    }
}
