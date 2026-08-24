//  🖥️ TUIKit — Terminal UI Kit for Swift
//  AppHeaderState.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - App Header State

/// Manages the app header state for the running application.
///
/// `AppHeaderState` stores the rendered content buffer that views
/// provide via the `.appHeader { ... }` modifier. The `RenderLoop`
/// reads this buffer each frame and renders it at the top of the terminal.
///
/// When no content is set, the header is hidden and no vertical space
/// is reserved.
///
/// # Usage
///
/// Views set the header content via the `.appHeader` modifier:
///
/// ```swift
/// VStack {
///     Text("Main content")
/// }
/// .appHeader {
///     HStack {
///         Text("My App").bold()
///         Spacer()
///         Text("v1.0")
///     }
/// }
/// ```
final class AppHeaderState: @unchecked Sendable {
    /// The rendered content buffer for the current frame.
    ///
    /// Set by ``AppHeaderModifier`` during rendering. Reset to `nil`
    /// at the start of each render pass by `RenderLoop`.
    var contentBuffer: FrameBuffer?

    /// The height from the previous render pass, used as an estimate
    /// for layout calculations before the current pass populates the buffer.
    ///
    /// Defaults to 3 (typical header: 1 content line inside a box's two rules)
    /// to avoid content shifting on the first frame when a header is present.
    /// Apps without a header will have this reset to 0 after the first frame.
    private var previousHeight: Int = 3

    /// Whether the header has content to display.
    var hasContent: Bool {
        guard let buffer = contentBuffer else { return false }
        return !buffer.isEmpty
    }

    /// The width the header will be DRAWN at — the whole terminal.
    ///
    /// Set by `RenderLoop` before the view tree renders, and read by
    /// ``AppHeaderModifier`` when it lays the header content out. The two have
    /// to agree, and they cannot both read it from their own context: the
    /// modifier is applied inside the view tree, where padding on the way down
    /// has already narrowed `availableWidth`, while the header is drawn across
    /// the terminal. Laying out at the narrower figure and padding to the wider
    /// one leaves a trailing gap the size of that padding.
    ///
    /// `nil` outside a run loop, where the modifier falls back to its own
    /// context — the best available answer when nobody has drawn a header yet.
    var renderWidth: Int?

    /// How the header frames itself against the page.
    ///
    /// Defaults to ``ChromeStyle/bordered`` — a box, like a container view,
    /// matching the status bar's. Set both at once with
    /// ``Scene/chromeStyle(_:)``.
    var style: ChromeStyle = .bordered

    /// The height of the header in terminal lines: its content plus whatever
    /// chrome the style draws around it, or 0 when no content is set.
    var height: Int {
        guard hasContent else { return 0 }
        return style.barHeight(contentRows: contentBuffer?.height ?? 0)
    }

    /// The estimated height for the current frame, based on the previous
    /// render pass. Available before the view tree is rendered.
    var estimatedHeight: Int {
        previousHeight
    }
}

// MARK: - Render Pass

extension AppHeaderState {
    /// Clears the content buffer at the start of each render pass.
    ///
    /// Saves the current height as ``estimatedHeight`` before clearing,
    /// so `RenderLoop` can reserve the correct space before the
    /// ``AppHeaderModifier`` populates the new buffer.
    ///
    /// Called by `RenderLoop` before rendering the view tree.
    /// If no view sets `.appHeader { ... }` during the pass,
    /// the header remains hidden.
    func beginRenderPass() {
        previousHeight = height
        contentBuffer = nil
    }
}

// MARK: - Environment Key

/// Environment key for the app header state.
private struct AppHeaderKey: EnvironmentKey {
    static let defaultValue: AppHeaderState? = nil
}

extension EnvironmentValues {
    /// The app header state.
    ///
    /// Used internally by ``AppHeaderModifier`` to store the header content
    /// and by `RenderLoop` to render it at the top of the terminal.
    ///
    /// `nil` outside a running application. These are the app's own objects,
    /// created by `AppRunner` and published by `RenderLoop.buildEnvironment()`
    /// — so a bare `EnvironmentValues()` (a headless render, a test) has none,
    /// which is the truth. It used to hand out a SHARED instance instead, and
    /// every such render mutated the same object: two tests rendering sheets in
    /// parallel both registered their ESC item into it and read each other's
    /// back. The convention here is the one `focusManager` and
    /// `keyEventDispatcher` already follow — a runtime service is Optional, and
    /// absent means absent.
    var appHeader: AppHeaderState? {
        get { self[AppHeaderKey.self] }
        set { self[AppHeaderKey.self] = newValue }
    }
}
