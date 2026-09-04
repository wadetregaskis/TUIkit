//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusManagerEnvironment.swift
//
//  How a render finds the focus manager. Split out of `Focus.swift` only for
//  its length; the key is private to this file, which is what lets it move at
//  all — every other extension of `FocusManager` reads state that is private
//  to the manager's own file.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Focus Manager Environment Key

/// Environment key for the focus manager.
private struct FocusManagerKey: EnvironmentKey {
    // No shared default instance — consistent with the other runtime services
    // (lifecycle, keyEventDispatcher, mouseEventDispatcher are all nil-default
    // Optionals). A single shared default would let every context that doesn't
    // install its own focus manager register into the SAME manager, leaking
    // focus state across isolated renders (and across parallel test contexts).
    // The real app installs one via `RenderLoop.makeRenderContext`; a nil manager
    // means "no focus system", so controls render unfocused and nothing
    // auto-focuses.
    static let defaultValue: FocusManager? = nil
}

extension EnvironmentValues {
    /// The focus manager for managing keyboard focus, or `nil` when no focus
    /// system is installed (an isolated/measure render, a dimmed backdrop, or a
    /// test that doesn't exercise focus). The live app always installs one.
    ///
    /// Access via `context.environment.focusManager` in `renderToBuffer(context:)`.
    public var focusManager: FocusManager? {
        get { self[FocusManagerKey.self] }
        set { self[FocusManagerKey.self] = newValue }
    }
}
