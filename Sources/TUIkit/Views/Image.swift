//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Image.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Image Source

/// Describes where to load an image from.
public enum ImageSource: Sendable, Equatable {
    /// Load from a local file path.
    case file(String)

    /// Load from a URL (cached per session).
    case url(String)
}

// MARK: - Image Loading Phase

/// Represents the current state of an async image loading operation.
enum ImageLoadingPhase: Sendable {
    /// Loading has not started yet or is in progress.
    case loading

    /// The raw image was successfully loaded and is ready for conversion.
    case success(RGBAImage)

    /// Loading failed with an error.
    case failure(String)
}

// MARK: - Image

/// Displays an image as colored ASCII art in the terminal.
///
/// `Image` loads a raster image from a file path or URL, converts it to
/// colored ASCII characters, and displays it at the specified size.
/// Loading happens asynchronously; a placeholder is shown while loading.
///
/// ## Usage
///
/// ```swift
/// // From a local file
/// Image(.file("/path/to/logo.png"))
///     .frame(width: 60, height: 30)
///
/// // From a URL (cached per session)
/// Image(.url("https://example.com/photo.png"))
///     .frame(width: 40, height: 20)
///
/// // With rendering options
/// Image(.file("photo.png"))
///     .imageCharacterSet(.braille)
///     .imageColorMode(.trueColor)
///     .imageDithering(.floydSteinberg)
///     .frame(width: 80, height: 40)
/// ```
///
/// ## Placeholder
///
/// While loading, a centered placeholder is displayed. By default this is
/// a ``Spinner``. Use ``View/imagePlaceholder(_:)`` to customize.
///
/// ## SF Symbols
///
/// ``init(systemName:)`` makes the other kind of image SwiftUI has — a system
/// symbol — which in a terminal is one glyph rather than a raster:
///
/// ```swift
/// HStack {
///     Image(systemName: "star.fill")
///     Text("Favourite")
/// }
/// ```
///
/// The rendering modifiers above apply to raster images only; there is nothing
/// for them to do to a character. See ``SFSymbol`` for where symbols draw at
/// all, and ``Label/init(_:systemImage:)`` for the icon-with-title shape, which
/// is usually the better one because it can drop its gap as well as its glyph.
public struct Image: View {
    /// What this image *is* — the two unrelated things SwiftUI's `Image` also
    /// covers, kept as one type because that is the API being matched.
    ///
    /// They share nothing but the name: one is decoded, resampled and converted
    /// to coloured cells, the other is a single character looked up in a table.
    enum Content: Equatable {
        /// A raster image, loaded from a file or a URL.
        case raster(ImageSource)
        /// An SF Symbol, by name — resolved to a glyph at render time so
        /// ``View/symbolVariant(_:)`` above it still chooses the cut.
        case symbol(String)
    }

    let content: Content

    /// Creates an image from the given source.
    ///
    /// - Parameter source: The image source (file or URL).
    public init(_ source: ImageSource) {
        self.content = .raster(source)
    }

    /// Creates an image showing the named SF Symbol.
    ///
    /// Mirrors SwiftUI's `Image(systemName:)`. The symbol is a terminal glyph,
    /// not artwork: it takes the two cells a wide character takes and follows
    /// the surrounding text's colour, and it cannot be scaled.
    ///
    /// Where the symbol would not really draw — a non-Apple platform, a
    /// terminal without the SF Symbols font, an unknown name — this renders
    /// **nothing**, because there is nothing else it could honestly show (see
    /// ``SFSymbol/canRender(named:)``). That is the one place
    /// ``Label/init(_:systemImage:)`` does better: it can close the gap it was
    /// going to leave, and a bare `Image` in an `HStack` cannot, the spacing
    /// being the stack's.
    ///
    /// - Parameter systemName: The SF Symbol name, e.g. `"star.fill"`.
    public init(systemName: String) {
        self.content = .symbol(systemName)
    }

    @ViewBuilder
    public var body: some View {
        switch content {
        case .raster(let source):
            _ImageCore(source: source)
        case .symbol(let name):
            _SymbolIcon(name: name)
        }
    }
}

// MARK: - Equatable

extension Image: @preconcurrency Equatable {
    public static func == (lhs: Image, rhs: Image) -> Bool {
        lhs.content == rhs.content
    }
}

// MARK: - Environment Keys

/// Environment key for the glyph charset used by Image.
private struct ImageCharacterSetKey: EnvironmentKey {
    static let defaultValue: ASCIICharacterSet = .blocks(.fine)
}

/// Environment key for shape-aware glyph matching.
private struct ImageShapeAwareKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

/// Environment key for the color mode used by Image.
private struct ImageColorModeKey: EnvironmentKey {
    static let defaultValue: ASCIIColorMode = .trueColor
}

/// Environment key for the dithering mode used by Image.
private struct ImageDitheringKey: EnvironmentKey {
    static let defaultValue: DitheringMode = .none
}

/// Environment key for the brightness-mapping supersampling factor.
private struct ImageSupersamplingKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

/// Environment key for the shape-mode edge-glyph gradient threshold.
private struct ImageEdgeThresholdKey: EnvironmentKey {
    static let defaultValue: Double? = 0.9
}

/// Environment key for the placeholder text shown while loading.
private struct ImagePlaceholderTextKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

/// Environment key controlling whether a spinner is shown while loading.
private struct ImagePlaceholderSpinnerKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

/// Environment key for the image content mode.
private struct ImageContentModeKey: EnvironmentKey {
    static let defaultValue: ContentMode = .fit
}

/// Environment key for an explicit aspect ratio override.
private struct ImageAspectRatioKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

/// Environment key for the terminal cell's height:width ratio (see
/// ``View/imageCellAspect(_:)``). Defaults to `2.0` — Apple Terminal's typical
/// cell — and is republished at the render root from the terminal's reported
/// pixel size when available.
private struct ImageCellAspectKey: EnvironmentKey {
    static let defaultValue: Double = 2.0
}

/// Environment key for the maximum allowed image pixel count.
private struct ImageMaxPixelCountKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

/// Environment key for the URL download timeout in seconds.
private struct ImageURLTimeoutKey: EnvironmentKey {
    static let defaultValue: TimeInterval = 30
}

/// The reference box an image scales to fit — see ``View/imageFitTarget(_:)``.
///
/// `.fit`/`.fill` (``ContentMode``) decides *how* an image scales relative to a box;
/// this decides *which box*. The two are orthogonal.
public enum ImageFitTarget: Sendable, Hashable, CaseIterable {
    /// Fit the size the layout proposes — the default. Inside a `ScrollView` the
    /// proposed size is unbounded on the scroll axis, so the image becomes
    /// width-driven and can be scrolled at full size.
    case proposedSize

    /// Fit the visible viewport — the innermost enclosing `ScrollView`'s visible
    /// content area, or the proposed size when there is no enclosing `ScrollView`.
    /// The image fills the viewport at ``View/imageZoom(_:)`` `1` and overflows
    /// (scrolling, with scrollbars appearing automatically) only when zoomed in.
    case viewport
}

/// Environment key for the image fit target.
private struct ImageFitTargetKey: EnvironmentKey {
    static let defaultValue: ImageFitTarget = .proposedSize
}

/// Environment key for the image zoom multiplier.
private struct ImageZoomKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

// MARK: - EnvironmentValues

extension EnvironmentValues {
    /// The character set for ASCII art rendering.
    var imageCharacterSet: ASCIICharacterSet {
        get { self[ImageCharacterSetKey.self] }
        set { self[ImageCharacterSetKey.self] = newValue }
    }

    /// Whether image glyphs are shape-matched — see
    /// ``View/imageShapeAware(_:)``.
    var imageShapeAware: Bool {
        get { self[ImageShapeAwareKey.self] }
        set { self[ImageShapeAwareKey.self] = newValue }
    }

    /// The color mode for ASCII art rendering.
    var imageColorMode: ASCIIColorMode {
        get { self[ImageColorModeKey.self] }
        set { self[ImageColorModeKey.self] = newValue }
    }

    /// The supersampling factor for brightness-mapping character sets —
    /// see ``View/imageSupersampling(_:)``.
    var imageSupersampling: Int? {
        get { self[ImageSupersamplingKey.self] }
        set { self[ImageSupersamplingKey.self] = newValue }
    }

    /// The shape-mode edge-glyph threshold — see
    /// ``View/imageEdgeThreshold(_:)``.
    var imageEdgeThreshold: Double? {
        get { self[ImageEdgeThresholdKey.self] }
        set { self[ImageEdgeThresholdKey.self] = newValue }
    }

    /// The dithering mode for ASCII art rendering.
    var imageDithering: DitheringMode {
        get { self[ImageDitheringKey.self] }
        set { self[ImageDitheringKey.self] = newValue }
    }

    /// Custom placeholder text shown while loading (nil = no text).
    var imagePlaceholderText: String? {
        get { self[ImagePlaceholderTextKey.self] }
        set { self[ImagePlaceholderTextKey.self] = newValue }
    }

    /// Whether to show a spinner in the placeholder.
    var imagePlaceholderSpinner: Bool {
        get { self[ImagePlaceholderSpinnerKey.self] }
        set { self[ImagePlaceholderSpinnerKey.self] = newValue }
    }

    /// The content mode for image scaling.
    var imageContentMode: ContentMode {
        get { self[ImageContentModeKey.self] }
        set { self[ImageContentModeKey.self] = newValue }
    }

    /// An explicit aspect ratio override for images (width/height).
    ///
    /// When `nil`, the source image's natural aspect ratio is used.
    var imageAspectRatio: Double? {
        get { self[ImageAspectRatioKey.self] }
        set { self[ImageAspectRatioKey.self] = newValue }
    }

    /// The maximum allowed total pixel count for loaded images.
    ///
    /// Images exceeding this limit will fail with `ImageLoadError.imageTooLarge`.
    /// `nil` means no limit (default).
    var imageMaxPixelCount: Int? {
        get { self[ImageMaxPixelCountKey.self] }
        set { self[ImageMaxPixelCountKey.self] = newValue }
    }

    /// The timeout in seconds for URL image downloads.
    ///
    /// Defaults to 30 seconds.
    var imageURLTimeout: TimeInterval {
        get { self[ImageURLTimeoutKey.self] }
        set { self[ImageURLTimeoutKey.self] = newValue }
    }

    /// The reference box images scale to fit — proposed size vs visible viewport.
    var imageFitTarget: ImageFitTarget {
        get { self[ImageFitTargetKey.self] }
        set { self[ImageFitTargetKey.self] = newValue }
    }

    /// The zoom multiplier applied to an image's fitted size (`1` = fit exactly).
    var imageZoom: Double {
        get { self[ImageZoomKey.self] }
        set { self[ImageZoomKey.self] = newValue }
    }

    /// The terminal cell's height:width ratio, used to size an image so it isn't
    /// distorted. See ``View/imageCellAspect(_:)``.
    public var imageCellAspect: Double {
        get { self[ImageCellAspectKey.self] }
        set { self[ImageCellAspectKey.self] = newValue }
    }
}

// MARK: - View Modifiers

extension View {

    /// Sets the glyph charset for image rendering — the fundamental
    /// repertoire (``ASCIICharacterSet/ascii(glyphs:)`` /
    /// ``ASCIICharacterSet/unicode(glyphs:)`` /
    /// ``ASCIICharacterSet/blocks(_:)`` /
    /// ``ASCIICharacterSet/customRamp(_:)``) and its size. Combine with
    /// ``imageShapeAware(_:)`` to choose the rendering algorithm.
    ///
    /// - Parameter characterSet: The charset to use.
    /// - Returns: A modified view.
    public func imageCharacterSet(_ characterSet: ASCIICharacterSet) -> some View {
        environment(\.imageCharacterSet, characterSet)
    }

    /// Sets whether image glyphs are SHAPE-matched — each glyph chosen for
    /// how its measured in-cell ink distribution fits the cell (a corner of
    /// darkness picks a corner-heavy glyph; curved edges follow) — rather
    /// than mapped from the cell's overall luminance alone.
    ///
    /// Applies to the `.ascii`, `.unicode`, and `.blocks` charsets (blocks
    /// shape-match over quadrants / halves / shades / corner triangles
    /// `◢◣◤◥`); a `.customRamp` is always luminance-mapped.
    public func imageShapeAware(_ shapeAware: Bool = true) -> some View {
        environment(\.imageShapeAware, shapeAware)
    }

    /// Sets the color mode for ASCII art image rendering.
    ///
    /// - Parameter colorMode: The color mode to use.
    /// - Returns: A modified view.
    public func imageColorMode(_ colorMode: ASCIIColorMode) -> some View {
        environment(\.imageColorMode, colorMode)
    }

    /// Sets the area-sampling factor for every non-shape renderer: each
    /// sample — a ramp cell's tone, a solid or half-block pixel, a braille
    /// dot — is averaged from a factor×factor block of source pixels
    /// instead of the bilinear scaler's 2×2 point read, which aliases fine
    /// textures on heavy downscales. Clamped to 1...4. Pass `nil` to
    /// restore the default (2 for luminance ramps longer than 12 levels,
    /// else 1). Ignored when ``imageShapeAware(_:)`` is on — the shape
    /// matcher already reads 96 staggered samples per cell.
    public func imageSupersampling(_ factor: Int?) -> some View {
        environment(\.imageSupersampling, factor)
    }

    /// Sets the minimum Sobel gradient magnitude for a shape-aware cell
    /// (see ``imageShapeAware(_:)``) to be drawn as a directional line
    /// glyph (`- | / \` for the ASCII charset, `─ │ ╱ ╲` for Unicode)
    /// instead of its nearest coverage match. Lower values trace more
    /// edges; the default `0.9` (in 0…1 region-darkness units, practical
    /// range roughly 0.3…2) triggers on a clean light/dark boundary across
    /// a cell. Pass `nil` to disable line glyphs entirely (pure coverage
    /// matching). The shape-aware block repertoire carries its own
    /// directional glyphs, so it does not trace edges.
    public func imageEdgeThreshold(_ threshold: Double?) -> some View {
        environment(\.imageEdgeThreshold, threshold)
    }

    /// Sets the dithering mode for ASCII art image rendering.
    ///
    /// - Parameter dithering: The dithering algorithm.
    /// - Returns: A modified view.
    public func imageDithering(_ dithering: DitheringMode) -> some View {
        environment(\.imageDithering, dithering)
    }

    /// Sets the localized placeholder text shown while an image is loading.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``. The text is not optional in this overload:
    /// `nil` has no key to look up, and would otherwise be ambiguous between
    /// the two.
    ///
    /// - Parameter textKey: The key for the placeholder text.
    /// - Returns: A modified view.
    public func imagePlaceholder(_ textKey: LocalizedStringKey) -> some View {
        environment(\.imagePlaceholderText, textKey.localized)
    }

    /// Sets the placeholder text shown while an image is loading, as written.
    ///
    /// - Parameter text: The placeholder text, or nil for no text.
    /// - Returns: A modified view.
    @_disfavoredOverload
    public func imagePlaceholder(_ text: String?) -> some View {
        environment(\.imagePlaceholderText, text)
    }

    /// Controls whether a spinner is shown while an image is loading.
    ///
    /// - Parameter showSpinner: Whether to show a spinner.
    /// - Returns: A modified view.
    public func imagePlaceholderSpinner(_ showSpinner: Bool) -> some View {
        environment(\.imagePlaceholderSpinner, showSpinner)
    }

    /// Sets the aspect ratio and content mode for image rendering.
    ///
    /// Use this modifier to control how images are scaled within their
    /// available space.
    ///
    /// ```swift
    /// // Use natural aspect ratio, fit within bounds
    /// Image(.file("photo.png"))
    ///     .aspectRatio(contentMode: .fit)
    ///
    /// // Force 16:9 ratio, fill bounds
    /// Image(.url("https://example.com/banner.png"))
    ///     .aspectRatio(16.0/9.0, contentMode: .fill)
    /// ```
    ///
    /// - Parameters:
    ///   - aspectRatio: The ratio of width to height to use for the
    ///     resulting view. Use `nil` to maintain the source image's
    ///     natural aspect ratio.
    ///   - contentMode: A flag that indicates whether this view fits or
    ///     fills the parent context.
    /// - Returns: A view that constrains this view's dimensions to the
    ///   given aspect ratio and content mode.
    public func aspectRatio(_ aspectRatio: Double? = nil, contentMode: ContentMode) -> some View {
        environment(\.imageContentMode, contentMode)
            .environment(\.imageAspectRatio, aspectRatio)
    }

    /// Scales this view to fit within the parent while maintaining the
    /// aspect ratio.
    ///
    /// Equivalent to `.aspectRatio(contentMode: .fit)`.
    ///
    /// - Returns: A view that scales to fit.
    public func scaledToFit() -> some View {
        aspectRatio(contentMode: .fit)
    }

    /// Scales this view to fill the parent while maintaining the
    /// aspect ratio.
    ///
    /// Equivalent to `.aspectRatio(contentMode: .fill)`.
    ///
    /// - Returns: A view that scales to fill.
    public func scaledToFill() -> some View {
        aspectRatio(contentMode: .fill)
    }

    /// Sets the reference box this image scales to fit.
    ///
    /// `.fit`/`.fill` (via ``aspectRatio(_:contentMode:)``) decides *how* an image
    /// scales; this decides *which box* it scales to. By default an image fits the
    /// size the layout proposes (``ImageFitTarget/proposedSize``) — which inside a
    /// `ScrollView` is unbounded on the scroll axis, so the image renders at full
    /// size and scrolls. Pass ``ImageFitTarget/viewport`` to fit the enclosing
    /// `ScrollView`'s *visible* area instead: the image fills the viewport at
    /// ``imageZoom(_:)`` `1` and overflows (showing scrollbars) only when zoomed in,
    /// so one fixed view tree goes from "fits exactly" to "scroll around" purely by
    /// changing the zoom.
    ///
    /// - Parameter target: The box to fit within.
    /// - Returns: A modified view.
    public func imageFitTarget(_ target: ImageFitTarget) -> some View {
        environment(\.imageFitTarget, target)
    }

    /// Scales an image by a zoom multiplier on top of its fitted size.
    ///
    /// `1` (the default) renders at the fitted size; `2` doubles it; and so on.
    /// Combine with ``imageFitTarget(_:)`` `.viewport` inside a `ScrollView` to zoom
    /// an image in and out, scrollbars appearing automatically once it exceeds the
    /// viewport. The ASCII conversion re-runs at the zoomed size, so zooming in adds
    /// detail rather than just enlarging cells.
    ///
    /// - Parameter factor: The zoom multiplier (clamped to a small positive minimum).
    /// - Returns: A modified view.
    public func imageZoom(_ factor: Double) -> some View {
        environment(\.imageZoom, factor)
    }

    /// Sets the terminal cell's height-to-width ratio for image sizing.
    ///
    /// A terminal cell is taller than it is wide, so an image needs more columns
    /// than rows to look undistorted. This ratio governs by how much: `2.0` (the
    /// default, ~Apple Terminal) means cells are twice as tall as wide, so a
    /// square image is laid out roughly 2 columns per row. The real ratio depends
    /// on the terminal, font, and line spacing — iTerm2's differs from Apple
    /// Terminal's, which is why an image tuned for one looks horizontally
    /// squished or stretched on the other.
    ///
    /// TUIkit auto-detects the ratio from the terminal's reported pixel cell size
    /// where available; set this explicitly to override it (e.g. to match a
    /// custom font or a terminal that doesn't report its cell size).
    ///
    /// - Parameter ratio: Cell height ÷ cell width (values ≤ 0 are ignored).
    /// - Returns: A modified view.
    public func imageCellAspect(_ ratio: Double) -> some View {
        environment(\.imageCellAspect, ratio > 0 ? ratio : 2.0)
    }

    /// Sets the maximum allowed pixel count for image loading.
    ///
    /// Images with more total pixels than this limit will fail to load
    /// with `ImageLoadError.imageTooLarge`. Use this to prevent excessive
    /// memory usage from very large images.
    ///
    /// ```swift
    /// Image(.url("https://example.com/photo.png"))
    ///     .imageMaxPixelCount(4_000_000)  // ~4 megapixels
    /// ```
    ///
    /// - Parameter maxPixels: The maximum total pixel count, or `nil` for no limit.
    /// - Returns: A modified view.
    public func imageMaxPixelCount(_ maxPixels: Int?) -> some View {
        environment(\.imageMaxPixelCount, maxPixels)
    }

    /// Sets the timeout for URL image downloads.
    ///
    /// If the download does not complete within the specified interval,
    /// it fails with `ImageLoadError.downloadFailed`.
    ///
    /// ```swift
    /// Image(.url("https://example.com/photo.png"))
    ///     .imageURLTimeout(10)  // 10 seconds
    /// ```
    ///
    /// - Parameter seconds: The timeout in seconds (default: 30).
    /// - Returns: A modified view.
    public func imageURLTimeout(_ seconds: TimeInterval) -> some View {
        environment(\.imageURLTimeout, seconds)
    }
}
