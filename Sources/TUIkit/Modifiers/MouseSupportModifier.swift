//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MouseSupportModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Mouse Support Modifier

/// A view modifier that overrides the scene-level ``MouseSupport``
/// configuration for the entirety of the current render pass.
///
/// Unlike ``Scene/mouseSupport(_:)`` which sets the *base*
/// configuration at app start, this modifier replaces that base
/// dynamically — the latest `.mouseSupport(...)` evaluated during a
/// render pass wins. Useful for temporarily disabling mouse capture
/// so the user can use their terminal's native text-selection
/// behaviour, or for boosting the configuration when a particular
/// view temporarily wants hover events.
///
/// ## Example
///
/// ```swift
/// @State var selectingText = false
///
/// var body: some View {
///     ContentView()
///         .mouseSupport(selectingText ? .disabled : .standard)
///         .onKeyPress(.character("s"), modifiers: .command) {
///             selectingText.toggle()
///             return true
///         }
/// }
/// ```
public struct MouseSupportModifier<Content: View>: View {
    /// The content view.
    let content: Content

    /// The mouse-support configuration to install.
    let support: MouseSupport

    public var body: Never {
        fatalError("MouseSupportModifier renders via Renderable")
    }
}

// MARK: - Renderable

extension MouseSupportModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Posting the override needs to happen *during* the render
        // pass so the AppRunner picks it up when computing the
        // effective configuration after rendering completes. Measure
        // passes are silent — they shouldn't alter terminal state.
        if !context.isMeasuring,
            let dispatcher = context.environment.mouseEventDispatcher
        {
            dispatcher.setConfigOverride(support)
        }
        return TUIkit.renderToBuffer(content, context: context)
    }
}

// MARK: - View Modifier

extension View {
    /// Overrides the scene-level ``MouseSupport`` configuration for
    /// this view subtree.
    ///
    /// Unlike the scene-level modifier of the same name, this view
    /// modifier applies *per render pass* — toggle the argument
    /// reactively to turn mouse capture on and off at runtime
    /// (e.g. to temporarily yield to the terminal's native text
    /// selection).
    ///
    /// The latest `.mouseSupport(...)` evaluated during a render pass
    /// takes effect (innermost wins). Per-frame feature requests
    /// from other modifiers (e.g. an `onHover` view wanting motion)
    /// are still unioned on top.
    ///
    /// - Parameter support: The desired mouse-support configuration.
    /// - Returns: A view that applies the configuration during render.
    public func mouseSupport(_ support: MouseSupport) -> some View {
        MouseSupportModifier(content: self, support: support)
    }
}
