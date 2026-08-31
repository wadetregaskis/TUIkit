//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ShapeStyleAsView.swift
//
//  A style used where a view is expected fills the space it is given.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling
import TUIkitView

// MARK: - The styles that are also views

// `Color: View` is NOT here. It has to be declared in `TUIkitView`, the module
// that owns `View`, or a `Color` in a `@ViewBuilder` pack beside a generic view
// segfaults the debug runtime — a toolchain bug, not a design one. See
// `TUIkitView/Core/ColorAsView.swift`, which carries the whole story, and §14
// of `Documentation/Gradients where a colour is accepted.md`.
//
// The gradients are unaffected: they are this module's own types, so their
// conformances are already in the module that declares them.

extension LinearGradient: View {
    /// A gradient used as a view fills the space it is offered, exactly as a
    /// ``Color`` does — the ramp then resolves over that rectangle.
    public var body: some View {
        _StyleFillBlock().background(self)
    }
}

extension RadialGradient: View {
    /// See ``LinearGradient/body``.
    public var body: some View {
        _StyleFillBlock().background(self)
    }
}

extension EllipticalGradient: View {
    /// See ``LinearGradient/body``.
    public var body: some View {
        _StyleFillBlock().background(self)
    }
}

extension AngularGradient: View {
    /// See ``LinearGradient/body``.
    public var body: some View {
        _StyleFillBlock().background(self)
    }
}
