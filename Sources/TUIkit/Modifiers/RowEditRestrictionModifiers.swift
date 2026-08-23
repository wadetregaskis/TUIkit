//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RowEditRestrictionModifiers.swift
//
//  Rows that refuse to be deleted or moved.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

/// Which edits a row has refused, gathered as the rows render.
///
/// A collector rather than a value on the row because the flag is stated INSIDE
/// the row's subtree — `Text(…).deleteDisabled(true).padding()` puts the
/// padding outermost — so reading it structurally would depend on modifier
/// order. Reporting on render does not.
///
/// One per `List` per frame. Absence means allowed, which is what makes a row
/// that never rendered (off the window) harmless: the only rows a user can
/// delete or move are the focused one and the grabbed one, and both are on
/// screen by construction.
@MainActor
final class RowEditRestrictions {
    /// Data offsets whose rows refused deletion this frame.
    private(set) var deleteDisabled: Set<Int> = []

    /// Data offsets whose rows refused to be moved this frame.
    private(set) var moveDisabled: Set<Int> = []

    func disableDelete(row: Int) { deleteDisabled.insert(row) }
    func disableMove(row: Int) { moveDisabled.insert(row) }
}

extension EnvironmentValues {
    /// Where a row states the edits it refuses. Installed by `_ListCore`.
    var listRowEditRestrictions: RowEditRestrictions? {
        get { self[RowEditRestrictionsKey.self] }
        set { self[RowEditRestrictionsKey.self] = newValue }
    }

    /// The data offset of the row being built. Stamped by `ForEach`, which is
    /// the only thing that knows it — the modifier is written on the row's
    /// content and has no idea where in the collection it sits.
    var listRowEditIndex: Int? {
        get { self[RowEditIndexKey.self] }
        set { self[RowEditIndexKey.self] = newValue }
    }
}

private struct RowEditRestrictionsKey: EnvironmentKey {
    static let defaultValue: RowEditRestrictions? = nil
}

private struct RowEditIndexKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

// MARK: - Modifiers

extension View {
    /// Prevents this row from being deleted.
    ///
    /// Write it inside a `ForEach` whose content the `List` can delete — one
    /// with an `onDelete` action, or `editActions` naming `.delete`. The row
    /// still draws, still selects and still takes the focus; Delete and
    /// Backspace simply do nothing on it, and fall through to whatever else
    /// wants them, exactly as they do in a list that is not deletable at all.
    ///
    /// ```swift
    /// ForEach(files) { file in
    ///     Text(file.name)
    ///         .deleteDisabled(file.isReadOnly)
    /// }
    /// .onDelete { files.remove(atOffsets: $0) }
    /// ```
    ///
    /// - Parameter isDisabled: Whether to refuse deletion.
    /// - Returns: A row that refuses to be deleted.
    public func deleteDisabled(_ isDisabled: Bool = true) -> some View {
        _RowEditRestrictionView(content: self, restriction: .delete, isDisabled: isDisabled)
    }

    /// Prevents this row from being moved.
    ///
    /// Write it inside a reorderable `ForEach`. A drag on the row does not pick
    /// it up — no gesture starts, so there is no floating preview and nothing
    /// to release — and a keyboard row-move leaves it where it is. Other rows
    /// still move freely, INCLUDING past this one: `moveDisabled` says this row
    /// does not travel, not that its position is fixed, which is SwiftUI's
    /// meaning too.
    ///
    /// - Parameter isDisabled: Whether to refuse moving.
    /// - Returns: A row that refuses to be moved.
    public func moveDisabled(_ isDisabled: Bool = true) -> some View {
        _RowEditRestrictionView(content: self, restriction: .move, isDisabled: isDisabled)
    }
}

/// Reports one refusal to the enclosing `List` as the row renders.
///
/// - Important: Framework infrastructure. Created by ``View/deleteDisabled(_:)``
///   and ``View/moveDisabled(_:)``.
public struct _RowEditRestrictionView<Content: View>: View {
    /// Which edit is being refused.
    enum Restriction {
        case delete
        case move
    }

    let content: Content
    let restriction: Restriction
    let isDisabled: Bool

    public var body: Never {
        fatalError("_RowEditRestrictionView renders via Renderable")
    }
}

extension _RowEditRestrictionView: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        report(context)
        return TUIkit.renderToBuffer(content, context: context)
    }

    /// Tells the list this row refuses the edit — and declares a render side
    /// effect while doing it.
    ///
    /// Both only when actually disabled, and that asymmetry is the whole
    /// performance story. A row's buffer can be served from the value memo
    /// without re-rendering, and a memoized row never reaches this code, so a
    /// refusal that did not opt out of caching would be reported on the frame
    /// it appeared and forgotten on every frame after — the row would quietly
    /// become deletable again. Declaring the side effect keeps a refusing row
    /// out of the memo, so it re-renders and re-reports every frame.
    ///
    /// A row that refuses NOTHING says nothing and pays nothing: it reports no
    /// restriction, declares no side effect, and memoizes exactly as it did
    /// before this modifier existed. Since `deleteDisabled(false)` is what most
    /// rows in a list carrying the modifier evaluate to, that is the case worth
    /// keeping free.
    private func report(_ context: RenderContext) {
        guard isDisabled, !context.isMeasuring,
            let restrictions = context.environment.listRowEditRestrictions,
            let row = context.environment.listRowEditIndex
        else { return }
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        switch restriction {
        case .delete: restrictions.disableDelete(row: row)
        case .move: restrictions.disableMove(row: row)
        }
    }
}

extension _RowEditRestrictionView: Layoutable {
    /// Measures as its content: the report is the whole of this view's effect,
    /// and it contributes no geometry.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}
