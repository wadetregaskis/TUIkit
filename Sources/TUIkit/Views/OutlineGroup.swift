//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OutlineGroup.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

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
/// Each node is a Tab stop while it can disclose anything: **Return**, **Space**
/// or a click on its row opens or closes it, as in ``DisclosureGroup``, whose
/// glyphs and indent step this shares. A leaf's label lines up with its
/// siblings' labels rather than with their triangles, so a column of names
/// stays a column.
///
/// `children` is the whole distinction between a branch and a leaf: `nil` is a
/// leaf and gets no triangle; a non-`nil` collection is a group, **even when it
/// is empty** — which is SwiftUI's rule, and the right one, since "this folder
/// has nothing in it" is worth being able to say.
///
/// ## It is a flat column of rows, not a nest of views
///
/// A node's children are *sibling rows* indented one step, not a subtree
/// rendered inside it. So the tree costs one row per node you can actually
/// see: the depth lives in each row's leading padding rather than in the view
/// hierarchy, and a closed branch's descendants are neither built nor
/// measured. Nesting the levels instead would make a deep tree a deep view
/// hierarchy, which is the shape a terminal renderer likes least.
///
/// The rows are a `VStack`, so an outline is one child of whatever contains
/// it. That is what a `ScrollView` or a `VStack` wants; feeding each node to a
/// ``List`` as its own selectable row is the separate step SwiftUI spells
/// `List(_:children:)`, and this flattening is what it will be built on.
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

    /// Which nodes are open. The group's own, as in SwiftUI: an outline has no
    /// `isExpanded:` binding, because the interesting state is a *set* and
    /// SwiftUI does not publish it.
    @State private var expanded: Set<ID> = []

    public var body: some View {
        // A column of rows, one per VISIBLE node — nothing at all is built for
        // a closed branch. `.leading`, because an outline's rows are a ragged
        // left-aligned column and centring them would undo the indent that
        // makes it a tree.
        VStack(alignment: .leading, spacing: 0) {
            ForEach(visibleNodes, id: \.id) { node in
                row(for: node)
            }
        }
    }

    /// The rows to draw, depth-first, stopping at every closed branch.
    ///
    /// Recomputed per pass rather than cached: it is a function of the data and
    /// the expansion set, both of which the render already has, and an outline
    /// is sized by what a person can see.
    private var visibleNodes: [Node] {
        var nodes: [Node] = []
        // An explicit stack rather than recursion: a deep tree must not put the
        // render pass any nearer the stack limit than the view hierarchy
        // already does. Pushed in reverse, so the top of the stack is always
        // the next node in reading order.
        var stack: [(element: Data.Element, depth: Int)] = roots.reversed().map { ($0, 0) }
        while let (element, depth) = stack.popLast() {
            let id = element[keyPath: idKeyPath]
            let children = element[keyPath: childrenKeyPath]
            nodes.append(Node(id: id, element: element, depth: depth, isBranch: children != nil))
            guard let children, expanded.contains(id) else { continue }
            for child in children.reversed() {
                stack.append((child, depth + 1))
            }
        }
        return nodes
    }

    /// One row: a disclosure header for a branch, the bare label for a leaf.
    @ViewBuilder
    private func row(for node: Node) -> some View {
        if node.isBranch {
            DisclosureGroup(isExpanded: expansionBinding(for: node.id)) {
                // The children are the NEXT rows, not this row's content — see
                // the note on the type. A disclosure group with nothing inside
                // is exactly the header this wants, triangle and all.
                EmptyView()
            } label: {
                content(node.element)
            }
            .padding(.leading, node.depth * DisclosureMetrics.contentIndent)
        } else {
            // One step further in than its depth, so a leaf's label lands in
            // the same column as a sibling branch's label rather than under
            // that branch's triangle.
            content(node.element)
                .padding(.leading, (node.depth + 1) * DisclosureMetrics.contentIndent)
        }
    }

    /// A `Bool` binding onto one node's membership of ``expanded``.
    ///
    /// Built from the projected `@State` binding rather than from `self`, so it
    /// writes through the box this frame was bound to when the row's button
    /// fires — which happens well after this returns.
    private func expansionBinding(for id: ID) -> Binding<Bool> {
        let expansion = $expanded
        return Binding(
            get: { expansion.wrappedValue.contains(id) },
            set: { isOpen in
                if isOpen {
                    expansion.wrappedValue.insert(id)
                } else {
                    expansion.wrappedValue.remove(id)
                }
            })
    }

    /// A node as it appears on screen: the element, how deep it sits, and
    /// whether it has a triangle.
    ///
    /// Deliberately **not** `Equatable`. `ForEach` memoizes an `Equatable`
    /// element's row by that element, and this row's appearance also depends on
    /// its depth and on whether it is open — state the element knows nothing
    /// about — so a memo keyed on it would serve a stale triangle forever.
    private struct Node {
        let id: ID
        let element: Data.Element
        let depth: Int
        let isBranch: Bool
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
