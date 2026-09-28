//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderCacheLinkTests.swift
//
//  Nothing references the render cache weakly. The first weak reference to an
//  object moves its reference count into a side table for the rest of the
//  object's life, and every retain and release of it then takes the runtime's
//  slow path — and the cache is retained and released with every context a
//  render copies. What keeps the cache past a render keeps its
//  `RenderCache.Link` instead.
//
//  Counted with the runtime's own weak count, and with a read of whether the
//  cache's count has a side table, on an app's `TUIContext`: its state
//  storage, its focus manager and its drag session are wired as an app's are.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIkit
@testable import TUIkitView

/// A row of the table below.
private struct Project: Identifiable {
    let id: Int
    var name: String { "project \(id)" }
}

/// What the observed body below reads.
@Observable
private final class LinkModel {
    var label = "observed"
}

/// A body that reads an `@Observable`: its registration's `onChange` held the
/// cache weakly.
private struct ObservedLabel: View {
    let model: LinkModel
    var body: some View { Text(verbatim: model.label) }
}

/// A view with `@State`: its box's sink held the cache weakly, stamped again at
/// every hydration.
private struct Counter: View {
    @State private var count = 0
    var body: some View { Button("count \(count)") { count += 1 } }
}

/// Everything that held the cache weakly, on one page.
private struct EveryHolder: View {
    let model: LinkModel
    var body: some View {
        VStack(spacing: 0) {
            ObservedLabel(model: model)
            Counter()
            Text("hover me").help("about it")
            List { ForEach(0..<5, id: \.self) { Text("row \($0)") } }
                .frame(height: 3)
            Table((0..<3).map(Project.init(id:))) { TableColumn("Name") { $0.name } }
                .frame(height: 3)
            ScrollViewReader { _ in
                ScrollView { VStack(spacing: 0) { ForEach(0..<10, id: \.self) { Text("line \($0)") } } }
                    .frame(height: 3)
            }
            Text("pull").refreshable {}
        }
    }
}

@MainActor
@Suite("Nothing references the render cache weakly")
struct RenderCacheLinkTests {

    /// The weak references to `cache` alive now. The runtime's count is one
    /// more than that: it holds an increment for the object's unowned count,
    /// with a side table or without one.
    private func weakReferences(to cache: RenderCache) -> Int {
        Int(_getWeakRetainCount(cache)) - 1
    }

    /// `frames` frames of `view` through `tui`, with a focus manager as an
    /// app's, the pass lifecycle around each as the render loop runs it.
    private func draw(_ view: some View, frames: Int = 3, tui: TUIContext) {
        let focus = FocusManager()
        for _ in 0..<frames {
            var environment = EnvironmentValues()
            environment.applyRuntimeServices(from: tui)
            environment.focusManager = focus
            environment.installVolatileReadTracker(VolatileReadTracker())
            focus.beginRenderPass()
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            _ = renderToBuffer(
                view,
                context: RenderContext(
                    availableWidth: 40, availableHeight: 24, environment: environment, tuiContext: tui))
            tui.stateStorage.endRenderPass()
            tui.renderCache.removeInactive()
        }
    }

    /// Whether the side-table probe must read this runtime: every 64-bit one,
    /// whose count word it knows. A 32-bit runtime (WASM) lays the word out
    /// differently, and the probe answers `nil` there by design; the live
    /// weak count, which the runtime reports itself, is checked everywhere.
    private static let probeReadsThisRuntime = Int.bitWidth == 64

    /// The probes are not blind: a weak reference is counted, and moves the
    /// count to a side table for good.
    @Test("The probes see a weak reference, and the side table it leaves")
    func probesSeeAWeakReference() {
        let cache = RenderCache()
        #expect(weakReferences(to: cache) == 0)
        let before = ReferenceCountProbe.usesSideTable(cache)
        if Self.probeReadsThisRuntime { #expect(before == false, "a fresh object's count is inline") }
        do {
            weak let held = cache
            #expect(weakReferences(to: cache) == 1)
            withExtendedLifetime(held) {}
        }
        #expect(weakReferences(to: cache) == 0, "the weak reference has gone")
        if Self.probeReadsThisRuntime {
            #expect(ReferenceCountProbe.usesSideTable(cache) == true, "and left the side table behind")
        }
    }

    /// An app's page, with everything that held the cache weakly on it —
    /// `StateStorage` and every `@State` box's sink, an observed body's
    /// registration, the focus manager, a `List`'s and a `Table`'s handler, a
    /// scroll view's reader, help text's hover observer, `.refreshable` —
    /// drawn for three frames: the cache has had no weak reference, so its
    /// count never left the object.
    @Test("An app's frames leave the cache with no weak reference and no side table")
    func appFramesLeaveNone() {
        let model = LinkModel()
        let tui = TUIContext()
        draw(EveryHolder(model: model), tui: tui)
        #expect(weakReferences(to: tui.renderCache) == 0)
        if Self.probeReadsThisRuntime {
            #expect(
                ReferenceCountProbe.usesSideTable(tui.renderCache) == false,
                "something referenced the cache weakly, if only for a moment")
        }
        withExtendedLifetime(model) {}
    }

    /// The link is how they reach it now, and it still reaches: a `@State`
    /// write and an `@Observable` change each queue their invalidation on it,
    /// and the next pass drains it.
    @Test("A write reaches the cache through its link")
    func writesReachTheCache() {
        let model = LinkModel()
        let tui = TUIContext()
        draw(EveryHolder(model: model), frames: 2, tui: tui)
        #expect(tui.renderCache.link.drain().identities.isEmpty)
        model.label = "changed"
        let queued = tui.renderCache.link.drain()
        #expect(queued.identities.count == 1, "the observed body's change was queued: \(queued.identities)")
    }

    /// A holder that outlives the cache reads nothing through the link, as it
    /// would through a weak reference: the cache detaches it as it goes, and a
    /// write to a closed link queues nothing.
    @Test("A link reads nil once its cache is gone, and queues nothing")
    func linkOutlivesItsCache() {
        var cache: RenderCache? = RenderCache()
        let link = cache?.link
        #expect(link?.cache === cache)
        cache = nil
        #expect(link?.cache == nil)
        link?.invalidateRender(for: ViewIdentity(rootType: Project.self))
        #expect(link?.drain().identities.isEmpty == true)
    }
}
