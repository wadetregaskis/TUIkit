//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RowEditRestrictionModifiers.swift
//
//  Rows that refuse to be deleted, moved, or selected.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

/// Which edits — and whether selection — a row has refused, gathered as the
/// rows render.
///
/// A collector rather than a value on the row because the flag is stated INSIDE
/// the row's subtree — `Text(…).deleteDisabled(true).padding()` puts the
/// padding outermost — so reading it structurally would depend on modifier
/// order. Reporting on render does not.
///
/// One per `List` per frame. Absence means allowed, which is what makes a row
/// that never rendered (off the window) harmless for delete/move: the only
/// rows a user can delete or move are the focused one and the grabbed one,
/// and both are on screen by construction. Selection is the one restriction
/// here that is not so contained — Up/Down can land the cursor on a row that
/// has never rendered — so a `.selectionDisabled()` row is only skipped by
/// navigation once a frame has drawn it and reported it here; see
/// ``ItemListHandler/selectionDisabledRows``.
@MainActor
final class RowEditRestrictions {
    /// LIST ROWS that refused deletion this frame.
    private(set) var deleteDisabled: Set<Int> = []

    /// List rows that refused to be moved this frame.
    private(set) var moveDisabled: Set<Int> = []

    /// List rows that refused to be selected this frame.
    private(set) var selectionDisabled: Set<Int> = []

    /// The LIST ROW currently rendering, stamped by the List's row
    /// materialisation just before each row renders — the only code that knows
    /// it, since the modifier is written on the row's content and has no idea
    /// where in the list it sits.
    ///
    /// A list row, not the row's offset in its own `ForEach`'s collection: the
    /// handler compares these sets against the focused row and the grabbed
    /// row, and both of those are list rows. The two are the same number only
    /// in a flat `List { ForEach … }`. Inside a `Section` they differ by
    /// ``rowIndexBase``, and with two Sections the offsets COLLIDE — each
    /// section counts its own rows from 0, so `.deleteDisabled()` on the
    /// second section's second row named the first section's second row as
    /// well as (in fact, instead of) its own.
    ///
    /// A field on this (per-List, per-frame) collector rather than an
    /// environment value because the environment is a copy-on-write
    /// dictionary: stamping a per-row Int into it copied the WHOLE dictionary
    /// — every environment entry rehashed, reboxed and retained — once per
    /// visible row per frame, which a windowed List pays for every row it
    /// shows. Writing a property on the already-installed collector is free,
    /// and rows render strictly one at a time, so the single slot cannot be
    /// observed with a neighbour's value. A nested List installs its own
    /// collector for its subtree, so the inner rows stamp the inner one and
    /// the outer row's stamp stays good for the rest of its own render.
    var currentRowIndex: Int?

    /// The list row at which the `ForEach` now being extracted draws its first
    /// element — what its per-element index is counted from to reach
    /// ``currentRowIndex``.
    ///
    /// Zero for a flat `List { ForEach … }`, where the two numberings coincide.
    /// Set by `_ListCore` around each `Section`'s extraction, and READ when a
    /// row's deferred content box is built (which for a Section's rows is
    /// during that same extraction), not when the box later renders — by then
    /// another section may have moved it.
    var rowIndexBase = 0

    func disableDelete(row: Int) { deleteDisabled.insert(row) }
    func disableMove(row: Int) { moveDisabled.insert(row) }
    func disableSelection(row: Int) { selectionDisabled.insert(row) }
}

extension EnvironmentValues {
    /// Where a row states the edits (and selection) it refuses. Installed by
    /// `_ListCore`.
    var listRowEditRestrictions: RowEditRestrictions? {
        get { self[RowEditRestrictionsKey.self] }
        set { self[RowEditRestrictionsKey.self] = newValue }
    }
}

private struct RowEditRestrictionsKey: EnvironmentKey {
    static let defaultValue: RowEditRestrictions? = nil
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
            let row = restrictions.currentRowIndex
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
