//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Scene+AppearanceOverride.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Root Appearance Discovery

/// A scene that can provide a root-level ``Appearance`` override.
///
/// `RenderLoop` uses this to keep out-of-tree surfaces (status bar, app header)
/// aligned with `.appearance(...)` applied at the scene level — the appearance
/// counterpart to ``RootPaletteOverrideProvidingScene``.
///
/// Without this, a scene-level appearance would only reach the content view
/// tree: `RenderLoop` derives the frame appearance from the appearance manager
/// (F2/F3/the appearance picker), which the header and status bar read but the
/// content's own `.appearance(...)` modifier cannot reach.
@MainActor
internal protocol RootAppearanceOverrideProvidingScene: Scene {
    /// Returns the root appearance override, or `nil` to defer to the
    /// appearance manager (the built-in F2/F3/picker appearance).
    func rootAppearanceOverride() -> Appearance?
}

@MainActor
extension WindowGroup: RootAppearanceOverrideProvidingScene {
    /// A bare `WindowGroup` carries no scene-level appearance, so the appearance
    /// manager's current selection wins.
    func rootAppearanceOverride() -> Appearance? { nil }
}

// MARK: - Public Modifier

extension Scene {
    /// Sets the ``Appearance`` (border style) for this scene — its content and
    /// every out-of-tree surface (app header, status bar) alike.
    ///
    /// This is the scene-level counterpart to ``View/appearance(_:)``: a
    /// `View`-level `.appearance(...)` only reaches the content subtree, whereas
    /// the app header and status bar are rendered outside the view tree by the
    /// framework and otherwise follow the appearance manager (F2/F3/the
    /// appearance picker). Applying the appearance here routes it to all three.
    ///
    /// ```swift
    /// @main
    /// struct MyApp: App {
    ///     @State private var border: BorderStyle?
    ///     var body: some Scene {
    ///         WindowGroup { ContentView(border: $border) }
    ///             // A custom border overrides the built-in appearance app-wide;
    ///             // `nil` defers to F2/F3/the appearance picker.
    ///             .appearance(border.map {
    ///                 Appearance(id: Appearance.ID(rawValue: "custom"), borderStyle: $0)
    ///             })
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter appearance: The appearance to apply app-wide, or `nil` to
    ///   leave the appearance manager (F2/F3/the appearance picker) in charge.
    /// - Returns: A scene that applies the appearance.
    public func appearance(_ appearance: Appearance?) -> some Scene {
        _AppearanceScene(content: self, appearance: appearance)
    }
}

// MARK: - Wrapper Scene

/// Framework-internal scene wrapper that records a root ``Appearance`` override
/// on its content. `RenderLoop` reads it via
/// ``RootAppearanceOverrideProvidingScene`` and installs it into the environment
/// for the whole frame, so it reaches the content view tree and the out-of-tree
/// surfaces alike.
internal struct _AppearanceScene<Content: Scene>: Scene {  // swiftlint:disable:this type_name
    let content: Content
    let appearance: Appearance?
}

extension _AppearanceScene: RootAppearanceOverrideProvidingScene {
    /// An appearance closer to the content wins — one applied to an inner scene —
    /// mirroring how `.palette(...)` composes (innermost wins) and how SwiftUI
    /// environment modifiers resolve. A `nil` here means "no opinion", so an
    /// outer `.appearance(...)` still shows through.
    func rootAppearanceOverride() -> Appearance? {
        if let inner = content as? any RootAppearanceOverrideProvidingScene,
            let innerAppearance = inner.rootAppearanceOverride()
        {
            return innerAppearance
        }
        return appearance
    }
}

extension _AppearanceScene: RootPaletteOverrideProvidingScene {
    /// Pass-through: forward any wrapped scene's palette override so
    /// `.appearance(...)` composes with `.palette(...)` in either order.
    func rootPaletteOverride() -> (any Palette)? {
        (content as? any RootPaletteOverrideProvidingScene)?.rootPaletteOverride()
    }
}

extension _AppearanceScene: SceneRenderable {
    /// The appearance is applied by `RenderLoop` through
    /// ``rootAppearanceOverride()``; rendering simply forwards to the wrapped
    /// scene.
    func renderScene(context: RenderContext) -> FrameBuffer {
        if let renderable = content as? SceneRenderable {
            return renderable.renderScene(context: context)
        }
        return FrameBuffer()
    }
}

extension _AppearanceScene: MouseSupportProvidingScene {
    /// Pass-through: forward the wrapped scene's mouse support so
    /// `.appearance(...)` composes with `.mouseSupport(...)` in either order.
    /// Returns `nil` (no opinion) when nothing inside specifies one, so wrapping
    /// a `.mouseSupport(...)` scene in `.appearance(...)` does not shadow it.
    func resolvedMouseSupport() -> MouseSupport? {
        (content as? MouseSupportProvidingScene)?.resolvedMouseSupport()
    }
}
