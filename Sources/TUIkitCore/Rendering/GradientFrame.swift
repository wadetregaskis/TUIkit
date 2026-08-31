//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GradientFrame.swift
//
//  Where a leaf sits inside the rectangle a gradient is being resolved over.
//
//  Created by Wade Tregaskis
//  License: MIT

/// The rectangle a `.gradientExtent(.subtree)` gradient runs across, and where
/// the view being rendered sits inside it.
///
/// Carried down the render context — not through the environment dictionary —
/// and nudged by every container that places children, so a leaf can ask "where
/// am I in the thing the ramp spans?" without knowing anything about its
/// ancestors.
///
/// It is a *context* field rather than an environment value for the reason
/// `RenderContext` mirrors `renderCache` and `stateStorage` out of the
/// dictionary: this is read on the leaf path, and `EnvironmentValues` is an
/// `[ObjectIdentifier: Any]` whose getter measured 4.5% and 5.2% of CPU for
/// those two services. A stored `Optional` costs a nil check.
public struct GradientFrame: Equatable, Sendable {
    /// Where the view being rendered starts, in the extent's cells.
    public var originX: Int
    public var originY: Int

    /// The extent itself, in cells — what `t` runs from 0 to 1 across.
    public var width: Int
    public var height: Int

    /// Whether ``width`` and ``height`` are still a stand-in.
    ///
    /// `.gradientExtent(.subtree)` needs the subtree's size before the subtree
    /// renders, and measuring for it costs a whole extra measure pass —
    /// measured at 96 µs of a 336 µs frame on a forty-row list, which is most
    /// of what made the feature slower than doing it by hand. But the first
    /// container that places children has just worked the same size out for its
    /// own layout, so it fills this in for nothing and clears the flag. Until
    /// one does, the space the modifier was given stands in.
    public var isProvisional: Bool

    public init(
        originX: Int = 0, originY: Int = 0, width: Int, height: Int,
        isProvisional: Bool = false
    ) {
        self.originX = originX
        self.originY = originY
        self.width = width
        self.height = height
        self.isProvisional = isProvisional
    }

    /// This frame with the extent the enclosing container just measured, if it
    /// was still a stand-in.
    public func resolvingExtent(width: Int, height: Int) -> Self {
        guard isProvisional else { return self }
        var settled = self
        settled.width = max(1, width)
        settled.height = max(1, height)
        settled.isProvisional = false
        return settled
    }

    /// This frame as seen by a child placed at `(x, y)` within the current view.
    public func offset(byX x: Int, y: Int) -> Self {
        var moved = self
        moved.originX += x
        moved.originY += y
        return moved
    }
}
