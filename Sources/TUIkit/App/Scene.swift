//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Scene.swift
//
//  Created by LAYERED.work
//  License: MIT

/// The base protocol for scenes in TUIkit.
///
/// A scene represents a distinct region of the app's user interface,
/// analogous to SwiftUI's `Scene` protocol. In TUIkit, scenes define
/// the top-level structure of your terminal application.
///
/// ## Overview
///
/// Scenes sit between the ``App`` and ``View`` layers in TUIkit's
/// architecture. While views define the content, scenes define how
/// that content is organized at the application level.
///
/// Currently, TUIkit provides one scene type:
/// - ``WindowGroup``: Displays content in the terminal window
///
/// ## Conforming to Scene
///
/// Most apps use the built-in ``WindowGroup`` directly in the app's `body`:
///
/// ```swift
/// @main
/// struct MyApp: App {
///     var body: some Scene {
///         WindowGroup {
///             ContentView()
///         }
///     }
/// }
/// ```
///
/// A custom scene type works the same way it does in SwiftUI: conform to
/// `Scene` and return the scene you are made of from ``body-swift.property``.
///
/// ```swift
/// struct DocumentScene: Scene {
///     var body: some Scene {
///         WindowGroup {
///             ContentView()
///         }
///         .palette(SystemPalette(.blue))
///     }
/// }
/// ```
///
/// ## Topics
///
/// ### Built-in Scenes
/// - ``WindowGroup``
@MainActor
public protocol Scene {
    /// The type of scene this scene is composed of.
    ///
    /// Swift infers this from the `body` implementation. The framework's
    /// own primitives — ``WindowGroup`` and the wrappers the scene
    /// modifiers produce — set it to `Never` and render through
    /// `SceneRenderable` instead, exactly as a primitive `View` sets
    /// `View.Body` to `Never` and renders through `Renderable`.
    associatedtype Body: Scene

    /// The content and behaviour of this scene.
    @SceneBuilder
    var body: Body { get }
}

// MARK: - Never as Scene

/// `Never` conforms to `Scene` so a primitive scene — one that renders
/// itself rather than composing others — can declare `Body == Never`,
/// the same way primitive views do (`extension Never: View`).
///
/// The `body` witness is the one `extension Never: View` already declares:
/// a single `Never`-typed property satisfies both protocols, and neither
/// can ever call it, because no value of type `Never` exists.
extension Never: Scene {}

// MARK: - Scene Dispatch

extension Scene {
    /// The primitive this scene renders as: itself if it renders directly,
    /// otherwise whatever its `body` chain arrives at.
    ///
    /// The scene-side twin of the `Renderable`-or-`body` dispatch in
    /// `renderToBuffer(_:context:)`, and it is checked in the same order and
    /// by the same two tests: `SceneRenderable` conformance first, then
    /// `Body.self != Never.self` to decide whether descending into `body` is
    /// meaningful. A scene that is neither — `Body == Never` without
    /// `SceneRenderable` — is returned unchanged, and the caller handles it.
    ///
    /// The walk terminates because a `Body` chain cannot be circular: `body`'s
    /// type is written as `some Scene`, and an opaque type that resolved to a
    /// type whose own `body` resolved back to it is a circular reference the
    /// compiler rejects.
    ///
    /// **Every** runtime question asked of a scene goes through this, not just
    /// the rendering one: `RenderLoop` reads the frame's palette, appearance,
    /// mouse support and chrome style off a scene by casting it, and each of
    /// the four scene-modifier wrappers forwards the three concerns it does not
    /// own to its content the same way. A cast that skipped the hop would find
    /// nothing on a custom scene and drop that configuration in silence — the
    /// same defect as the blank screen, one level down.
    internal var primitiveScene: any Scene {
        if self is SceneRenderable { return self }
        guard Self.Body.self != Never.self else { return self }
        return body.primitiveScene
    }

    /// Renders this scene by descending to the primitive that draws.
    ///
    /// Traps rather than drawing nothing, because there is no legitimate way to
    /// reach the failure: `SceneRenderable` is internal, so a scene outside this
    /// module cannot be a primitive, and every scene inside it is one. Reaching
    /// here therefore means a `Body == Never` that conforms to nothing — a
    /// mistake the compiler cannot catch, whose only other outcome is a blank
    /// terminal for the life of the process with nothing said about it.
    ///
    /// This is where `View` and `Scene` deliberately part: the free
    /// `renderToBuffer(_:context:)` returns an empty buffer in the same
    /// position, and must, because `Renderable` is public and a `body: Never`
    /// view that forgot it is the app's own code to fix.
    internal func renderSceneTree(context: RenderContext) -> FrameBuffer {
        guard let renderable = primitiveScene as? SceneRenderable else {
            preconditionFailure(
                "\(type(of: self)) declares Body == Never but is not a rendering scene — "
                    + "a scene either composes others through `body` or is one of TUIkit's own "
                    + "primitives. Return a WindowGroup (or a scene modifier applied to one) "
                    + "from `body` instead."
            )
        }
        return renderable.renderScene(context: context)
    }
}

// MARK: - WindowGroup

/// A scene that represents a single window (terminal).
///
/// `WindowGroup` is the main scene for most TUI apps.
///
/// # Example
///
/// ```swift
/// WindowGroup {
///     ContentView()
/// }
/// ```
public struct WindowGroup<Content: View>: Scene {
    /// The content of the window.
    public let content: Content

    /// Creates a WindowGroup with the specified content.
    ///
    /// - Parameter content: A ViewBuilder that defines the content.
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    /// `WindowGroup` is a primitive scene: it renders through
    /// `SceneRenderable` and this is never called.
    public var body: Never {
        fatalError("WindowGroup renders via SceneRenderable")
    }
}

// MARK: - SceneBuilder

/// A result builder that constructs scene hierarchies from closures.
///
/// `SceneBuilder` enables the declarative syntax used in ``App/body-swift.property``
/// to define your application's scene structure. You don't use this type directly;
/// instead, the `@SceneBuilder` attribute is applied to the `body` property of
/// your ``App`` conforming type.
///
/// ## Overview
///
/// When you write:
///
/// ```swift
/// var body: some Scene {
///     WindowGroup {
///         ContentView()
///     }
/// }
/// ```
///
/// The `@SceneBuilder` attribute transforms this closure into a scene that
/// TUIkit can render. Currently, `SceneBuilder` supports a single scene
/// in the body, which is typically a ``WindowGroup``.
@MainActor
@resultBuilder
public struct SceneBuilder {
    /// Builds a scene expression from a single scene component.
    ///
    /// - Parameter content: The scene to build.
    /// - Returns: The same scene, unchanged.
    public static func buildBlock<Content: Scene>(_ content: Content) -> Content {
        content
    }
}
