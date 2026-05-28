//  🖥️ TUIKit — Terminal UI Kit for Swift
//  _ImageCore.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - State Indices

/// Named property indices for `_ImageCore` state storage.
private enum StateIndex {
    /// Stores the loading phase (`ImageLoadingPhase`).
    static let phase = 0

    /// Stores the last loaded source for change detection (`ImageSource`).
    static let lastSource = 1

    /// Stores the most recent ASCII conversion output and its parameters,
    /// so the next render at the same size + settings reuses the cached
    /// glyph buffer instead of re-running `ASCIIConverter.convert`.
    static let renderCache = 2
}

// MARK: - Render Cache

/// Cached ASCII conversion output along with the input parameters that
/// produced it.
///
/// Re-using `ASCIIConverter` output across frames is safe whenever every
/// input that influences the output is unchanged. The cache key spans the
/// loaded image's pixel dimensions, the output cell footprint, and every
/// styling environment value that the converter reads. A `_ImageCore`
/// only keeps the most-recent entry because each instance hosts one
/// image; on a hit the cached `[String]` is returned without touching
/// `ASCIIConverter.convert`.
private struct ImageRenderCache: Equatable {
    var rawImageWidth: Int
    var rawImageHeight: Int
    var width: Int
    var height: Int
    var characterSet: ASCIICharacterSet
    var colorMode: ASCIIColorMode
    var dithering: DitheringMode
    var contentMode: ContentMode
    var aspectRatioOverride: Double?
    var lines: [String]

    /// Returns whether `self` was built from the same inputs as the
    /// pending render. Compares everything except the cached `lines`.
    func matches(  // swiftlint:disable:this function_parameter_count
        rawImageWidth: Int, rawImageHeight: Int,
        width: Int, height: Int,
        characterSet: ASCIICharacterSet, colorMode: ASCIIColorMode,
        dithering: DitheringMode, contentMode: ContentMode,
        aspectRatioOverride: Double?
    ) -> Bool {
        self.rawImageWidth == rawImageWidth
            && self.rawImageHeight == rawImageHeight
            && self.width == width
            && self.height == height
            && self.characterSet == characterSet
            && self.colorMode == colorMode
            && self.dithering == dithering
            && self.contentMode == contentMode
            && self.aspectRatioOverride == aspectRatioOverride
    }
}

// MARK: - Image Core

/// Private rendering implementation for ``Image``.
///
/// Handles async image loading, caching, and placeholder display.
/// The raw `RGBAImage` is cached in state; ASCII conversion happens
/// on every render pass so that environment changes (character set,
/// color mode, dithering) take effect immediately.
struct _ImageCore: View, Renderable, Layoutable {
    /// The image source.
    let source: ImageSource

    var body: Never {
        fatalError("_ImageCore renders via Renderable")
    }

    // MARK: - Layoutable

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let proposedWidth = proposal.width ?? context.availableWidth
        let proposedHeight = proposal.height ?? context.availableHeight
        return .fixed(proposedWidth, proposedHeight)
    }

    // MARK: - Renderable

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let stateStorage = context.environment.stateStorage!
        let lifecycle = context.environment.lifecycle!
        let identity = context.identity

        let width = context.availableWidth
        let height = context.availableHeight

        guard width > 0, height > 0 else {
            return FrameBuffer()
        }

        // Read environment values
        let characterSet = context.environment.imageCharacterSet
        let colorMode = context.environment.imageColorMode
        let dithering = context.environment.imageDithering
        let contentMode = context.environment.imageContentMode
        let aspectRatioOverride = context.environment.imageAspectRatio
        let placeholderText = context.environment.imagePlaceholderText
        let showSpinner = context.environment.imagePlaceholderSpinner
        let maxPixelCount = context.environment.imageMaxPixelCount
        let urlTimeout = context.environment.imageURLTimeout

        // Retrieve or create persistent phase state
        let phaseKey = StateStorage.StateKey(identity: identity, propertyIndex: StateIndex.phase)
        let phaseBox: StateBox<ImageLoadingPhase> = stateStorage.storage(for: phaseKey, default: .loading)
        stateStorage.markActive(identity)

        // Track the last loaded source to detect changes
        let sourceKey = StateStorage.StateKey(identity: identity, propertyIndex: StateIndex.lastSource)
        let lastSourceBox: StateBox<ImageSource?> = stateStorage.storage(for: sourceKey, default: nil)

        // Build a unique token for this image source
        let token = "image-\(identity.path)"

        // Detect source change and force reload
        if let lastSource = lastSourceBox.value, lastSource != source {
            lifecycle.cancelTask(token: token)
            lifecycle.resetAppearance(token: token)
            phaseBox.value = .loading
        }
        lastSourceBox.value = source

        // Start loading on first appearance
        if !lifecycle.hasAppeared(token: token) {
            _ = lifecycle.recordAppear(token: token) {}

            let src = source
            lifecycle.startTask(token: token, priority: .userInitiated) {
                let loader = PlatformImageLoader()

                do {
                    let rawImage: RGBAImage
                    switch src {
                    case .file(let path):
                        rawImage = try loader.loadImage(from: path, maxPixelCount: maxPixelCount)
                    case .url(let urlString):
                        rawImage = try loader.loadImage(
                            from: urlString,
                            cache: .shared,
                            timeout: urlTimeout,
                            maxPixelCount: maxPixelCount
                        )
                    }

                    // Store the raw image; conversion happens per render pass.
                    // StateBox.didSet triggers setNeedsRender() automatically,
                    // so there is no need to hop to the main actor here.
                    phaseBox.value = .success(rawImage)
                } catch let loadError as ImageLoadError {
                    phaseBox.value = .failure(loadError.description)
                } catch {
                    phaseBox.value = .failure(error.localizedDescription)
                }
            }
        } else {
            _ = lifecycle.recordAppear(token: token) {}
        }

        // Cancel loading task on disappear
        lifecycle.registerDisappear(token: token) { [lifecycle] in
            lifecycle.cancelTask(token: token)
        }

        // Render based on current phase
        switch phaseBox.value {
        case .loading:
            return renderPlaceholder(
                width: width,
                height: height,
                text: placeholderText,
                showSpinner: showSpinner,
                context: context
            )

        case .success(let rawImage):
            return renderImage(
                rawImage,
                width: width,
                height: height,
                characterSet: characterSet,
                colorMode: colorMode,
                dithering: dithering,
                contentMode: contentMode,
                aspectRatioOverride: aspectRatioOverride,
                stateStorage: stateStorage,
                identity: identity
            )

        case .failure(let message):
            return renderError(message, width: width, height: height, context: context)
        }
    }
}

// MARK: - Image Rendering

extension _ImageCore {

    /// Converts the raw image to ASCII art for the current frame dimensions and settings.
    ///
    /// The conversion is cached in `StateStorage`: if the next render is
    /// passed the same image at the same target size with the same
    /// styling, the previous conversion's `[String]` is returned without
    /// re-running `ASCIIConverter.convert`. That converter is the
    /// hot spot of the renderer (especially in the `.shapeBased` and
    /// `.braille` modes), and the typical TUIkit redraw cadence —
    /// spinner pulses, focus animations — re-renders an unchanged image
    /// many times per second.
    private func renderImage(  // swiftlint:disable:this function_parameter_count
        _ rawImage: RGBAImage,
        width: Int,
        height: Int,
        characterSet: ASCIICharacterSet,
        colorMode: ASCIIColorMode,
        dithering: DitheringMode,
        contentMode: ContentMode,
        aspectRatioOverride: Double?,
        stateStorage: StateStorage,
        identity: ViewIdentity
    ) -> FrameBuffer {
        let targetSize = ASCIIConverter.targetSize(
            imageWidth: rawImage.width,
            imageHeight: rawImage.height,
            maxWidth: width,
            maxHeight: height,
            contentMode: contentMode,
            overrideAspectRatio: aspectRatioOverride
        )

        guard targetSize.width > 0, targetSize.height > 0 else {
            return FrameBuffer()
        }

        // Check the per-view cache; if every conversion input matches,
        // skip the (potentially very expensive) re-conversion.
        let cacheKey = StateStorage.StateKey(identity: identity, propertyIndex: StateIndex.renderCache)
        let cacheBox: StateBox<ImageRenderCache?> = stateStorage.storage(for: cacheKey, default: nil)
        if let cache = cacheBox.value, cache.matches(
            rawImageWidth: rawImage.width,
            rawImageHeight: rawImage.height,
            width: targetSize.width,
            height: targetSize.height,
            characterSet: characterSet,
            colorMode: colorMode,
            dithering: dithering,
            contentMode: contentMode,
            aspectRatioOverride: aspectRatioOverride
        ) {
            return FrameBuffer(lines: cache.lines)
        }

        let converter = ASCIIConverter(
            characterSet: characterSet,
            colorMode: colorMode,
            dithering: dithering
        )
        let lines = converter.convert(rawImage, width: targetSize.width, height: targetSize.height)

        cacheBox.value = ImageRenderCache(
            rawImageWidth: rawImage.width,
            rawImageHeight: rawImage.height,
            width: targetSize.width,
            height: targetSize.height,
            characterSet: characterSet,
            colorMode: colorMode,
            dithering: dithering,
            contentMode: contentMode,
            aspectRatioOverride: aspectRatioOverride,
            lines: lines
        )

        return FrameBuffer(lines: lines)
    }
}

// MARK: - Placeholder Rendering

extension _ImageCore {

    /// Renders a centered placeholder with optional spinner and text.
    private func renderPlaceholder(
        width: Int,
        height: Int,
        text: String?,
        showSpinner: Bool,
        context: RenderContext
    ) -> FrameBuffer {
        let palette = context.environment.palette

        // Build placeholder content lines
        var contentLines: [String] = []

        if showSpinner {
            let spinnerText = "⠋"
            let colored = ANSIRenderer.colorize(spinnerText, foreground: palette.accent)
            contentLines.append(colored)
        }

        if let text {
            let colored = ANSIRenderer.colorize(text, foreground: palette.foregroundSecondary)
            contentLines.append(colored)
        }

        if contentLines.isEmpty {
            contentLines.append(ANSIRenderer.colorize("Loading...", foreground: palette.foregroundSecondary))
        }

        return centerContent(contentLines, width: width, height: height)
    }

    /// Renders an error message centered in the frame.
    private func renderError(
        _ message: String,
        width: Int,
        height: Int,
        context: RenderContext
    ) -> FrameBuffer {
        let palette = context.environment.palette
        let errorText = ANSIRenderer.colorize("Error: \(message)", foreground: palette.error)
        return centerContent([errorText], width: width, height: height)
    }

    /// Centers content lines vertically and horizontally within the given dimensions.
    private func centerContent(_ contentLines: [String], width: Int, height: Int) -> FrameBuffer {
        let emptyLine = String(repeating: " ", count: width)
        var lines = [String](repeating: emptyLine, count: height)

        let startY = max(0, (height - contentLines.count) / 2)

        for (i, content) in contentLines.enumerated() {
            let y = startY + i
            guard y < height else { break }

            // Calculate visible width of content (excluding ANSI codes, accounting for wide chars)
            let visibleWidth = content.strippedLength
            let padding = max(0, (width - visibleWidth) / 2)
            let padded = String(repeating: " ", count: padding) + content
            lines[y] = padded
        }

        return FrameBuffer(lines: lines, width: width)
    }
}
