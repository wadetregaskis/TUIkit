//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TUIkit.swift
//
//  Created by LAYERED.work
//  License: MIT
//  TUIkit enables creating TUI applications with a declarative,
//  SwiftUI-like syntax - without ncurses or other low-level libraries.
//

import Foundation

/// True iff `TUIKIT_DEBUG_FOCUS=1` was set in the environment at
/// process start.
///
/// Read once at module-load time; flipping the variable mid-run has
/// no effect. Used to gate the focus / mouse-dispatch / text-field
/// diagnostic logging across the framework. The cached boolean
/// means each call site costs a single branch in the hot path.
internal let isFocusDebugEnabled: Bool =
    ProcessInfo.processInfo.environment["TUIKIT_DEBUG_FOCUS"] == "1"

/// Appends a one-line, timestamped diagnostic to
/// `/tmp/tuikit-debug.log` when `TUIKIT_DEBUG_FOCUS=1`.
///
/// When the flag is unset (the common case) the `message`
/// autoclosure is not evaluated and the function returns
/// immediately, so leaving call sites in place permanently is
/// effectively free.
///
/// Used to diagnose issues that only reproduce in the running
/// example app — typically "the click reached the dispatcher but no
/// region matched", "the keypress dispatched but to the wrong focus
/// handler", or "the binding wrote, but to the wrong @State".
///
/// > Note: Internal diagnostic helper, not part of the public API.
internal func debugFocusLog(_ message: @autoclosure () -> String) {
    guard isFocusDebugEnabled else { return }
    let stamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(stamp)] \(message())\n"
    if let handle = FileHandle(forWritingAtPath: "/tmp/tuikit-debug.log") {
        defer { try? handle.close() }
        try? handle.seekToEnd()
        if let data = line.data(using: .utf8) { try? handle.write(contentsOf: data) }
    } else {
        try? line.write(toFile: "/tmp/tuikit-debug.log", atomically: false, encoding: .utf8)
    }
}

/// The current version of TUIkit.
///
/// Read from `Sources/TUIkit/VERSION` (bundled as a resource).
/// Update the `VERSION` file to change the version number.
public let tuiKitVersion: String = {
    guard let url = Bundle.module.url(forResource: "VERSION", withExtension: nil),
        let content = try? String(contentsOf: url, encoding: .utf8)
    else {
        return "unknown"
    }
    return content.trimmingCharacters(in: .whitespacesAndNewlines)
}()

/// Executes a view closure and renders it once.
///
/// This is useful for simple CLI tools that don't need a full App.
///
/// # Example
///
/// ```swift
/// renderOnce {
///     VStack {
///         Text("Hello, TUIkit!")
///             .bold()
///             .foregroundStyle(.cyan)
///         Divider()
///         Text("Version \(tuiKitVersion)")
///             .dim()
///     }
/// }
/// ```
///
/// - Parameter content: A ViewBuilder closure that defines the view to render.
@MainActor
public func renderOnce<Content: View>(@ViewBuilder content: () -> Content) {
    let view = content()
    let renderer = ViewRenderer()
    renderer.render(view)
}
