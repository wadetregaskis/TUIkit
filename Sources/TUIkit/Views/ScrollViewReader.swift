//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollViewReader.swift
//
//  SwiftUI-parity programmatic scrolling: ScrollViewReader hands its content
//  a ScrollViewProxy whose scrollTo(_:anchor:) scrolls the scroll views
//  inside to the row with the matching identity — a ForEach element's, or a
//  View.id(_:) tag — same-frame, and in O(window) via the seek machinery of
//  "Locating things without drawing them" (the request rides the
//  ScrollContentWindow handshake; the windowed stack that finds the key
//  renders its band AT the resolved offset).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - ScrollViewProxy

/// A proxy value for programmatically scrolling the scroll views within an
/// enclosing ``ScrollViewReader``'s content. Matches SwiftUI's type of the
/// same name.
@MainActor
public struct ScrollViewProxy {
    let registry: ScrollToRegistry

    /// Scrolls the reader's scroll views so the row identified by `id`
    /// is visible. Matches SwiftUI's signature exactly.
    ///
    /// `id` is an identity within the scroll view's content: a `ForEach`
    /// element's — `proxy.scrollTo(item.id)` for a data-driven list, or the
    /// element value itself for `ForEach(0..<n, id: \.self)` — or the tag a
    /// ``View/id(_:)`` bound to one of the content stack's own children, the
    /// spelling SwiftUI's own `ScrollViewReader` example is built out of. An
    /// unknown id is a no-op, as in SwiftUI.
    ///
    /// - Parameters:
    ///   - id: The identity of the row to scroll to.
    ///   - anchor: Where the row lands in the viewport — `.top`,
    ///     `.center`, `.bottom` — or `nil` (the default) for minimal
    ///     movement: scroll just enough to make the row visible, not at
    ///     all if it already is.
    ///
    /// > Note: Deviations from SwiftUI, both from the terminal scroll
    ///   model. Horizontal-capable scroll views (`axes` containing
    ///   `.horizontal`) don't participate — the seek rides the vertical
    ///   row-windowing handshake. And a `.id(_:)` tag is read off the
    ///   content stack's own children, never from inside a `ForEach` row: a
    ///   row's identity is its element's `id`, which is the rule `.tag(_:)`
    ///   follows too. Decided in one place, so every seek path gives the same
    ///   answer — the ones serving a whole-`ForEach` stack resolve from the
    ///   data's keys and never build a row view to look inside.
    public func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint? = nil) {
        // The SAME stringification ForEach derives its identity keys with,
        // so the key comparison in the seek paths is exact.
        registry.scrollTo(key: identityKey(id), anchor: anchor)
    }
}

// MARK: - ScrollViewReader

/// A view whose content builder receives a ``ScrollViewProxy`` capable of
/// scrolling the scroll views it contains. Matches SwiftUI's type of the
/// same name.
///
/// ```swift
/// ScrollViewReader { proxy in
///     ScrollView {
///         LazyVStack {
///             ForEach(0..<1_000_000, id: \.self) { i in Text("row \(i)") }
///         }
///     }
///     Button("Jump to the middle") { proxy.scrollTo(500_000, anchor: .center) }
/// }
/// ```
public struct ScrollViewReader<Content: View>: View {
    /// The reader's content, given the proxy.
    public var content: (ScrollViewProxy) -> Content

    /// The proxy↔scroll-view rendezvous. `@State` so the SAME registry
    /// survives across frames: a proxy captured by a closure in frame 1
    /// must still reach a scroll view that registers in frame 50.
    @State private var registry = ScrollToRegistry()

    /// Creates a reader whose `content` receives the scrolling proxy.
    public init(@ViewBuilder content: @escaping (ScrollViewProxy) -> Content) {
        self.content = content
    }

    public var body: some View {
        content(ScrollViewProxy(registry: registry))
            .environment(\.scrollToRegistry, registry)
    }
}

// MARK: - Registry

/// The rendezvous between a proxy (used at event time or from async
/// contexts) and the scroll views in a reader's content (which register
/// during render): `scrollTo` parks the request on every live handler and
/// wakes the render loop; the next frame resolves and applies it.
///
/// Not `@MainActor` — like the handlers themselves, it is only ever touched
/// from the render loop and event dispatch (both main-actor); staying
/// nonisolated lets `@State` hold it and view inits create it.
final class ScrollToRegistry: @unchecked Sendable {
    private struct Entry {
        weak var handler: ScrollViewHandler?
        let identity: ViewIdentity
        weak var renderCache: RenderCache?
    }

    /// Live scroll views, keyed by identity path so a re-render refreshes
    /// its entry in place. Handlers are held weakly: a scroll view that
    /// leaves the tree dies with its state, and its entry is swept on the
    /// next `scrollTo`.
    private var entries: [String: Entry] = [:]

    /// Registers (or refreshes) a scroll view for this frame.
    func register(handler: ScrollViewHandler, identity: ViewIdentity, renderCache: RenderCache?) {
        entries[identity.path] = Entry(
            handler: handler, identity: identity, renderCache: renderCache)
    }

    /// Parks the request on every live registered scroll view — each
    /// resolves independently against its own content; ones without the
    /// key no-op — and invalidates each one's identity through the render
    /// cache it rendered with, so `scrollTo` works from `.task`/async
    /// contexts where no input event would otherwise trigger a frame.
    ///
    /// That is the sink a `@State` write uses: it asks the run loop for a
    /// frame, and that frame's start drops the cached buffers of the scroll
    /// view, of its content and of everything above it. With no live scroll
    /// view it asks for nothing.
    func scrollTo(key: String, anchor: UnitPoint?) {
        for (path, entry) in entries {
            guard let handler = entry.handler else {
                entries[path] = nil
                continue
            }
            handler.pendingScrollTo = ScrollToRequest(key: key, anchor: anchor)
            entry.renderCache?.invalidateRender(for: entry.identity)
        }
    }
}

// MARK: - Environment

private struct ScrollToRegistryKey: EnvironmentKey {
    static let defaultValue: ScrollToRegistry? = nil
}

extension EnvironmentValues {
    /// The enclosing ``ScrollViewReader``'s registry, which the scroll
    /// views in its content register with each render pass. `nil` outside
    /// any reader.
    var scrollToRegistry: ScrollToRegistry? {
        get { self[ScrollToRegistryKey.self] }
        set { self[ScrollToRegistryKey.self] = newValue }
    }
}
