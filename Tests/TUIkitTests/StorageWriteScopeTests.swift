//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StorageWriteScopeTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// An `@AppStorage` or `@SceneStorage` write invalidates the views that read
/// the key, not the whole render cache.
///
/// It used to clear everything: a stored value is in no memo's key and a write
/// carries no view identity, so dropping every buffer and size was the only
/// way to be sure. That cost every write a cold frame (a `Slider` bound to
/// `$storage` paid it per drag tick), and in a test process the clear was a
/// flag the next frame took, whichever app drew it — so one test's write cold-
/// started another test's app. A read is now an Observation access to the
/// store's ``StoredKey`` for the key, caught by the body that made it or by the
/// kept result around the control that read it through a `Binding`.
@MainActor
@Suite("A storage write invalidates what read the key, not the whole cache")
struct StorageWriteScopeTests {

    /// Counts its renders: a kept view that read nothing must be served.
    private struct CountingText: View, Renderable {
        let text: String
        let counter: Counter
        var body: Never { fatalError("CountingText renders via Renderable") }
        func renderToBuffer(context: RenderContext) -> FrameBuffer {
            counter.renders += 1
            return FrameBuffer(text: text)
        }
    }

    private final class Counter: @unchecked Sendable {
        var renders = 0
    }

    /// Equal to every other: stands for an `.equatable()` view whose value has
    /// not changed, which is all a stored value's readers ever look like.
    private struct Kept<Content: View>: View, @preconcurrency Equatable {
        let content: Content
        var body: some View { content }
        static func == (lhs: Self, rhs: Self) -> Bool { true }
    }

    private struct Reader: View {
        let store: MockStorageBackend
        let key: String
        var body: some View {
            let flag = AppStorage(wrappedValue: false, key, store: store)
            return Text("flag \(flag.wrappedValue)")
        }
    }

    private struct ToggleRow: View {
        let store: MockStorageBackend
        let key: String
        var body: some View {
            let flag = AppStorage(wrappedValue: false, key, store: store)
            return Toggle("stored", isOn: flag.projectedValue)
        }
    }

    private struct Page: App {
        let store: MockStorageBackend
        let key: String
        let counter: Counter
        init() { self.init(store: MockStorageBackend(), key: "unused", counter: Counter()) }
        init(store: MockStorageBackend, key: String, counter: Counter) {
            (self.store, self.key, self.counter) = (store, key, counter)
        }
        var body: some Scene {
            WindowGroup {
                VStack(alignment: .leading) {
                    // Holds the focus: a focused control breathes, and a
                    // subtree that animates is never kept.
                    Button("first") {}
                    Kept(content: Reader(store: store, key: key)).equatable()
                    Kept(content: ToggleRow(store: store, key: key)).equatable()
                    Kept(content: CountingText(text: "sibling", counter: counter)).equatable()
                }
            }
        }
    }

    private static func draw<A: App>(_ app: HeadlessApp<A>, _ frame: inout Int64) -> String {
        for _ in 0..<2 {
            frame += 100_000_000
            app.frame(atNanos: frame)
        }
        return app.screen.joined(separator: "\n").stripped
    }

    @Test("A write redraws the views that read the key, keeps a kept view that did not, and clears nothing")
    func writeReachesItsReaders() {
        let (store, counter) = (MockStorageBackend(), Counter())
        let key = "scope.reader"
        let app = HeadlessApp(Page(store: store, key: key, counter: counter), width: 30, height: 10)
        var frame: Int64 = 1_000_000_000
        let before = Self.draw(app, &frame)
        #expect(before.contains("flag false") && before.contains("□ stored"), "sanity:\n\(before)")
        let (siblingRenders, clears) = (counter.renders, app.renderCache.stats.clears)

        AppStorage(wrappedValue: false, key, store: store).wrappedValue = true
        let after = Self.draw(app, &frame)
        #expect(after.contains("flag true"), "a body that read the key kept the old value:\n\(after)")
        #expect(after.contains("■ stored"), "a toggle bound to the key kept the old state:\n\(after)")
        #expect(counter.renders == siblingRenders, "a kept view that read nothing was drawn again")
        #expect(app.renderCache.stats.clears == clears, "the write cleared the whole cache")
    }

    /// The observation is the store's, not the property wrapper's: a write or
    /// a removal made straight through the store reaches the same readers.
    @Test("A write or removal made through the store itself redraws the views that read the key")
    func storeWritesReachReaders() {
        let (store, counter) = (MockStorageBackend(), Counter())
        let key = "scope.direct"
        let app = HeadlessApp(Page(store: store, key: key, counter: counter), width: 30, height: 10)
        var frame: Int64 = 1_000_000_000
        _ = Self.draw(app, &frame)

        store.setValue(true, forKey: key)
        let written = Self.draw(app, &frame)
        #expect(written.contains("flag true") && written.contains("■ stored"), "\(written)")

        store.removeValue(forKey: key)
        let removed = Self.draw(app, &frame)
        #expect(removed.contains("flag false") && removed.contains("□ stored"), "the default after a removal:\n\(removed)")
    }

    /// Each store has its own keys: the same name in another store is another
    /// key, and a write to it reaches nothing that read this one.
    @Test("A write to the same key name in another store redraws nothing here")
    func storesKeepTheirOwnKeys() {
        let (store, elsewhere, counter) = (MockStorageBackend(), MockStorageBackend(), Counter())
        let key = "scope.shared-name"
        let app = HeadlessApp(Page(store: store, key: key, counter: counter), width: 30, height: 10)
        var frame: Int64 = 1_000_000_000
        _ = Self.draw(app, &frame)
        let stats = app.renderCache.stats

        elsewhere.setValue(true, forKey: key)
        let after = Self.draw(app, &frame)
        #expect(after.contains("flag false"), "\(after)")
        #expect(app.renderCache.stats.misses == stats.misses, "a write to another store's key redrew this app")
    }

    @Test("A write in one app neither clears nor redraws another app that never read the key")
    func writeStaysInItsApp() {
        let (store, counter) = (MockStorageBackend(), Counter())
        let bystander = HeadlessApp(
            Page(store: store, key: "scope.bystander", counter: counter), width: 30, height: 10)
        var frame: Int64 = 1_000_000_000
        _ = Self.draw(bystander, &frame)
        let (renders, clears) = (counter.renders, bystander.renderCache.stats.clears)

        AppStorage(wrappedValue: false, "scope.elsewhere", store: store).wrappedValue = true
        _ = Self.draw(bystander, &frame)
        #expect(bystander.renderCache.stats.clears == clears, "another app's write cleared this one's cache")
        #expect(counter.renders == renders, "another app's write redrew this one's kept view")
    }

    // MARK: - Rows that capture a stored value their parent read

    private struct Item: Identifiable, Equatable {
        let id: Int
        let short: String
        let long: String
    }

    /// The shape the 2026-08 semantic audit named: the parent reads the key and
    /// its `ForEach` rows — Equatable elements, so each row is memoised on its
    /// element — capture what it read. A row's element does not change when the
    /// preference does, so only the parent's invalidation can reach the rows.
    private struct CompactList: View {
        let store: MockStorageBackend
        var body: some View {
            let compact = AppStorage(wrappedValue: false, "scope.compact", store: store)
            let items = [Item(id: 1, short: "a", long: "alpha"), Item(id: 2, short: "b", long: "bravo")]
            return VStack(alignment: .leading) {
                Button("first") {}
                ForEach(items) { item in Text(compact.wrappedValue ? item.short : item.long) }
            }
        }
    }

    private struct CompactPage: App {
        let store: MockStorageBackend
        init() { self.init(store: MockStorageBackend()) }
        init(store: MockStorageBackend) { self.store = store }
        var body: some Scene { WindowGroup { CompactList(store: store) } }
    }

    @Test("Rows that capture a stored value their parent read show the new value after a write")
    func capturedByRows() {
        let store = MockStorageBackend()
        let app = HeadlessApp(CompactPage(store: store), width: 30, height: 8)
        var frame: Int64 = 1_000_000_000
        let before = Self.draw(app, &frame)
        #expect(before.contains("alpha") && before.contains("bravo"), "sanity:\n\(before)")

        AppStorage(wrappedValue: false, "scope.compact", store: store).wrappedValue = true
        let after = Self.draw(app, &frame)
        #expect(!after.contains("alpha") && !after.contains("bravo"), "a row kept the old text:\n\(after)")
    }
}
