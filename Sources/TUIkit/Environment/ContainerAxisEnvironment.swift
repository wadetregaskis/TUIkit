//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContainerAxisEnvironment.swift
//
//  Which way the enclosing stack lays its children out, published so that a
//  child whose appearance depends on it — `Divider`, today — can ask. SwiftUI
//  carries the same information internally, which is how its `Divider`
//  manages to be a horizontal rule in a VStack and a vertical one in an HStack
//  without the caller saying so.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitView

private struct ContainerAxisKey: EnvironmentKey {
    static let defaultValue: Axis? = nil
}

extension EnvironmentValues {
    /// The axis of the stack laying this view out, or `nil` outside one.
    ///
    /// Set by the stack cores on the context they hand their children, and
    /// read by ``Divider`` to choose its orientation. The value is constant
    /// for a given call site — an `HStack` always publishes `.horizontal` —
    /// so writing it directly on a child context cannot leave a memoized
    /// subtree holding a stale one, which is the hazard that makes
    /// `environment(_:_:)` the right tool for values that change.
    ///
    /// Deliberately not public: it describes an implementation relationship
    /// between a container and its children, and SwiftUI does not expose its
    /// equivalent either. A view that wants to know its own axis should be
    /// told by its caller.
    var containerAxis: Axis? {
        get { self[ContainerAxisKey.self] }
        set { self[ContainerAxisKey.self] = newValue }
    }
}

extension RenderContext {
    /// This context with ``EnvironmentValues/containerAxis`` set, for a stack
    /// to hand its children.
    ///
    /// Written directly rather than through `environment(_:_:)` because the
    /// value is a property of the call site, not of any state: an `HStack` is
    /// horizontal on every frame it ever renders, so no memoized subtree can
    /// be holding a value that has since changed.
    func publishingContainerAxis(_ axis: Axis) -> Self {
        var copy = self
        copy.environment.containerAxis = axis
        return copy
    }
}
