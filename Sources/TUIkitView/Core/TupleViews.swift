//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TupleViews.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

/// A view that contains multiple child views packed via a parameter pack.
///
/// `TupleView` replaces the previous `TupleView2` through `TupleView10`
/// types with a single generic struct using Swift Parameter Packs (SE-0393).
/// This removes the 10-child limit and eliminates ~400 lines of boilerplate.
///
/// `TupleView` is created automatically by `ViewBuilder` when multiple
/// views appear in a `@ViewBuilder` closure.
///
/// - Important: This is framework infrastructure. Created automatically by
///   `@ViewBuilder`. Do not instantiate directly.
public struct TupleView<each V: View>: View {
    /// The packed child views.
    public let children: (repeat each V)

    /// Creates a tuple view from a parameter pack of child views.
    ///
    /// - Parameter children: The child views.
    init(_ children: repeat each V) {
        self.children = (repeat each children)
    }

    public var body: Never {
        fatalError("TupleView renders its children directly")
    }
}

// MARK: - Equatable Conformance

// A main-actor-isolated conformance (SE-0470), NOT the `@preconcurrency
// Equatable` every other view spells. Both run `==` on the main actor; the
// isolated one is also refused, statically, outside it, and everything here
// still compiles. The reason is a compiler bug: swift.org's Swift 6.2.4 is an
// assertions build, and SILGen aborts on a `@preconcurrency` conformance of a
// type that stores a parameter pack (`Assertion failed: (isPreconcurrency),
// function emitProtocolWitness`). Xcode's 6.2.4 compiles either spelling. See
// Tools/CompilerBugs/README.md, section 3.
extension TupleView: @MainActor Equatable where repeat each V: Equatable {
    public static func == (lhs: TupleView, rhs: TupleView) -> Bool {
        func isEqual<T: Equatable>(_ left: T, _ right: T) -> Bool { left == right }
        var result = true
        repeat result = result && isEqual(each lhs.children, each rhs.children)
        return result
    }
}

// MARK: - TupleView Rendering + ChildInfoProvider

extension TupleView: Renderable, ChildInfoProvider {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        FrameBuffer(verticallyStacking: childInfos(context: context).compactMap(\.buffer))
    }

    public func childInfos(context: RenderContext) -> [ChildInfo] {
        var infos: [ChildInfo] = []
        repeat Self.appendChildInfos(
            from: each children,
            into: &infos,
            context: context
        )
        return infos
    }

    /// Appends one or more `ChildInfo` entries for `child`.
    ///
    /// When `child` is itself a `ChildInfoProvider` (a nested
    /// `TupleView`, a `Group`, a `Section`), its `childInfos` are
    /// spliced in so the surrounding container sees the children
    /// as individual siblings — rather than treating the whole
    /// provider as one opaque element.
    ///
    /// Note that `ForEach` is *not* a `ChildInfoProvider` — it
    /// implements only the two-pass `ChildViewProvider` — so any
    /// remaining consumer of this legacy single-pass path pushes
    /// a `ForEach` child through the universal `renderToBuffer`,
    /// where (body: Never, not Renderable) it silently yields an
    /// empty buffer. The stacks and `ZStack` all resolve children
    /// through `resolveChildViews` for exactly that reason; this
    /// path remains only for `List`/`Section` row extraction,
    /// which handles `ForEach` separately.
    @MainActor
    private static func appendChildInfos<C: View>(
        from child: C,
        into infos: inout [ChildInfo],
        context: RenderContext
    ) {
        if let provider = child as? ChildInfoProvider {
            infos.append(contentsOf: provider.childInfos(context: context))
        } else {
            infos.append(
                makeChildInfo(
                    for: child,
                    context: context.withChildIdentity(
                        type: type(of: child), index: infos.count)
                )
            )
        }
    }
}

// MARK: - TupleView Two-Pass Layout Support

extension TupleView: ChildViewProvider {
    public func childViews(context: RenderContext) -> [ChildView] {
        var views: [ChildView] = []
        var slot = 0
        repeat Self.appendChildViews(
            from: each children,
            into: &views,
            slot: &slot,
            context: context
        )
        return views
    }

    /// Appends one or more `ChildView` entries for `child`. See
    /// the matching note on `appendChildInfos` — this exists for
    /// the same reason on the two-pass layout side.
    ///
    /// `slot` is the element's STATIC position in the tuple — one per pack
    /// element regardless of how many children it flattens to — which is what
    /// namespaces keyed rows spliced from sibling providers. See
    /// `ChildView.spliced(fromSlot:under:branched:)`.
    @MainActor
    private static func appendChildViews<C: View>(
        from child: C,
        into views: inout [ChildView],
        slot: inout Int,
        context: RenderContext
    ) {
        defer { slot += 1 }
        if let provider = child as? ChildViewProvider {
            // A provider gets an identity step of its OWN, at its static slot,
            // and its children are indexed WITHIN it — `/ForEach.0/Text[2]`,
            // not `/Text.2`.
            //
            // What that buys is the thing the flattened index could not give:
            // a sibling's identity no longer depends on how many children the
            // providers before it happened to produce. Keyed rows were already
            // safe (`"\(slot)#\(key)"` is namespaced by the static slot and
            // stable across insertions), but everything positional took
            // `views.count`, so adding one row to a `ForEach` moved the
            // `Button` after it from `/Button.3` to `/Button.4` — a different
            // identity, which means a reset `@State`, a new focus id, a
            // re-fired `onAppear` and a dropped buffer. A form under a list
            // lost what you had typed into it when the list grew.
            //
            // Indexing within the provider is also what makes the static slot
            // usable below. The two namespaces have to be disjoint: with the
            // children still flattened, giving the direct child its slot would
            // have aliased it onto one of them — `VStack { Group { Counter();
            // Counter() }; Counter() }` puts the last at slot 1 and the Group's
            // second child at index 1, same type, same parent, one `@State`
            // box between them.
            //
            // What a nested provider's level already worked out is KEPT, not
            // replaced by this one. Only that level knew what told its
            // children apart — an inner tuple slot, an inner provider's step, a
            // branch — and nothing handed up to this level can rebuild it. This
            // used to re-address everything from its own slot, on the belief
            // that each level re-enumerates its children 0..<n; it does not (a
            // positional child keeps its INNER index, below), so two levels
            // down distinct children met: `Group { if a { Counter() }; if b {
            // Counter() } }` beside a sibling put both counters on one
            // `@State` box, and `Group { ForEach(0..<2); ForEach(0..<2) }` put
            // both loops' rows on the same two identities, so the row memo drew
            // the first loop twice. See `ChildView.spliced(fromSlot:under:branched:)`.
            //
            // The provider builds its children in its OWN scope, not the
            // stack's. It has to: `Optional.childViews` asks the departure
            // store whether anything is still leaving `directlyUnder:
            // context.identity`, and the answer has to be asked at the address
            // the present view actually rendered at — which is now under this
            // step, not beside it. Handing it the stack's context instead makes
            // every removal transition inside an `if` stop playing.
            var providerContext = context.withChildIdentity(erasedType: C.self, index: slot)
            // An `if`/`else` offers one branch or the other from the same slot,
            // and the two must not share an identity — see
            // ``ChildViewProvider/identityBranchLabel``. The same step
            // `ConditionalView.renderToBuffer` applies, so the flattened path
            // and the whole-view path agree on where a branch's children live.
            let branch = provider.identityBranchLabel
            if let branch {
                providerContext = providerContext.withBranchIdentity(branch)
            }
            for entry in provider.childViews(context: providerContext) {
                // A KEYED row needs none of this and must not pay for it.
                // `"\(slot)#\(key)"` is already unique across sibling
                // providers and already follows its element across
                // insertions, so it was never the half that broke — and it
                // is the hot half. Putting `ForEach` rows under an extra
                // identity step deepened every chain in the tree that
                // matters most, and identity chains are hashed and walked
                // on the measure and state paths: it measured **menus
                // +6.2%**, against +2.6% once the rows were left where they
                // were. That is the row nothing below has namespaced and no
                // branch separates, here or one provider further in (`Group {
                // if … else … }`, whose conditional marked its rows). A row with
                // either takes the step, since a flat key can carry neither, and
                // only nested shapes make one.
                //
                // A POSITIONAL child is the half that broke, and it keeps
                // the index the level below already gave it — its static
                // slot there — rather than taking the enumeration position
                // here. Re-indexing to the enumeration would reintroduce
                // the bug one level down: in `Group { ForEach(rows); Text }`
                // the `Text` would count the rows before it and move every
                // time the collection grew.
                views.append(
                    entry.spliced(
                        fromSlot: slot, under: providerContext.identity, branched: branch != nil))
            }
        } else {
            // The STATIC position, not the flattened one — see above.
            views.append(ChildView(child, childIndex: slot))
        }
    }
}
