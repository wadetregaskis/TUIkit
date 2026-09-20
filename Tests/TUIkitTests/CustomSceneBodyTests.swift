//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CustomSceneBodyTests.swift
//
//  `Scene` used to declare no requirements at all, so a type that conformed to
//  it and put its content in `body` — the shape SwiftUI's own `Scene`
//  documentation teaches — compiled, ran, and drew an empty terminal. Nothing
//  cast to the internal `SceneRenderable`, so the render funnel returned a bare
//  `FrameBuffer()`. These tests pin the three halves of that: the content
//  renders, scene configuration applied INSIDE a custom scene reaches the
//  frame, and configuration applied AROUND one survives the hop through its
//  body.
//
//  Asserted against the bytes the frame writes rather than against the internal
//  `primitiveScene` walk, so the suite stays red on any tree where a custom
//  scene does not draw — including the one these tests were written against.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

// MARK: - Probe scenes

/// A custom scene: conforms to `Scene`, provides its content through `body`.
private struct CustomRootScene: Scene {
    var body: some Scene {
        WindowGroup {
            Text("custom-scene-content")
        }
    }
}

/// A custom scene that configures the frame from inside its own `body`.
private struct ConfiguredRootScene: Scene {
    var body: some Scene {
        WindowGroup {
            Text("configured-scene-content")
        }
        .palette(SystemPalette(.blue))
    }
}

private struct CustomSceneApp: App {
    init() {}
    var body: some Scene { CustomRootScene() }
}

private struct ConfiguredSceneApp: App {
    init() {}
    var body: some Scene { ConfiguredRootScene() }
}

/// The other order: the modifier is applied to the custom scene, so the wrapper
/// holds a scene that is not itself a rendering primitive.
private struct WrappedCustomSceneApp: App {
    init() {}
    var body: some Scene {
        CustomRootScene()
            .palette(SystemPalette(.amber))
    }
}

@MainActor
@Suite("A custom Scene renders through its body")
struct CustomSceneBodyTests {

    @Test("An app whose scene is a custom Scene draws that scene's content")
    func customSceneRendersItsBody() {
        let harness = RenderLoopHarness()
        let loop = harness.loop(CustomSceneApp())

        _ = loop.render()

        #expect(
            harness.terminal.writtenOutput.joined().contains("custom-scene-content"),
            "a custom Scene's body must be walked, not silently dropped")
    }

    @Test("A scene modifier inside a custom Scene's body reaches the frame")
    func configurationInsideACustomSceneIsFound() {
        let harness = RenderLoopHarness()
        let loop = harness.loop(ConfiguredSceneApp())

        _ = loop.render()

        let output = harness.terminal.writtenOutput.joined()
        #expect(
            output.contains("configured-scene-content"),
            "a modified custom scene must still draw its content")
        #expect(
            output.contains(ANSIRenderer.backgroundCode(for: SystemPalette(.blue).background)),
            "the .palette(...) inside the custom scene's body must paint the frame")
    }

    @Test("A scene modifier applied to a custom Scene still renders and still applies")
    func configurationAroundACustomSceneSurvives() {
        let harness = RenderLoopHarness()
        let loop = harness.loop(WrappedCustomSceneApp())

        _ = loop.render()

        let output = harness.terminal.writtenOutput.joined()
        #expect(
            output.contains("custom-scene-content"),
            "the wrapper must forward through the custom scene's body to its content")
        // The wrapper answers for its own palette whatever its content is, so
        // this half was never broken — asserted so that teaching the wrapper to
        // look through its content cannot cost it its own value.
        #expect(
            output.contains(ANSIRenderer.backgroundCode(for: SystemPalette(.amber).background)),
            "the wrapper's own .palette(...) must still paint the frame")
    }
}
