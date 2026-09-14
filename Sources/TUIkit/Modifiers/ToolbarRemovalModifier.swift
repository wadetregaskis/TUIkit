//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToolbarRemovalModifier.swift
//
//  `View.toolbar(removing:)`: take away a control the framework provides by
//  default. TUIkit has no toolbar container (see
//  `Documentation/SwiftUI-compatibility.md` §2.6); the one default item it has
//  is the split view's sidebar toggle, which lives on the split itself.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Toolbar Default Item Kind

/// A kind of control the framework provides by default, which
/// ``View/toolbar(removing:)`` can take away.
///
/// Mirrors SwiftUI's `ToolbarDefaultItemKind`. TUIkit has no toolbar, so the
/// only kind is ``sidebarToggle``, the ``NavigationSplitView``'s own handles.
/// SwiftUI's `.title` is not provided: TUIkit draws no default title to remove.
public struct ToolbarDefaultItemKind {
    /// The item kinds TUIkit has.
    enum Kind {
        case sidebarToggle
    }

    let kind: Kind

    /// A ``NavigationSplitView``'s sidebar toggle: the ◀ on its leftmost divider
    /// and the ▶ edge column shown while a leading column is hidden.
    ///
    /// SwiftUI declares this `static let`. A computed property reads the same at
    /// every call site, and a `static let` of this type would be global state
    /// Swift 6 rejects, since the type is deliberately not `Sendable` (as in
    /// SwiftUI).
    public static var sidebarToggle: Self { Self(kind: .sidebarToggle) }
}

/// Not `Sendable`, exactly as SwiftUI declares it.
@available(*, unavailable)
extension ToolbarDefaultItemKind: Sendable {}

// MARK: - Storage

/// Whether a ``View/toolbar(removing:)`` inside a split view's column removed the
/// sidebar toggle. A preference, because the modifier may sit anywhere inside
/// the column and the split view reads it from outside; `true` wins.
struct SidebarToggleRemovedKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

private struct SidebarToggleRemovedEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether a ``View/toolbar(removing:)`` on or above this view removed a
    /// split view's sidebar toggle.
    var sidebarToggleRemoved: Bool {
        get { self[SidebarToggleRemovedEnvironmentKey.self] }
        set { self[SidebarToggleRemovedEnvironmentKey.self] = newValue }
    }
}

// MARK: - Modifier

/// Publishes a sidebar-toggle removal into the enclosing preference scope, for a
/// split view whose column holds it, and renders `content` unchanged.
struct SidebarToggleRemovalView<Content: View>: View {
    let content: Content

    /// Whether this modifier removes the toggle; `false` for `nil`, which
    /// publishes nothing.
    let publishes: Bool

    var body: Never {
        fatalError("SidebarToggleRemovalView renders via Renderable")
    }

    /// Declared as a per-pass side effect for the reason
    /// `NavigationSplitViewColumnWidthView` declares its write: a memoising
    /// ancestor serving a cached buffer or measurement would drop the write, and
    /// the split view would put its toggle back.
    private func publish(context: RenderContext) {
        guard publishes else { return }
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        context.environment.preferenceStorage?.setValue(true, forKey: SidebarToggleRemovedKey.self)
    }
}

extension SidebarToggleRemovalView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        publish(context: context)
        return TUIkit.renderToBuffer(content, context: context)
    }
}

extension SidebarToggleRemovalView: Layoutable {
    /// Publishes during a measure too: the split view measures a column to learn
    /// what it asked for before it lays the handles out. The key's `reduce` is an
    /// OR, so publishing twice in a pass is idempotent.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        publish(context: context)
        return measureChild(content, proposal: proposal, context: context)
    }
}

extension View {
    /// Removes a control the framework provides by default.
    ///
    /// With ``ToolbarDefaultItemKind/sidebarToggle`` it removes a
    /// ``NavigationSplitView``'s toggle handles: the ◀ on its leftmost divider
    /// (which goes back to three grip dots, or to a plain space when the split
    /// cannot resize) and the ▶ edge column shown while a leading column is
    /// hidden. `nil` removes nothing, and does not undo a removal further out.
    ///
    /// ```swift
    /// NavigationSplitView {
    ///     Sidebar()
    ///         .toolbar(removing: .sidebarToggle)
    /// } detail: {
    ///     Detail()
    /// }
    /// ```
    ///
    /// The modifier works on the split view, anywhere above it, or anywhere
    /// inside one of its columns. A hidden column is not rendered, so the split
    /// view remembers what each column said the last time it was shown. A split
    /// that is hidden from its very first frame has never shown its leading
    /// columns, so put the modifier on the split view or in the detail column.
    ///
    /// Removing the handles does not change what `columnVisibility` can do from
    /// code.
    ///
    /// TUIkit has no toolbar: this is a removal, not a toolbar container (see
    /// `Documentation/SwiftUI-compatibility.md` §2.6).
    ///
    /// - Parameter defaultItemKind: The kind of control to remove, or `nil`.
    /// - Returns: A view whose split views omit that control.
    public func toolbar(removing defaultItemKind: ToolbarDefaultItemKind?) -> some View {
        // Reduced to a Bool before it reaches the environment or the preference
        // store, neither of which should hold a non-Sendable value.
        let removes = defaultItemKind?.kind == .sidebarToggle
        return SidebarToggleRemovalView(
            content: transformEnvironment(\.sidebarToggleRemoved) { removed in
                if removes { removed = true }
            },
            publishes: removes)
    }
}
