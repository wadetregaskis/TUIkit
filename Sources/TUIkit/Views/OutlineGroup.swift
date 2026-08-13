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
/// Every branch is a Tab stop, and **Return** or **Space** opens or closes it.
/// With the mouse it is the **triangle** that discloses, not the whole row —
/// unlike ``DisclosureGroup``, which has no competition for its row, an outline
/// row's text belongs to whatever the outline is inside, so that a ``List`` can
/// select the node whose triangle just opened it. A single cell is a mean
/// target, so the triangle's button quietly extends over the blank cell on
/// either side: four cells to hit, one glyph to read.
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

    /// Never called: an outline is a run of rows, not one view, so it hands its
    /// children to its container instead of rendering itself. `ForEach` says
    /// the same thing the same way.
    public var body: Never {
        fatalError("OutlineGroup has no standalone rendering; use it inside a container")
    }
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
    func row(for node: Node, expansion: StateBox<Set<ID>>) -> _OutlineRow<Data.Element, ID, Leaf> {
        _OutlineRow(
            element: node.element, id: node.id, depth: node.depth, isBranch: node.isBranch,
            isExpanded: node.isExpanded, expansion: expansion, content: content)
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
        return visibleNodes(expanded: expansion.value).enumerated()
            .compactMap { index, node -> ListRow<RowID>? in
                guard let rowID: RowID = (node.id as? RowID) ?? (index as? RowID) else {
                    return nil
                }
                let view = row(for: node, expansion: expansion)
                let rowContext = context.withChildIdentity(
                    erasedType: _OutlineRow<Data.Element, ID, Leaf>.self,
                    key: identityKey(node.id))
                return ListRow(
                    id: rowID,
                    content: LazyListRowContent(identity: rowContext.identity) {
                        (TUIkit.renderToBuffer(view, context: rowContext), nil)
                    })
            }
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
                Button(
                    action: toggle,
                    label: {
                        Text(verbatim: isExpanded
                            ? TerminalSymbols.disclosureExpanded
                            : TerminalSymbols.disclosureCollapsed)
                            .frame(width: DisclosureMetrics.triangleColumnWidth)
                    }
                )
                .buttonStyle(.plain)

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
