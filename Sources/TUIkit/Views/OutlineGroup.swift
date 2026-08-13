//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OutlineGroup.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - OutlineGroup

/// A tree, drawn from a collection and a key path to each element's children.
///
/// ```swift
/// struct Node: Identifiable {
///     let id = UUID()
///     let name: String
///     var children: [Node]?      // nil = a leaf
/// }
///
/// ScrollView {
///     OutlineGroup(tree, children: \.children) { node in
///         Text(node.name)
///     }
/// }
/// ```
///
/// ```
///   ▼ Sources
///       ▶ TUIkit
///       ▼ TUIkitCore
///           Rendering
///           Extensions
///     README.md
/// ```
///
/// With the mouse it is the **triangle** that discloses, not the whole row —
/// unlike ``DisclosureGroup``, which has no competition for its row, an outline
/// row's text belongs to whatever the outline is inside, so that a ``List`` can
/// select the node whose triangle just opened it. A single cell is a mean
/// target, so the triangle quietly extends over the blank cell on either side:
/// four cells to hit, one glyph to read.
///
/// ## From the keyboard
///
/// On its own — in a `VStack`, a `ScrollView` — each branch's triangle is a Tab
/// stop, and **Return** or **Space** opens or closes it, as any button would.
///
/// Inside a ``List`` the row is the focusable and the triangle is not, because
/// a row has a *selection* as well as an action and the two must not compete:
///
/// - **Space** selects the focused row, as it does in any list.
/// - **Return** activates it, which for a branch means disclosing it — unless
///   the app claims Return with ``List/onRowActivate(_:)``, which wins.
/// - **Right** opens the focused branch and **Left** closes it, so a tree stays
///   reachable when the app has taken Return. Both fall through on a leaf, on a
///   branch already in that state, and on a list that is not a tree at all.
///
/// The glyphs and the indent step are ``DisclosureGroup``'s. A leaf's label
/// lines up with its siblings' labels rather than with their triangles, so a
/// column of names stays a column.
///
/// `children` is the whole distinction between a branch and a leaf: `nil` is a
/// leaf and gets no triangle; a non-`nil` collection is a group, **even when it
/// is empty** — which is SwiftUI's rule, and the right one, since "this folder
/// has nothing in it" is worth being able to say.
///
/// ## Its nodes are the container's rows
///
/// An outline emits one row per *visible* node to whatever contains it, exactly
/// as ``ForEach`` emits one per element — a `VStack` lays them out as siblings,
/// and a `List` makes each one a selectable row of its own, which is what
/// `List(_:children:)` is. The depth lives in each row's leading padding rather
/// than in the view hierarchy, so a deep tree is not a deep view hierarchy, and
/// a closed branch's descendants are neither built nor measured — the
/// flattening walk simply stops there.
///
/// That is why, like `ForEach`, this has no `body` of its own: it is not one
/// view, it is a run of them.
///
/// The expansion is the group's own, starting closed, exactly as in SwiftUI —
/// ``DisclosureGroup`` is the one to reach for when something outside needs to
/// drive it.
///
/// - Note: SwiftUI's `OutlineGroup` carries five generic parameters; two of
///   them (`Parent` and `Subgroup`) are phantom — `Parent` is always `Leaf`,
///   and `Subgroup` can only ever be the one `DisclosureGroup` specialization
///   — so TUIkit declares the three that carry information and drops SwiftUI's
///   `OutlineSubgroupChildren` marker with them. Every initializer is
///   unchanged; only spelling the type out by hand differs. (Same call as
///   ``Gauge``, which likewise drops a generic parameter with no terminal
///   meaning.)
public struct OutlineGroup<Data: RandomAccessCollection, ID: Hashable, Leaf: View>: View {
    /// The top-level elements, flattened out of whichever initializer was used
    /// so one implementation serves both the `root` and the collection forms.
    let roots: [Data.Element]

    /// Each element's stable identity.
    let idKeyPath: KeyPath<Data.Element, ID>

    /// Each element's children — `nil` for a leaf.
    let childrenKeyPath: KeyPath<Data.Element, Data?>

    /// Builds a node's label.
    let content: (Data.Element) -> Leaf

    /// The bridge a hierarchical ``List`` drives the disclosure through.
    ///
    /// A reference type deliberately: this value is rebuilt every frame, and
    /// the list re-reads it every frame too, so the pair always agree — but the
    /// closure inside has to survive from the render that installs it to the
    /// keystroke that calls it.
    let activation = OutlineActivation()

    /// Never called: an outline is a run of rows, not one view, so it hands its
    /// children to its container instead of rendering itself. `ForEach` says
    /// the same thing the same way.
    public var body: Never {
        fatalError("OutlineGroup has no standalone rendering; use it inside a container")
    }
}

// MARK: - Disclosure from the list's own row cursor

/// How a hierarchical ``List`` reaches the disclosure of the row its cursor is
/// on.
///
/// The two halves are built in one initializer but only meet at render: an
/// outline does not learn where its expansion lives until it is handed a
/// context, while the list's key handling has to reach it from a handler
/// configured before any key arrives. This reference type is what both hold —
/// the outline fills it in each pass, the list calls through it.
///
/// Not actor-isolated, for the same reason ``ItemListHandler``'s
/// `primaryAction` is a plain closure: key dispatch reaches the handler from a
/// nonisolated context, and rendering — the only thing that ever writes here —
/// is single-threaded on the run loop.
protocol OutlineRowActivating {
    /// Opens, closes or toggles the node with this id.
    ///
    /// - Parameters:
    ///   - id: The row's id, as the list knows it.
    ///   - target: `true` to open, `false` to close, `nil` to toggle.
    /// - Returns: Whether anything moved — `false` for a leaf, for an unknown
    ///   id, or for a branch already in the requested state, so the key falls
    ///   through to whatever else wants it.
    @discardableResult
    func setRowExpanded(_ id: AnyHashable, to target: Bool?) -> Bool
}

/// The mutable half of ``OutlineRowActivating``, refreshed every pass.
final class OutlineActivation: @unchecked Sendable {
    /// Installed by ``OutlineGroup/extractListRows(context:)`` with that
    /// frame's real expansion box captured. `nil` before the first render.
    var apply: ((AnyHashable, Bool?) -> Bool)?
}

// MARK: - The rows

extension OutlineGroup {
    /// The rows to draw, depth-first, stopping at every closed branch.
    ///
    /// Recomputed per pass rather than cached: it is a function of the data and
    /// the expansion set, both of which the caller already has, and an outline
    /// is sized by what a person can actually see.
    func visibleNodes(expanded: Set<ID>) -> [Node] {
        var nodes: [Node] = []
        // An explicit stack rather than recursion: a deep tree must not put the
        // render pass any nearer the stack limit than the view hierarchy
        // already does. Pushed in reverse, so the top of the stack is always
        // the next node in reading order.
        var stack: [(element: Data.Element, depth: Int)] = roots.reversed().map { ($0, 0) }
        while let (element, depth) = stack.popLast() {
            let id = element[keyPath: idKeyPath]
            let children = element[keyPath: childrenKeyPath]
            let isOpen = expanded.contains(id)
            nodes.append(
                Node(
                    id: id, element: element, depth: depth, isBranch: children != nil,
                    isExpanded: isOpen))
            guard let children, isOpen else { continue }
            for child in children.reversed() {
                stack.append((child, depth + 1))
            }
        }
        return nodes
    }

    /// The view for one node's row.
    ///
    /// - Parameter rowOwnsFocus: Whether something else — a `List`'s own row
    ///   cursor — is the focusable here. When it is, the triangle must not be a
    ///   second Tab stop inside the row: it would take the row's Space with it,
    ///   and a tree of N branches would add N stops nobody asked for.
    func row(
        for node: Node, expansion: StateBox<Set<ID>>, rowOwnsFocus: Bool = false
    ) -> _OutlineRow<Data.Element, ID, Leaf> {
        _OutlineRow(
            element: node.element, id: node.id, depth: node.depth, isBranch: node.isBranch,
            isExpanded: node.isExpanded, expansion: expansion, rowOwnsFocus: rowOwnsFocus,
            content: content)
    }

    /// The persistent set of open node ids.
    ///
    /// Kept in the render-pass `StateStorage` rather than in an `@State`
    /// property, because neither path that draws an outline goes through
    /// `body`: a container asks for ``childViews(context:)`` and a `List` for
    /// ``extractListRows(context:)``, and `@State` is bound during a view's own
    /// render, which never happens. Both of those hand over a context, which is
    /// what this needs anyway.
    ///
    /// The identity is a child step off the container's, keyed by name, so two
    /// outlines in different places keep different sets. Two *siblings* of the
    /// same type in one container would share one — the same collision
    /// `ForEach` has for its rows' state, and for the same reason.
    func expansion(context: RenderContext) -> StateBox<Set<ID>> {
        let identity = context.withChildIdentity(erasedType: Self.self, key: "outline").identity
        guard let storage = context.stateStorage else { return StateBox([]) }
        // Nothing renders this identity, so nothing else will mark it — without
        // this the set is collected at the end of the pass that created it and
        // every branch closes itself again on the next frame.
        storage.markActive(identity)
        return storage.storage(
            for: StateStorage.StateKey(identity: identity, propertyIndex: 0), default: [])
    }

    /// A node as it appears on screen: the element, how deep it sits, whether
    /// it has a triangle, and which way that triangle points.
    struct Node {
        let id: ID
        let element: Data.Element
        let depth: Int
        let isBranch: Bool

        /// Carried on the node rather than re-read per row, so the flattening
        /// walk is the only thing that consults the expansion set — the row
        /// and the walk cannot disagree about which triangle to draw.
        let isExpanded: Bool
    }
}

// MARK: - One row per visible node

extension OutlineGroup: ChildViewProvider {
    /// One child per visible node, keyed by the node's id — so a stack lays the
    /// tree out as a column of siblings, and each row's own state follows its
    /// node rather than its position.
    public func childViews(context: RenderContext) -> [ChildView] {
        let expansion = expansion(context: context)
        return visibleNodes(expanded: expansion.value).map { node in
            ChildView(
                row(for: node, expansion: expansion),
                identityType: _OutlineRow<Data.Element, ID, Leaf>.self,
                key: identityKey(node.id))
        }
    }
}

extension OutlineGroup: OutlineRowActivating {
    /// `nonisolated` because key dispatch is: the handler reaches this from
    /// outside the main actor, and everything it touches — a `let` reference
    /// and the closure inside it — is written only by the render loop.
    @discardableResult
    nonisolated func setRowExpanded(_ id: AnyHashable, to target: Bool?) -> Bool {
        activation.apply?(id, target) ?? false
    }
}

extension OutlineGroup: ListRowExtractor {
    /// One list row per visible node, so a `List` selects, reveals and scrolls
    /// to *nodes* rather than to the outline as a whole.
    ///
    /// Eager rather than windowed: the row count is a function of the expansion
    /// set, so answering it at all means walking the visible nodes — which is
    /// the same O(visible) the list was going to pay. Content is still built
    /// lazily, per row, exactly as `ForEach` does it.
    func extractListRows<RowID: Hashable>(context: RenderContext) -> [ListRow<RowID>] {
        let expansion = expansion(context: context)
        let nodes = visibleNodes(expanded: expansion.value)
        // What the list will call a row is not always what the outline calls a
        // node: a list with no selection binding is keyed by `Int`, so its rows
        // are POSITIONS. The disclosure has to be reachable from whichever id
        // the list hands back, so the two are paired here, where both are in
        // hand — branches only, since a leaf must let the key fall through
        // rather than swallow a Left or Right it has no use for.
        var branchNodeID: [AnyHashable: ID] = [:]
        var rows: [ListRow<RowID>] = []
        rows.reserveCapacity(nodes.count)
        for (index, node) in nodes.enumerated() {
            guard let rowID: RowID = (node.id as? RowID) ?? (index as? RowID) else { continue }
            if node.isBranch {
                branchNodeID[AnyHashable(rowID)] = node.id
            }
            let view = row(for: node, expansion: expansion, rowOwnsFocus: true)
            let rowContext = context.withChildIdentity(
                erasedType: _OutlineRow<Data.Element, ID, Leaf>.self,
                key: identityKey(node.id))
            rows.append(
                ListRow(
                    id: rowID,
                    content: LazyListRowContent(identity: rowContext.identity) {
                        (TUIkit.renderToBuffer(view, context: rowContext), nil)
                    }))
        }
        activation.apply = { erased, target in
            guard let id = branchNodeID[erased] else { return false }
            let isOpen = expansion.value.contains(id)
            let wanted = target ?? !isOpen
            guard wanted != isOpen else { return false }
            if wanted {
                expansion.value.insert(id)
            } else {
                expansion.value.remove(id)
            }
            return true
        }
        return rows
    }
}

// MARK: - A row

/// One node's row: the disclosure triangle (when it has one) and the label.
///
/// Its own type rather than a `@ViewBuilder` result so the row has a name —
/// which is what a `ChildView` needs to key each node's identity by.
public struct _OutlineRow<Element, ID: Hashable, Leaf: View>: View {
    let element: Element
    let id: ID
    let depth: Int
    let isBranch: Bool
    let isExpanded: Bool

    /// The outline's open-node set, held directly. It is the persistent box, so
    /// writing to it from the button below outlives this frame and asks for the
    /// next one — which is the whole reason the row carries it rather than a
    /// snapshot of the value.
    let expansion: StateBox<Set<ID>>

    /// Whether the container owns this row's focus — see
    /// ``OutlineGroup/row(for:expansion:rowOwnsFocus:)``.
    let rowOwnsFocus: Bool

    let content: (Element) -> Leaf

    public var body: some View {
        if isBranch {
            HStack(spacing: 0) {
                // Only the TRIANGLE toggles, not the whole row — the rest of an
                // outline row belongs to whatever the outline is inside, which
                // is what lets a list select the node the triangle discloses.
                //
                // One cell is a small target, so the button is deliberately
                // wider than its glyph: the frame adds the blank cell after the
                // triangle, and the focus gutter contributes the two before it.
                // Four cells to hit, one glyph to read.
                //
                // Inside a list the triangle keeps that click target but stops
                // being FOCUSABLE: the row is the focusable there, Space is the
                // row's (it selects) and Return is the row's (it activates —
                // which for a branch means disclosing it). A second focus stop
                // in the row would take both keys with it.
                triangle

                content(element)
            }
            .padding(.leading, depth * DisclosureMetrics.contentIndent)
        } else {
            // One step further in than its depth, so a leaf's label lands in
            // the same column as a sibling branch's label rather than under
            // that branch's triangle.
            content(element)
                .padding(.leading, (depth + 1) * DisclosureMetrics.contentIndent)
        }
    }

    /// The triangle: a Tab stop of its own when nothing else owns the row, a
    /// bare tappable glyph when a list's cursor does.
    @ViewBuilder
    private var triangle: some View {
        let glyph = Text(verbatim: isExpanded
            ? TerminalSymbols.disclosureExpanded
            : TerminalSymbols.disclosureCollapsed)
            .frame(width: DisclosureMetrics.triangleColumnWidth)
        if rowOwnsFocus {
            // The same four cells, still clickable — the focus gutter is drawn
            // by the list's own cursor rather than by a button here, so the
            // glyph is padded to keep the column it had.
            glyph
                .padding(.leading, BorderRenderer.focusIndicatorWidth)
                .onTapGesture { _, _ in toggle() }
        } else {
            Button(action: toggle, label: { glyph })
                .buttonStyle(.plain)
        }
    }

    /// Opens a closed node, or closes an open one.
    private func toggle() {
        if expansion.value.contains(id) {
            expansion.value.remove(id)
        } else {
            expansion.value.insert(id)
        }
    }
}

// MARK: - Initializers (Identifiable)

extension OutlineGroup where Data.Element: Identifiable, ID == Data.Element.ID {
    /// Creates an outline rooted at a single element.
    ///
    /// - Parameters:
    ///   - root: The element at the top of the tree.
    ///   - children: A key path to an element's children, or `nil` for a leaf.
    ///   - content: Builds a node's label.
    public init<DataElement>(
        _ root: DataElement,
        children: KeyPath<DataElement, Data?>,
        @ViewBuilder content: @escaping (DataElement) -> Leaf
    ) where DataElement == Data.Element {
        self.init(roots: [root], id: \.id, children: children, content: content)
    }

    /// Creates an outline from a collection of top-level elements.
    ///
    /// - Parameters:
    ///   - data: The elements at the top of the tree.
    ///   - children: A key path to an element's children, or `nil` for a leaf.
    ///   - content: Builds a node's label.
    public init<DataElement>(
        _ data: Data,
        children: KeyPath<DataElement, Data?>,
        @ViewBuilder content: @escaping (DataElement) -> Leaf
    ) where DataElement == Data.Element {
        self.init(roots: Array(data), id: \.id, children: children, content: content)
    }
}

// MARK: - Initializers (explicit id)

extension OutlineGroup {
    /// Creates an outline rooted at a single element, keyed by an explicit id.
    ///
    /// - Parameters:
    ///   - root: The element at the top of the tree.
    ///   - id: A key path to each element's stable identity.
    ///   - children: A key path to an element's children, or `nil` for a leaf.
    ///   - content: Builds a node's label.
    public init<DataElement>(
        _ root: DataElement,
        id: KeyPath<DataElement, ID>,
        children: KeyPath<DataElement, Data?>,
        @ViewBuilder content: @escaping (DataElement) -> Leaf
    ) where DataElement == Data.Element {
        self.init(roots: [root], id: id, children: children, content: content)
    }

    /// Creates an outline from a collection of top-level elements, keyed by an
    /// explicit id.
    ///
    /// - Parameters:
    ///   - data: The elements at the top of the tree.
    ///   - id: A key path to each element's stable identity.
    ///   - children: A key path to an element's children, or `nil` for a leaf.
    ///   - content: Builds a node's label.
    public init<DataElement>(
        _ data: Data,
        id: KeyPath<DataElement, ID>,
        children: KeyPath<DataElement, Data?>,
        @ViewBuilder content: @escaping (DataElement) -> Leaf
    ) where DataElement == Data.Element {
        self.init(roots: Array(data), id: id, children: children, content: content)
    }

    /// The one designated initializer the four public ones funnel through.
    private init(
        roots: [Data.Element],
        id: KeyPath<Data.Element, ID>,
        children: KeyPath<Data.Element, Data?>,
        content: @escaping (Data.Element) -> Leaf
    ) {
        self.roots = roots
        self.idKeyPath = id
        self.childrenKeyPath = children
        self.content = content
    }
}
