//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LayoutPlacing.swift
//
//  The one-traversal-many-visitors foundation of "Locating things without
//  drawing them" (§5b): a container that can enumerate its children's
//  placements — child + identity + rect, computed from measurement, not
//  rendering — answers every question the framework otherwise answered by
//  drawing. Locate ("where is X?"), window ("what meets the viewport?"),
//  enumerate ("what can be focused?"), and extent ("how tall is it all?")
//  are visitors over this single enumeration, so they cannot disagree.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Placement

/// One child's resolved place within its container: the child itself, the
/// identity it will measure/render under, and its container-relative rect.
@MainActor
public struct Placement {
    /// The child, ready to measure or render further (or to recurse into,
    /// when it is itself a `LayoutPlacing` container).
    public let child: ChildView

    /// The identity the child measures/renders under — the routing address.
    public let identity: ViewIdentity

    /// Container-relative horizontal origin.
    ///
    /// Vertical stacks report `0` here: a row's aligned x-offset depends on
    /// the column's final width (alignment against the widest sibling), which
    /// is exactly the global aggregate §5j forbids deriving from all children.
    /// Vertical reveal — the shipping axis — needs only `y`/`height`.
    public let x: Int

    /// Container-relative vertical origin (below any inter-child spacing).
    public let y: Int

    /// The child's extent along the container's horizontal axis.
    public let width: Int

    /// The child's extent along the container's vertical axis.
    public let height: Int

    public init(child: ChildView, identity: ViewIdentity, x: Int, y: Int, width: Int, height: Int) {
        self.child = child
        self.identity = identity
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

// MARK: - LayoutPlacing

/// A container that can place its children without rendering them.
///
/// The signature is **seekable and bidirectional**: placements are addressed
/// by ordinal so a caller can start at an anchor and walk outward in both
/// directions rather than from child 0. (A `forEach`-with-stop shape could
/// only stop early — reaching row 49,999,999 would still cost 49,999,999
/// callbacks, and filling a viewport upward from an anchor has no direction
/// at all.)
///
/// Conformers are the framework's Tier-1 multi-child containers (the stacks,
/// `List`, `Section`, `ViewThatFits`); single-content containers forward with
/// an offset; app-level views never implement this — their `body` composes
/// containers that do.
@MainActor
public protocol LayoutPlacing {
    /// The number of placements (children) this container lays out.
    func placementCount(context: RenderContext) -> Int

    /// The placement of the child at `ordinal`, or `nil` when out of range.
    ///
    /// Geometry is computed from measurement under `proposal`; nothing is
    /// rendered and no side effects run.
    func placement(at ordinal: Int, proposal: ProposedSize, context: RenderContext) -> Placement?

    /// Routes a target identity to the ordinal of the child leading to it —
    /// `nil` when the target is not under this container ("not mine").
    ///
    /// O(1) chain inspection plus a child lookup; never measures or renders.
    func ordinal(of target: ViewIdentity, context: RenderContext) -> Int?

    /// Non-`nil` when every placement provably has exactly this extent along
    /// the container's primary axis under `proposal` (§5i): placement
    /// arithmetic, scrollbars, and viewport mapping become exact and O(1).
    func uniformExtent(proposal: ProposedSize, context: RenderContext) -> Int?
}

extension LayoutPlacing {
    /// Containers without a provable uniform extent are variable (§5i's
    /// `measured` source): estimates + the layout cache serve them.
    public func uniformExtent(proposal: ProposedSize, context: RenderContext) -> Int? { nil }
}
