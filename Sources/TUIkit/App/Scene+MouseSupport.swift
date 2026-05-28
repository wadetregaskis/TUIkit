//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Scene+MouseSupport.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Public Modifier

extension Scene {
    /// Configures which kinds of mouse interactions the app will
    /// receive from the terminal.
    ///
    /// See ``MouseSupport`` for details on each feature and the
    /// trade-off with native terminal text selection.
    ///
    /// ## Example
    ///
    /// ```swift
    /// @main
    /// struct MyApp: App {
    ///     var body: some Scene {
    ///         WindowGroup {
    ///             ContentView()
    ///         }
    ///         .mouseSupport(.full)  // enable hover effects too
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter support: The desired mouse support configuration.
    /// - Returns: A scene that applies the configuration.
    public func mouseSupport(_ support: MouseSupport) -> some Scene {
        _MouseSupportScene(content: self, support: support)
    }
}

// MARK: - Wrapper Scene

/// Framework-internal scene wrapper that records a ``MouseSupport``
/// configuration on its content.
internal struct _MouseSupportScene<Content: Scene>: Scene {  // swiftlint:disable:this type_name
    let content: Content
    let support: MouseSupport
}

/// A scene that can report its requested ``MouseSupport``
/// configuration. `RenderLoop` queries this to decide which terminal
/// tracking mode to apply each frame.
@MainActor
internal protocol MouseSupportProvidingScene: Scene {
    func resolvedMouseSupport() -> MouseSupport
}

extension _MouseSupportScene: MouseSupportProvidingScene {
    /// Inner `.mouseSupport` calls shadow outer ones — the closest
    /// (innermost) modifier to the content wins, mirroring how
    /// SwiftUI environment-style modifiers compose.
    func resolvedMouseSupport() -> MouseSupport {
        if let inner = content as? MouseSupportProvidingScene {
            return inner.resolvedMouseSupport()
        }
        return support
    }
}

// MARK: - SceneRenderable forwarding

extension _MouseSupportScene: SceneRenderable {
    func renderScene(context: RenderContext) -> FrameBuffer {
        // Forward rendering to the wrapped content. The mouse support
        // configuration is metadata that's extracted by the AppRunner
        // via ``resolvedMouseSupport()`` — it doesn't affect what
        // gets drawn.
        if let renderable = content as? SceneRenderable {
            return renderable.renderScene(context: context)
        }
        return FrameBuffer()
    }
}

// MARK: - Palette Override Forwarding

extension _MouseSupportScene: RootPaletteOverrideProvidingScene {
    /// Forward the palette-override lookup to the wrapped scene so
    /// `.mouseSupport(...)` can be composed with `.palette(...)` in
    /// either order without losing either.
    func rootPaletteOverride() -> (any Palette)? {
        if let inner = content as? any RootPaletteOverrideProvidingScene {
            return inner.rootPaletteOverride()
        }
        return nil
    }
}
