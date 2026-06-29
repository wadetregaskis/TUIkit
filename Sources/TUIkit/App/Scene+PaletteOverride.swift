//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Scene+PaletteOverride.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Root Palette Discovery

/// A scene that can provide a root-level palette override.
///
/// `RenderLoop` uses this to keep out-of-tree surfaces (status bar, app header)
/// aligned with `.palette(...)` applied at the root view level.
@MainActor
internal protocol RootPaletteOverrideProvidingScene: Scene {
    /// Returns the root palette override, if present.
    func rootPaletteOverride() -> (any Palette)?
}

/// Type-erased access to `EnvironmentModifier` internals.
///
/// This is intentionally limited to root modifier chain discovery.
@MainActor
private protocol AnyEnvironmentModifierNode {
    var anyEnvironmentKeyPath: AnyKeyPath { get }
    var anyEnvironmentValue: Any { get }
    var anyEnvironmentContent: Any { get }
}

@MainActor
extension EnvironmentModifier: AnyEnvironmentModifierNode {
    fileprivate var anyEnvironmentKeyPath: AnyKeyPath { keyPath }
    fileprivate var anyEnvironmentValue: Any { value }
    fileprivate var anyEnvironmentContent: Any { content }
}

@MainActor
extension WindowGroup: RootPaletteOverrideProvidingScene {
    func rootPaletteOverride() -> (any Palette)? {
        var current: Any = content

        while let modifier = current as? any AnyEnvironmentModifierNode {
            if modifier.anyEnvironmentKeyPath == \EnvironmentValues.palette,
                let palette = modifier.anyEnvironmentValue as? any Palette
            {
                return palette
            }
            current = modifier.anyEnvironmentContent
        }

        return nil
    }
}

// MARK: - Public Modifier

extension Scene {
    /// Sets the color palette for this scene — its content and every
    /// out-of-tree surface (app header, status bar).
    ///
    /// This is the scene-level counterpart to ``View/palette(_:)``: it lets the
    /// palette be written directly on a `WindowGroup`, matching SwiftUI's habit
    /// of theming at the scene level.
    ///
    /// ```swift
    /// @main
    /// struct MyApp: App {
    ///     var body: some Scene {
    ///         WindowGroup {
    ///             ContentView()
    ///         }
    ///         .palette(SystemPalette(.green))  // Classic green terminal
    ///     }
    /// }
    /// ```
    ///
    /// Applying `.palette(_:)` to the root *view* inside the `WindowGroup`
    /// remains equivalent and is honoured identically (see
    /// ``RootPaletteOverrideProvidingScene``).
    ///
    /// - Parameter palette: The palette to apply.
    /// - Returns: A scene that applies the palette.
    public func palette(_ palette: any Palette) -> some Scene {
        _PaletteScene(content: self, palette: palette)
    }
}

// MARK: - Wrapper Scene

/// Framework-internal scene wrapper that records a root ``Palette`` override on
/// its content. `RenderLoop` reads it via ``RootPaletteOverrideProvidingScene``
/// and installs it into the environment for the whole frame, so it reaches the
/// content view tree and the out-of-tree surfaces alike.
internal struct _PaletteScene<Content: Scene>: Scene {  // swiftlint:disable:this type_name
    let content: Content
    let palette: any Palette
}

extension _PaletteScene: RootPaletteOverrideProvidingScene {
    /// A palette closer to the content wins — one applied to an inner scene, or
    /// to the root view inside `WindowGroup` — mirroring how `.mouseSupport`
    /// composes (innermost wins) and how SwiftUI environment modifiers resolve.
    func rootPaletteOverride() -> (any Palette)? {
        if let inner = content as? any RootPaletteOverrideProvidingScene,
            let innerPalette = inner.rootPaletteOverride()
        {
            return innerPalette
        }
        return palette
    }
}

extension _PaletteScene: RootAppearanceOverrideProvidingScene {
    /// Pass-through: forward any wrapped scene's appearance override so
    /// `.palette(...)` composes with `.appearance(...)` in either order.
    func rootAppearanceOverride() -> Appearance? {
        (content as? any RootAppearanceOverrideProvidingScene)?.rootAppearanceOverride()
    }
}

extension _PaletteScene: SceneRenderable {
    /// The palette is applied by `RenderLoop` through ``rootPaletteOverride()``;
    /// rendering simply forwards to the wrapped scene.
    func renderScene(context: RenderContext) -> FrameBuffer {
        if let renderable = content as? SceneRenderable {
            return renderable.renderScene(context: context)
        }
        return FrameBuffer()
    }
}

extension _PaletteScene: MouseSupportProvidingScene {
    /// Pass-through: forward the wrapped scene's mouse support so `.palette(...)`
    /// composes with `.mouseSupport(...)` in either order. Returns `nil` (no
    /// opinion) when nothing inside specifies one — crucially, so wrapping a
    /// `.mouseSupport(...)` scene in `.palette(...)` does not shadow it with a
    /// default.
    func resolvedMouseSupport() -> MouseSupport? {
        (content as? MouseSupportProvidingScene)?.resolvedMouseSupport()
    }
}
