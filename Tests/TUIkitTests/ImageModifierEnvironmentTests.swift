//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageModifierEnvironmentTests.swift
//
//  Every image modifier is a one-line `environment(\.key, value)` forward, and
//  the image suite reached past all of them: it set the environment fields by
//  hand. So which key a modifier writes was pinned by nothing — swapping
//  `.imageEdgeContrast(_:)`'s body to `\.imageEdgeThreshold` compiled, and the
//  whole suite stayed green while apps silently retuned edge tracing instead
//  of local contrast. This asserts the forward itself: the named value lands
//  on the named key, and no other image key moves with it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitImage

/// Captures the environment the modifier chain delivered. A class, and
/// `@unchecked Sendable`, for the same reason `RenderPassScopeTests.ProbeState`
/// is: `Renderable` is not actor-isolated, so the probe cannot carry the
/// recording itself.
private final class EnvironmentRecording: @unchecked Sendable {
    var environment = EnvironmentValues()
}

/// A leaf that records the environment it was rendered with, and draws nothing.
private struct EnvironmentProbe: View, Renderable {
    let recording: EnvironmentRecording

    var body: Never { fatalError("EnvironmentProbe renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        recording.environment = context.environment
        return FrameBuffer(lines: [""])
    }
}

@MainActor
@Suite("Image modifiers write the keys they name")
struct ImageModifierEnvironmentTests {

    /// Every image environment field, as `name → description`.
    ///
    /// Described rather than compared: the field types are a mix of enums,
    /// optionals and structs with no shared conformance, and all this needs is
    /// "did it move", with a readable answer when it did.
    private func snapshot(of environment: EnvironmentValues) -> [String: String] {
        [
            "imageAspectRatio": String(describing: environment.imageAspectRatio),
            "imageCellAspect": String(describing: environment.imageCellAspect),
            "imageCellPixels": String(describing: environment.imageCellPixels),
            "imageCharacterSet": String(describing: environment.imageCharacterSet),
            "imageColorMode": String(describing: environment.imageColorMode),
            "imageContentMode": String(describing: environment.imageContentMode),
            "imageDithering": String(describing: environment.imageDithering),
            "imageEdgeContrast": String(describing: environment.imageEdgeContrast),
            "imageEdgeThreshold": String(describing: environment.imageEdgeThreshold),
            "imageFitTarget": String(describing: environment.imageFitTarget),
            "imageMaxPixelCount": String(describing: environment.imageMaxPixelCount),
            "imagePlaceholderSpinner": String(describing: environment.imagePlaceholderSpinner),
            "imagePlaceholderText": String(describing: environment.imagePlaceholderText),
            "imageShapeAware": String(describing: environment.imageShapeAware),
            "imageSupersampling": String(describing: environment.imageSupersampling),
            "imageToneCurve": String(describing: environment.imageToneCurve),
            "imageURLTimeout": String(describing: environment.imageURLTimeout),
            "imageZoom": String(describing: environment.imageZoom),
        ]
    }

    /// Renders `view` and returns the environment its leaf saw.
    private func delivered(_ modified: (EnvironmentProbe) -> AnyView) -> [String: String] {
        let recording = EnvironmentRecording()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        let context = RenderContext(
            availableWidth: 20, availableHeight: 4, environment: environment,
            tuiContext: TUIContext())
        _ = renderToBuffer(modified(EnvironmentProbe(recording: recording)), context: context)
        return snapshot(of: recording.environment)
    }

    /// The environment with no image modifier applied at all.
    private var defaults: [String: String] {
        delivered { AnyView($0) }
    }

    /// Asserts that `modified` moved exactly `expected` and nothing else.
    private func check(
        _ label: String, _ expected: [String: String],
        _ modified: (EnvironmentProbe) -> AnyView,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let base = defaults
        let after = delivered(modified)
        let moved = after.filter { base[$0.key] != $0.value }
        #expect(
            moved.keys.sorted() == expected.keys.sorted(),
            "\(label): moved \(moved.keys.sorted()), expected \(expected.keys.sorted())",
            sourceLocation: sourceLocation)
        for (key, value) in expected {
            #expect(
                after[key] == value,
                "\(label): \(key) is \(after[key] ?? "<absent>"), expected \(value)",
                sourceLocation: sourceLocation)
        }
    }

    // MARK: - Conversion

    @Test("The glyph and colour modifiers each write their own key")
    func conversionModifiers() {
        check("imageCharacterSet", ["imageCharacterSet": String(describing: ASCIICharacterSet.customRamp(" .:#"))]) {
            AnyView($0.imageCharacterSet(.customRamp(" .:#")))
        }
        check("imageShapeAware", ["imageShapeAware": "true"]) {
            AnyView($0.imageShapeAware())
        }
        check("imageColorMode", ["imageColorMode": String(describing: ASCIIColorMode.ansi16)]) {
            AnyView($0.imageColorMode(.ansi16))
        }
        let curve = ASCIIToneCurve([(Color.black, Color.white)])
        check("imageToneCurve", ["imageToneCurve": String(describing: Optional(curve))]) {
            AnyView($0.imageToneCurve(curve))
        }
        check("imageDithering", ["imageDithering": String(describing: DitheringMode.floydSteinberg)]) {
            AnyView($0.imageDithering(.floydSteinberg))
        }
    }

    @Test("The three sampling knobs are three separate keys")
    func samplingModifiers() {
        // The pair the mutation test turns on: `imageSupersampling` and
        // `imageMaxPixelCount` are both `Int?`, so a swapped forward compiles.
        check("imageSupersampling", ["imageSupersampling": "Optional(3)"]) {
            AnyView($0.imageSupersampling(3))
        }
        check("imageMaxPixelCount", ["imageMaxPixelCount": "Optional(4096)"]) {
            AnyView($0.imageMaxPixelCount(4096))
        }
        // And so are `imageEdgeThreshold` (Double?) and `imageEdgeContrast`
        // (Double) — the latter promotes into the former's slot.
        check("imageEdgeThreshold", ["imageEdgeThreshold": "Optional(0.42)"]) {
            AnyView($0.imageEdgeThreshold(0.42))
        }
        check("imageEdgeContrast", ["imageEdgeContrast": "0.8"]) {
            AnyView($0.imageEdgeContrast(0.8))
        }
    }

    // MARK: - Placeholder

    @Test("All three placeholder overloads write the placeholder text")
    func placeholderModifiers() {
        // Resolved through the same service the modifier uses: the assertion
        // here is that the LOCALIZED overload resolves at all, not what any
        // particular catalogue says.
        let key = LocalizedStringKey("image.probe.placeholder")
        check("imagePlaceholder(key)", ["imagePlaceholderText": String(describing: Optional(key.localized))]) {
            AnyView($0.imagePlaceholder(key))
        }
        check("imagePlaceholder(Substring)", ["imagePlaceholderText": #"Optional("loading")"#]) {
            AnyView($0.imagePlaceholder("loading…".dropLast()))
        }
        check("imagePlaceholder(String?)", ["imagePlaceholderText": #"Optional("wait")"#]) {
            AnyView($0.imagePlaceholder(String?.some("wait")))
        }
        check("imagePlaceholderSpinner", ["imagePlaceholderSpinner": "false"]) {
            AnyView($0.imagePlaceholderSpinner(false))
        }
    }

    // MARK: - Geometry

    @Test("aspectRatio writes both of its keys, and the scaledTo pair writes only the mode")
    func geometryModifiers() {
        check(
            "aspectRatio",
            [
                "imageContentMode": String(describing: ContentMode.fill),
                "imageAspectRatio": "Optional(1.5)",
            ]
        ) {
            AnyView($0.aspectRatio(1.5, contentMode: .fill))
        }
        // `scaledToFit()` is the default mode, so it moves nothing — which is
        // exactly what it should do, and is asserted as such rather than
        // skipped.
        check("scaledToFit", [:]) { AnyView($0.scaledToFit()) }
        check("scaledToFill", ["imageContentMode": String(describing: ContentMode.fill)]) {
            AnyView($0.scaledToFill())
        }
        check("imageFitTarget", ["imageFitTarget": String(describing: ImageFitTarget.viewport)]) {
            AnyView($0.imageFitTarget(.viewport))
        }
        check("imageZoom", ["imageZoom": "2.5"]) { AnyView($0.imageZoom(2.5)) }
        check("imageCellAspect", ["imageCellAspect": "1.0"]) { AnyView($0.imageCellAspect(1.0)) }
    }

    // MARK: - Loading

    @Test("The URL timeout is its own key")
    func loadingModifiers() {
        check("imageURLTimeout", ["imageURLTimeout": "12.5"]) { AnyView($0.imageURLTimeout(12.5)) }
    }
}
