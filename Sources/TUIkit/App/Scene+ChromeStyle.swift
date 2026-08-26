//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Scene+ChromeStyle.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Root Chrome-Style Discovery

/// A scene that can state how the app header and status bar frame themselves.
///
/// Both bars are rendered OUTSIDE the view tree by `RenderLoop`, and — unlike
/// the appearance, which only has to reach the render — their style also
/// decides how many rows the page has to give up. `RenderLoop` therefore reads
/// this at the top of the frame, before it reserves anything.
@MainActor
internal protocol RootChromeStyleProvidingScene: Scene {
    /// The header's and the status bar's styles, or `nil` for either to leave
    /// that bar as it is.
    func rootChromeStyle() -> (appHeader: ChromeStyle?, statusBar: ChromeStyle?)
}

@MainActor
extension WindowGroup: RootChromeStyleProvidingScene {
    /// A bare `WindowGroup` states nothing, so both bars keep their defaults.
    func rootChromeStyle() -> (appHeader: ChromeStyle?, statusBar: ChromeStyle?) { (nil, nil) }
}

// MARK: - Public Modifiers

extension Scene {
    /// Sets how BOTH framing bars — the app header and the status bar — separate
    /// themselves from the page.
    ///
    /// The one-line spelling, and the one to reach for: a boxed footer under a
    /// ruled header reads as a mistake, so the styles want to move together
    /// unless a mismatch is deliberate.
    ///
    /// ```swift
    /// WindowGroup { ContentView() }
    ///     .chromeStyle(.bordered)
    /// ```
    ///
    /// - Parameter style: The style both bars adopt.
    public func chromeStyle(_ style: ChromeStyle) -> some Scene {
        _ChromeStyleScene(content: self, appHeaderStyle: style, statusBarStyle: style)
    }

    /// Sets the two framing bars' styles independently.
    ///
    /// The deliberate-mismatch spelling — a compact header over a bordered
    /// status bar, say, when the page's own top edge is chrome enough.
    ///
    /// ```swift
    /// WindowGroup { ContentView() }
    ///     .chromeStyle(appHeader: .compact, statusBar: .bordered)
    /// ```
    ///
    /// - Parameters:
    ///   - appHeader: The app header's style.
    ///   - statusBar: The status bar's style.
    public func chromeStyle(appHeader: ChromeStyle, statusBar: ChromeStyle) -> some Scene {
        _ChromeStyleScene(content: self, appHeaderStyle: appHeader, statusBarStyle: statusBar)
    }
}

// MARK: - Wrapper Scene

/// Framework-internal scene wrapper recording the chrome styles for the frame.
/// `RenderLoop` reads it via ``RootChromeStyleProvidingScene``.
internal struct _ChromeStyleScene<Content: Scene>: Scene {
    let content: Content
    let appHeaderStyle: ChromeStyle?
    let statusBarStyle: ChromeStyle?
}

extension _ChromeStyleScene: RootChromeStyleProvidingScene {
    /// A style closer to the content wins, per bar and independently — the same
    /// innermost-wins rule `.palette(...)` and `.appearance(...)` follow. Per
    /// bar, so an inner `.chromeStyle(appHeader:statusBar:)` overriding only one
    /// of them still lets an outer blanket `.chromeStyle(_:)` cover the other.
    func rootChromeStyle() -> (appHeader: ChromeStyle?, statusBar: ChromeStyle?) {
        let inner: (appHeader: ChromeStyle?, statusBar: ChromeStyle?) =
            (content as? any RootChromeStyleProvidingScene)?.rootChromeStyle()
            ?? (appHeader: nil, statusBar: nil)
        return (inner.appHeader ?? appHeaderStyle, inner.statusBar ?? statusBarStyle)
    }
}

extension _ChromeStyleScene: RootPaletteOverrideProvidingScene {
    /// Pass-through, so `.chromeStyle(...)` composes with `.palette(...)` in
    /// either order.
    func rootPaletteOverride() -> (any Palette)? {
        (content as? any RootPaletteOverrideProvidingScene)?.rootPaletteOverride()
    }
}

extension _ChromeStyleScene: RootAppearanceOverrideProvidingScene {
    /// Pass-through, so `.chromeStyle(...)` composes with `.appearance(...)` in
    /// either order — which matters here more than most, since both restyle the
    /// same two bars.
    func rootAppearanceOverride() -> Appearance? {
        (content as? any RootAppearanceOverrideProvidingScene)?.rootAppearanceOverride()
    }
}

extension _ChromeStyleScene: MouseSupportProvidingScene {
    /// Pass-through, so `.chromeStyle(...)` composes with `.mouseSupport(...)`.
    func resolvedMouseSupport() -> MouseSupport? {
        (content as? MouseSupportProvidingScene)?.resolvedMouseSupport()
    }
}

extension _ChromeStyleScene: SceneRenderable {
    /// The styles are applied by `RenderLoop` before the frame is laid out;
    /// rendering forwards to the wrapped scene.
    func renderScene(context: RenderContext) -> FrameBuffer {
        if let renderable = content as? SceneRenderable {
            return renderable.renderScene(context: context)
        }
        return FrameBuffer()
    }
}
