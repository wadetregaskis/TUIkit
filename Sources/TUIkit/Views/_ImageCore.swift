//  🖥️ TUIkit — Terminal UI Kit for Swift
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
/// SOURCE, the loaded image's pixel dimensions, the output cell footprint, and
/// every styling environment value that the converter reads. A `_ImageCore`
/// only keeps the most-recent entry because each instance hosts one
/// image; on a hit the cached `[String]` is returned without touching
/// `ASCIIConverter.convert`.
private struct ImageRenderCache: Equatable {
    /// WHICH picture this was converted from — not merely how big it decoded.
    ///
    /// Pixel dimensions are not an identity. Two photographs, two icons, two
    /// frames of one sequence are routinely the same size, so a source change
    /// that lands on a same-size file re-decoded into an entry that still
    /// "matched", and the view drew the picture it used to show for as long as
    /// that identity lived. Carried for the same reason, and named the same
    /// way, as ``TerminalImageSignature/source`` on the pixel path — which had
    /// it from the start, so the same app switching pictures was correct on a
    /// Kitty-graphics terminal and stale on every other one.
    var source: ImageSource
    var rawImageWidth: Int
    var rawImageHeight: Int
    var width: Int
    var height: Int
    var characterSet: ASCIICharacterSet
    var shapeAware: Bool
    var colorMode: ASCIIColorMode
    var dithering: DitheringMode
    var toneCurve: ASCIIToneCurve?
    var supersampling: Int?
    var edgeThreshold: Double?
    var edgeContrast: Double
    var contentMode: ContentMode
    var aspectRatioOverride: Double?
    var cellAspect: Double
    var art: ASCIIArt

    /// Returns whether `self` was built from the same inputs as the
    /// pending render. Compares everything except the cached `art`.
    func matches(  // swiftlint:disable:this function_parameter_count
        source: ImageSource,
        rawImageWidth: Int, rawImageHeight: Int,
        width: Int, height: Int,
        characterSet: ASCIICharacterSet, shapeAware: Bool, colorMode: ASCIIColorMode,
        dithering: DitheringMode, toneCurve: ASCIIToneCurve?,
        supersampling: Int?, edgeThreshold: Double?, edgeContrast: Double,
        contentMode: ContentMode,
        aspectRatioOverride: Double?,
        cellAspect: Double
    ) -> Bool {
        self.rawImageWidth == rawImageWidth
            && self.rawImageHeight == rawImageHeight
            && self.width == width
            && self.height == height
            && self.characterSet == characterSet
            && self.shapeAware == shapeAware
            && self.colorMode == colorMode
            && self.dithering == dithering
            && self.toneCurve == toneCurve
            && self.supersampling == supersampling
            && self.edgeThreshold == edgeThreshold
            && self.edgeContrast == edgeContrast
            && self.contentMode == contentMode
            && self.aspectRatioOverride == aspectRatioOverride
            && self.cellAspect == cellAspect
            // Last: the scalar comparisons above reject the frequent miss — a
            // resize — before this one runs. It is the field that decides
            // correctness, not the one that usually decides the answer.
            && self.source == source
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
        let environment = context.environment
        // Already finite, positive and bounded: the environment's setter is
        // the one place that rule lives. Any positive zoom is honoured; the
        // rendered size is floored at one cell (see `zoomed`), so even a
        // 1/512 zoom shrinks gracefully to a single cell instead of vanishing.
        let zoom = environment.imageZoom

        // The box the image scales to fit: the visible viewport (when requested and
        // available) or the size the layout proposes. `.viewport` is what lets an
        // image fill the visible area at zoom 1 and overflow (scroll) only once
        // zoomed in, even though a ScrollView measures content against an unbounded
        // canvas.
        let fitWidth: Int
        let fitHeight: Int
        if environment.imageFitTarget == .viewport, let viewport = environment.scrollViewportSize {
            fitWidth = viewport.width
            fitHeight = viewport.height
        } else {
            fitWidth = proposal.width ?? context.availableWidth
            fitHeight = proposal.height ?? context.availableHeight
        }

        // Once the image has loaded, report the SAME aspect-fitted size the renderer
        // produces (height follows from width × aspect ratio), then apply zoom.
        // Reading the phase box is a pure lookup (no mutation that matters during a
        // measure pass).
        if let stateStorage = environment.stateStorage {
            let phaseKey = StateStorage.StateKey(
                identity: context.identity, propertyIndex: StateIndex.phase)
            let phaseBox: StateBox<ImageLoadingPhase> = stateStorage.storage(
                for: phaseKey, default: .loading)
            if case .success(let rawImage) = phaseBox.value, rawImage.width > 0, rawImage.height > 0 {
                let fitted = ASCIIConverter.targetSize(
                    imageWidth: rawImage.width, imageHeight: rawImage.height,
                    maxWidth: fitWidth, maxHeight: fitHeight,
                    contentMode: environment.imageContentMode,
                    overrideAspectRatio: environment.imageAspectRatio,
                    cellAspect: environment.imageCellAspect)
                return .fixed(Self.zoomed(fitted.width, zoom), Self.zoomed(fitted.height, zoom))
            }
        }

        // Before it loads, the aspect ratio is unknown — reserve a bounded
        // placeholder box (the terminal's cell aspect) rather than the full
        // offered height, so an unbounded offer can't balloon to thousands of
        // lines.
        let cellAspect = environment.imageCellAspect > 0 ? environment.imageCellAspect : 2.0
        let placeholderHeight = min(fitHeight, max(1, Int(Double(fitWidth) / cellAspect)))
        return .fixed(Self.zoomed(fitWidth, zoom), Self.zoomed(placeholderHeight, zoom))
    }

    /// Multiplies a cell dimension by the zoom factor (rounded, floored at 1).
    private static func zoomed(_ value: Int, _ factor: Double) -> Int {
        factor == 1 ? value : max(1, Int((Double(value) * factor).rounded()))
    }

    // MARK: - Renderable

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let stateStorage = context.stateStorage!
        let lifecycle = context.environment.lifecycle!
        let identity = context.identity

        let (width, height) = (context.availableWidth, context.availableHeight)

        guard width > 0, height > 0 else {
            return FrameBuffer()
        }

        // Read environment values
        let characterSet = context.environment.imageCharacterSet
        let shapeAware = context.environment.imageShapeAware
        // Resolved HERE, against the theme, and not inside the converter: a
        // `.palette` mode may name `.palette.accent`, which has no colour of its
        // own until a palette says so. Resolving before the render cache is
        // consulted is what makes the image follow a theme change — the
        // unresolved mode is identical either side of it, so a cache keyed on
        // that would serve the old colours forever.
        let colorMode = context.environment.imageColorMode.resolved(
            with: context.environment.palette)
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

        // Lifecycle and phase mutations are RENDER-pass side effects. An
        // ancestor that measures by rendering (a Card's container measure, a
        // multi-line Table cell probe) runs this body with `isMeasuring` set —
        // it must not reset a loaded image back to `.loading` on a source
        // change, start a load for a measured-but-never-shown branch (a
        // ViewThatFits rejected candidate), or register appear/disappear
        // handlers for it. The measure pass still reads the current phase below
        // so what's measured is what's drawn.
        if !context.isMeasuring {
            // Declared as a side effect, as `LifecycleModifier` declares its
            // own: the appearance record is per-frame presence, and a
            // memoized row serving its cached cells skips this body — the
            // token then vanishes from the frame's visible set and
            // `endRenderPass` fires the disappear handler for an image still
            // on screen, deleting it from the terminal or cancelling its
            // decode. The memos decline a buffer that declares this.
            context.environment.volatileReadTracker?.recordRenderSideEffect()
            manageLoadLifecycle(
                lifecycle: lifecycle, token: token,
                phaseBox: phaseBox, lastSourceBox: lastSourceBox,
                maxPixelCount: maxPixelCount, urlTimeout: urlTimeout,
                imageStore: context.environment.terminalImageStore)
        }

        // The image renders into the fit box scaled by zoom — mirroring
        // `sizeThatFits`, so what's measured is what's drawn. For a `.viewport`
        // fit the base is the (unzoomed) published viewport, so zooming OUT
        // shrinks the image below the viewport (and zooming IN grows it past it);
        // otherwise the laid-out available size already reflects the zoom.
        // `zoomed` floors at one cell, so even a 1/512 zoom stays renderable.
        // Sanitised by the environment's setter; see `sizeThatFits`.
        let zoom = context.environment.imageZoom
        let renderWidth: Int
        let renderHeight: Int
        if context.environment.imageFitTarget == .viewport,
            let viewport = context.environment.scrollViewportSize {
            renderWidth = Self.zoomed(viewport.width, zoom)
            renderHeight = Self.zoomed(viewport.height, zoom)
        } else {
            renderWidth = width
            renderHeight = height
        }

        // Render based on current phase
        switch phaseBox.value {
        case .loading:
            return renderPlaceholder(
                width: renderWidth,
                height: renderHeight,
                text: placeholderText,
                showSpinner: showSpinner,
                context: context
            )

        case .success(let rawImage):
            // Real pixels first, where the terminal will take them. Falls
            // through to the glyph renderer for every terminal that did not
            // answer the startup handshake, every subtree that asked for
            // glyphs, and every request the protocol cannot express — which is
            // why this is an `if let` and not a branch: the fallback is not an
            // error path, it is the path this framework has always taken.
            if let drawn = renderWithTerminalGraphics(
                rawImage, width: renderWidth, height: renderHeight, context: context)
            {
                return drawn
            }
            return renderImage(
                rawImage,
                width: renderWidth,
                height: renderHeight,
                characterSet: characterSet,
                shapeAware: shapeAware,
                colorMode: colorMode,
                dithering: dithering,
                toneCurve: context.environment.imageToneCurve?.resolved(
                    with: context.environment.palette),
                supersampling: context.environment.imageSupersampling,
                edgeThreshold: context.environment.imageEdgeThreshold,
                edgeContrast: context.environment.imageEdgeContrast,
                contentMode: contentMode,
                aspectRatioOverride: aspectRatioOverride,
                cellAspect: context.environment.imageCellAspect,
                palette: context.environment.palette,
                stateStorage: stateStorage,
                identity: identity
            )

        case .failure(let message):
            return renderError(message, width: renderWidth, height: renderHeight, context: context)
        }
    }
}

// MARK: - Load Lifecycle

extension _ImageCore {

    /// Render-pass-only load management: resets the phase on a source change,
    /// starts the load task on first appearance, and registers the
    /// cancel-on-disappear handler. Split from `renderToBuffer` so the
    /// `!isMeasuring` gate wraps one call (and the body stays within the
    /// function-length limit).
    private func manageLoadLifecycle(
        lifecycle: LifecycleManager,
        token: String,
        phaseBox: StateBox<ImageLoadingPhase>,
        lastSourceBox: StateBox<ImageSource?>,
        maxPixelCount: Int?,
        urlTimeout: Double,
        imageStore: TerminalImageStore?
    ) {
        // Detect source change and force reload
        if let lastSource = lastSourceBox.value, lastSource != source {
            lifecycle.cancelTask(token: token)
            lifecycle.resetAppearance(token: token)
            phaseBox.value = .loading
        }
        // Only on an actual change. `StateBox.value.didSet` invalidates
        // unconditionally — it cannot compare, since `Value` is not constrained
        // to `Equatable` — so re-recording the same source every render asked
        // for a frame that would be identical to the one being drawn. The loop
        // is demand-driven, so that request is honoured: an on-screen `Image`
        // held it at 2% CPU forever, writing zero bytes, because the diff
        // writer correctly found nothing to say. Measured with
        // `Tools/Profiling/idle-image.sh`.
        if lastSourceBox.value != source {
            lastSourceBox.value = source
        }

        // Start loading on first appearance
        if !lifecycle.hasAppeared(token: token) {
            _ = lifecycle.recordAppear(token: token) {}

            let src = source
            lifecycle.startTask(token: token, priority: .userInitiated) {
                // Decode off the main actor (@concurrent guarantees it), then
                // write the box ON it. The box's invalidation SINK is
                // thread-safe, but the value itself is a plain property the
                // render loop reads every frame — assigning a multi-word enum
                // payload from a pool thread raced those reads (a torn read of
                // the CoW pixel array is heap corruption, not a glitch). This
                // is the one place the framework itself wrote @State off-main.
                guard
                    let phase = await Self.loadPhase(
                        source: src, maxPixelCount: maxPixelCount, urlTimeout: urlTimeout)
                else { return }
                await MainActor.run {
                    // Cancellation is observed HERE, not (only) inside the
                    // decode. `loadPhase` returns nil when it notices — but a
                    // `.file` decode is synchronous with no cancellation
                    // points at all, so the flag `cancelTask` sets on a source
                    // change is never seen by it. Without this check the OLD
                    // task publishes its stale result whenever it finishes
                    // second, and the image the user switched away from
                    // replaces the one they switched to (or an error from the
                    // abandoned path lands on a view that loaded fine).
                    //
                    // Last thing before the write, so it also covers a cancel
                    // that arrives during the hop onto the main actor.
                    guard !Task.isCancelled else { return }
                    phaseBox.value = phase
                }
            }
        } else {
            _ = lifecycle.recordAppear(token: token) {}
        }

        // Cancel loading task on disappear — and give the terminal its
        // memory back. A transmitted image is retained by the terminal until
        // something deletes it, and this is the only moment anything knows
        // the picture is not coming back.
        lifecycle.registerDisappear(token: token) { [lifecycle] in
            lifecycle.cancelTask(token: token)
            imageStore?.release(token: token)
        }
    }

    /// Loads and decodes the image, returning the phase to publish — or `nil`
    /// if the load was cancelled, which is not a phase: the view has left the
    /// tree (or its source changed), and a replacement task may already be
    /// running, so publishing anything here would either paint an error into a
    /// view nobody asked about any more or clobber the new load's result.
    ///
    /// Decoding is CPU-bound, so `@concurrent` keeps it off the main actor's
    /// executor no matter what context awaits it — the caller then publishes
    /// the result on the main actor, where every other `@State` write happens.
    @concurrent
    private static func loadPhase(
        source: ImageSource, maxPixelCount: Int?, urlTimeout: Double
    ) async -> ImageLoadingPhase? {
        let loader = PlatformImageLoader()
        do {
            let rawImage: RGBAImage
            switch source {
            case .file(let path):
                rawImage = try loader.loadImage(from: path, maxPixelCount: maxPixelCount)
            case .url(let urlString):
                rawImage = try await loader.loadImage(
                    fromURL: urlString,
                    cache: .shared,
                    timeout: urlTimeout,
                    maxPixelCount: maxPixelCount
                )
            }
            // Store the raw image; conversion happens per render pass.
            return .success(rawImage)
        } catch is CancellationError {
            return nil
        } catch let loadError as ImageLoadError {
            return .failure(loadError.description)
        } catch {
            return .failure(error.localizedDescription)
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
    /// hot spot of the renderer (especially in the shape-aware and
    /// `.braille` modes), and the typical TUIkit redraw cadence —
    /// spinner pulses, focus animations — re-renders an unchanged image
    /// many times per second.
    private func renderImage(  // swiftlint:disable:this function_parameter_count
        _ rawImage: RGBAImage,
        width: Int,
        height: Int,
        characterSet: ASCIICharacterSet,
        shapeAware: Bool,
        colorMode: ASCIIColorMode,
        dithering: DitheringMode,
        toneCurve: ASCIIToneCurve?,
        supersampling: Int?,
        edgeThreshold: Double?,
        edgeContrast: Double,
        contentMode: ContentMode,
        aspectRatioOverride: Double?,
        cellAspect: Double,
        palette: any Palette,
        stateStorage: StateStorage,
        identity: ViewIdentity
    ) -> FrameBuffer {
        let targetSize = ASCIIConverter.targetSize(
            imageWidth: rawImage.width,
            imageHeight: rawImage.height,
            maxWidth: width,
            maxHeight: height,
            contentMode: contentMode,
            overrideAspectRatio: aspectRatioOverride,
            cellAspect: cellAspect
        )

        guard targetSize.width > 0, targetSize.height > 0 else {
            return FrameBuffer()
        }

        // Check the per-view cache; if every conversion input matches,
        // skip the (potentially very expensive) re-conversion.
        let cacheKey = StateStorage.StateKey(identity: identity, propertyIndex: StateIndex.renderCache)
        let cacheBox: StateBox<ImageRenderCache?> = stateStorage.storage(for: cacheKey, default: nil)
        if let cache = cacheBox.value, cache.matches(
            source: source,
            rawImageWidth: rawImage.width,
            rawImageHeight: rawImage.height,
            width: targetSize.width,
            height: targetSize.height,
            characterSet: characterSet,
            shapeAware: shapeAware,
            colorMode: colorMode,
            dithering: dithering,
            toneCurve: toneCurve,
            supersampling: supersampling,
            edgeThreshold: edgeThreshold,
            edgeContrast: edgeContrast,
            contentMode: contentMode,
            aspectRatioOverride: aspectRatioOverride,
            cellAspect: cellAspect
        ) {
            return Self.buffer(for: cache.art, mode: colorMode, palette: palette)
        }

        let converter = ASCIIConverter(
            characterSet: characterSet,
            shapeAware: shapeAware,
            colorMode: colorMode,
            dithering: dithering,
            supersampling: supersampling,
            edgeThreshold: edgeThreshold,
            toneCurve: toneCurve,
            edgeContrast: edgeContrast
        )
        let art = converter.convert(rawImage, width: targetSize.width, height: targetSize.height)

        cacheBox.value = ImageRenderCache(
            source: source,
            rawImageWidth: rawImage.width,
            rawImageHeight: rawImage.height,
            width: targetSize.width,
            height: targetSize.height,
            characterSet: characterSet,
            shapeAware: shapeAware,
            colorMode: colorMode,
            dithering: dithering,
            toneCurve: toneCurve,
            supersampling: supersampling,
            edgeThreshold: edgeThreshold,
            edgeContrast: edgeContrast,
            contentMode: contentMode,
            aspectRatioOverride: aspectRatioOverride,
            cellAspect: cellAspect,
            art: art
        )

        return Self.buffer(for: art, mode: colorMode, palette: palette)
    }

    /// The buffer a converted picture becomes: its lines, inked if the mode needs it,
    /// and its coverage as claims.
    ///
    /// **The claims are the glyph path's half of the claim/bytes pairing.** Every cell
    /// the converter drew at less than full coverage states its colour at full strength
    /// — an emitter has no backdrop to composite against — and says here which cells owe
    /// a blend, so the compositor resolves them against what is actually behind the
    /// image rather than against the black the flatten used to assume (§42).
    ///
    /// A fully opaque picture's `coverage` is empty, so this is one `isEmpty` for the
    /// overwhelming majority of images and no allocation at all.
    private static func buffer(
        for art: ASCIIArt, mode: ASCIIColorMode, palette: any Palette
    ) -> FrameBuffer {
        var buffer = FrameBuffer(lines: inked(art.lines, mode: mode, palette: palette))
        buffer.opacityRegions += art.claims
        return buffer
    }

    /// Mono output, given the theme's ink and paper.
    ///
    /// ``ASCIIColorMode/mono`` emits no colour at all — that is the point of it,
    /// and what makes it work on a terminal that has none. Inside an app that
    /// paints its own background, though, "no colour" is not black and white:
    /// it is the TERMINAL's defaults, over a page the app has already painted.
    /// Under a dark theme with a dark terminal default that is ink on ink, and
    /// the image simply does not appear.
    ///
    /// Applied here rather than in the converter, and AFTER the render cache,
    /// because the cache is not keyed on the palette: baking the colours into
    /// the cached lines would serve the old theme's ink forever. Same reason
    /// ``ASCIIColorMode/resolved(with:)`` is applied before it.
    private static func inked(
        _ lines: [String], mode: ASCIIColorMode, palette: any Palette
    ) -> [String] {
        guard mode == .mono else { return lines }
        return lines.map {
            ANSIRenderer.colorize(
                $0, foreground: palette.foreground, background: palette.background)
        }
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

        // Build placeholder content lines, each with the colour it is to be drawn
        // in rather than already drawn in it: `centerContent` is the only thing that
        // knows where a centred line lands, so it is the only thing that can claim
        // the cells (§68.3).
        var contentLines: [(text: String, ink: Color)] = []

        if showSpinner {
            contentLines.append((text: "⠋", ink: palette.accent))
        }

        if let text {
            contentLines.append((text: text, ink: palette.foregroundSecondary))
        }

        if contentLines.isEmpty {
            contentLines.append((text: "Loading...", ink: palette.foregroundSecondary))
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
        return centerContent(
            [(text: "Error: \(message)", ink: palette.error)], width: width, height: height)
    }

    /// Centers content lines vertically and horizontally within the given
    /// dimensions, cutting any line wider than `width` to it (and closing the
    /// styling the cut interrupts).
    ///
    /// The returned buffer's declared `width` is therefore an upper bound on
    /// every row it carries — which the general clamp assumes and cannot check
    /// here (see the clip below). Rows may be NARROWER than `width` (the
    /// centring pads on the left only), so the buffer stays non-uniform: do not
    /// pass `uniformWidth: true`, or `appendHorizontally` skips the pad for a
    /// centred row and lands the next sibling mid-box.
    private func centerContent(
        _ contentLines: [(text: String, ink: Color)], width: Int, height: Int
    ) -> FrameBuffer {
        let emptyLine = String(repeating: " ", count: width)
        var lines = [String](repeating: emptyLine, count: height)
        var claims: [OpacityRegion] = []

        let startY = max(0, (height - contentLines.count) / 2)

        for (i, content) in contentLines.enumerated() {
            let y = startY + i
            guard y < height else { break }

            // Drawn here, in the opaque spelling, with the alpha claimed below once
            // the pad and any cut have decided which cells it covers. A placeholder's
            // accent and an error's `palette.error` both reached the emitter with a
            // faded palette's alpha on them before this (§68.3).
            var line = ANSIRenderer.colorize(
                content.text, foreground: content.ink.opaqueSpelling)
            var visibleWidth = line.strippedLength

            // Cut it, rather than merely failing to pad it. "Loading..." is 10
            // cells and an "Error: <path>" far more, while this buffer declares
            // only `width` columns — and that is a lie the general net cannot
            // catch: every ancestor clamps with `clamped(toWidth:height:)`,
            // whose `self.width <= maxWidth` fast path TRUSTS the declaration,
            // and `width` here IS that clamp target (`availableWidth`). The
            // over-wide row then reaches `appendHorizontally`, which measures
            // the row's REAL width and starts the next `HStack` sibling past
            // it — shearing that one row from the rest of the same box. Same
            // clip primitive as `clamped` and `_ListCore.fitted`: counts cells,
            // never splits a wide glyph, keeps the styling in force.
            if visibleWidth > width {
                let (cut, cutWidth) = line.ansiAwarePrefixWithWidth(
                    visibleCount: width, knownVisibleWidth: visibleWidth)
                // Closed, because the cut lands mid-run and drops the reset
                // `colorize` had put at the end — the clip primitive closes an
                // open hyperlink but never SGR. Without this the placeholder's
                // colour stays in force and paints whatever the row holds next:
                // the very `HStack` sibling this clip just pulled back to the
                // box edge. `BorderRenderer.contentLine` closes its clip the
                // same way; `_ListCore.fitted` gets away without it only
                // because it pads with plain spaces, where a leaked foreground
                // cannot be seen. The reset is stripped by every width scan, so
                // it costs no columns.
                line = cut + ANSIRenderer.reset
                visibleWidth = cutWidth
            }

            // Still `max(0,)`: the clip above makes this non-negative, and
            // `String(repeating:count:)` traps if it ever stops being.
            let padding = max(0, (width - visibleWidth) / 2)
            let padded = String(repeating: " ", count: padding) + line
            lines[y] = padded
            // The cells the glyphs actually took: past the pad, and `visibleWidth`
            // wide, which the clip above has already reduced if it cut the line. The
            // pad itself is a bare space and claims nothing — an ink claim over one
            // lets what is behind show through where this drew blank.
            if let claim = OpacityRegion.claim(
                offsetX: padding, offsetY: y, width: visibleWidth, height: 1,
                ink: content.ink)
            {
                claims.append(claim)
            }
        }

        var buffer = FrameBuffer(lines: lines, width: width)
        buffer.opacityRegions = claims
        return buffer
    }
}

// MARK: - Drawing with the terminal's own graphics

extension _ImageCore {

    /// The image as **real pixels**, if this terminal will place one in its
    /// cell grid — or `nil`, which means "draw it out of glyphs, as always".
    ///
    /// What comes back is ordinary text: `columns` × `rows` cells of Unicode
    /// placeholders that the terminal replaces with parts of the picture. It
    /// measures, clips, scrolls, composites and diffs exactly like the glyph
    /// rendering it replaces, so nothing downstream of here knows the
    /// difference. See ``KittyGraphics``.
    ///
    /// ## The five gates, and why each is separate
    ///
    /// - **`isSupported`** — the startup handshake's answer. Default `false`,
    ///   so a terminal nobody asked draws glyphs.
    /// - **`terminalGraphics`** — the app's preference. The glyph renderer is
    ///   a look and not only a fallback; see ``View/terminalGraphics(_:)``.
    /// - **`!isMeasuring`** — transmitting is a side effect, and a measure
    ///   pass that renders (a Card sizing its container, a Table probing a
    ///   multi-line cell) must not put an image in the terminal for a branch
    ///   that may never be drawn. The measured SIZE is unaffected: both paths
    ///   produce the same cell box, because both ask
    ///   ``ASCIIConverter/targetSize(imageWidth:imageHeight:maxWidth:maxHeight:contentMode:overrideAspectRatio:cellAspect:)``.
    /// - **a store** — `nil` in a headless render, where there is no terminal
    ///   to transmit to.
    /// - **the store's own answer** — `nil` for an extent past what
    ///   placeholders can address (297 cells; there is no combining mark for
    ///   the 298th column).
    fileprivate func renderWithTerminalGraphics(
        _ rawImage: RGBAImage, width: Int, height: Int, context: RenderContext
    ) -> FrameBuffer? {
        guard KittyGraphics.isSupported,
            context.environment.terminalGraphics,
            let store = context.environment.terminalImageStore,
            rawImage.width > 0, rawImage.height > 0
        else { return nil }

        // The same cell box the glyph renderer would fill, from the same
        // function — so switching renderers cannot move the image or change
        // what the layout around it was told.
        let target = ASCIIConverter.targetSize(
            imageWidth: rawImage.width, imageHeight: rawImage.height,
            maxWidth: width, maxHeight: height,
            contentMode: context.environment.imageContentMode,
            overrideAspectRatio: context.environment.imageAspectRatio,
            cellAspect: context.environment.imageCellAspect)
        guard target.width > 0, target.height > 0 else { return nil }

        // A measure pass reads a BOX, not a picture. Falling through to the
        // glyph renderer here — which is what bailing on `isMeasuring` did —
        // paid a full glyph conversion for every new size a measure-by-render
        // parent (a Button's label, a Section, a stack holding a Spacer)
        // probed, and threw the ink away: the render pass then transmitted
        // pixels and never looked at it. The box is the contract; blank
        // cells are the cheapest thing that has it.
        if context.isMeasuring {
            return FrameBuffer(
                lines: Array(repeating: String(repeating: " ", count: target.width), count: target.height))
        }

        // Never transmit more pixels than the picture HAS. The terminal fits
        // the image to the placement rectangle, so upscaling before
        // transmission buys nothing and costs everything: on a 135x48 grid of
        // 16x34-pixel cells at zoom 2 the unclamped size is 4320x3264, which
        // is 56 MB of RGBA resampled UP from a 1101x1080 source. Zoom is what
        // makes this reachable, and zoom is exactly when an app feels slow.
        //
        // Clamped by a single factor rather than per axis, so a source whose
        // aspect differs from the box is not stretched on the way out.
        let cell = context.environment.imageCellPixels
        let wantedWidth = target.width * cell.width
        let wantedHeight = target.height * cell.height
        let shrink = min(
            1.0,
            min(
                Double(rawImage.width) / Double(max(1, wantedWidth)),
                Double(rawImage.height) / Double(max(1, wantedHeight))))
        let pixelWidth = max(1, Int((Double(wantedWidth) * shrink).rounded()))
        let pixelHeight = max(1, Int((Double(wantedHeight) * shrink).rounded()))

        // The colour settings apply to a real picture as much as to a field of
        // glyphs — more so, since there is no character in the way — and they
        // come from the same converter the glyph path builds, so the two
        // renderings of one picture agree about what the picture IS. The
        // settings that only decide which CHARACTER to draw are not consulted;
        // see `ASCIIConverter.recoloured(_:width:height:)`.
        let colorMode = context.environment.imageColorMode.resolved(
            with: context.environment.palette)
        let toneCurve = context.environment.imageToneCurve?.resolved(
            with: context.environment.palette)
        let edgeContrast = context.environment.imageEdgeContrast
        let dithering = context.environment.imageDithering
        // Mono's two colours, which pixels have to be TOLD. The character
        // renderer states them after the fact — `inked(_:mode:palette:)`, run
        // after the render cache so a theme change re-colours a cached
        // conversion — and pixels have nothing to state them onto: a pixel is a
        // colour or it is nothing. So they are baked in, and therefore they are
        // in the signature: change the theme and the picture is genuinely a
        // different picture.
        let palette = context.environment.palette
        let ink = Self.rgba(palette.foreground, in: palette) ?? RGBA(r: 255, g: 255, b: 255)
        let paper = Self.rgba(palette.background, in: palette) ?? RGBA(r: 0, g: 0, b: 0)

        // The transmitted resolution, not the cell box: two boxes that resample
        // to the same pixels are the same picture, and the store answers the
        // second with a placement instead of megabytes.
        let signature = TerminalImageSignature(
            source: source,
            rawWidth: rawImage.width, rawHeight: rawImage.height,
            pixelWidth: pixelWidth, pixelHeight: pixelHeight,
            colorMode: colorMode, toneCurve: toneCurve,
            edgeContrast: edgeContrast, dithering: dithering,
            monoInk: ink, monoPaper: paper)

        guard
            let lines = store.placeholderRows(
                token: "image-\(context.identity.path)", signature: signature,
                columns: target.width, rows: target.height,
                pixels: {
                    // Only on a miss: this resamples and recolours the decoded
                    // image and can be megabytes. The common case, by a wide
                    // margin, is that nothing has changed since last frame.
                    let converter = ASCIIConverter(
                        colorMode: colorMode, dithering: dithering,
                        toneCurve: toneCurve, edgeContrast: edgeContrast)
                    let packed = Self.pixelBytes(
                        converter.recoloured(
                            rawImage, width: pixelWidth, height: pixelHeight,
                            monoInk: ink, monoPaper: paper))
                    return (packed.bytes, packed.format, pixelWidth, pixelHeight)
                })
        else { return nil }

        // Every row is exactly `target.width` cells by construction — one
        // placeholder each, and `KittyGraphics.placeholderRows` builds nothing
        // else. Saying so costs nothing and saves every consumer of this buffer
        // re-deriving it EVERY FRAME: measuring a row means walking its scalars
        // through grapheme segmentation, and an image row is four scalars per
        // cell (the placeholder and three marks) with no ASCII fast path to take.
        return FrameBuffer(
            lines: lines, width: target.width, uniformWidth: true,
            lineWidths: [Int](repeating: target.width, count: lines.count))
    }

    /// A palette colour as pixels, or `nil` for a semantic colour that has no
    /// RGB even after resolution.
    fileprivate static func rgba(_ color: Color, in palette: any Palette) -> RGBA? {
        // Alpha is not carried, for the reason `ASCIIPalette.init` states: this is
        // a colour being handed to the image pipeline as a MATCHING candidate or a
        // recolouring target, and transparency is not an axis of either. An
        // image's own transparency comes from its alpha channel instead.
        guard let components = color.resolve(with: palette).rgbComponents else { return nil }
        return RGBA(r: components.red, g: components.green, b: components.blue)
    }

    /// An ``RGBAImage`` as the flat byte run the protocol wants, in the
    /// narrowest format that says everything the picture has to say.
    ///
    /// A photograph has no transparency, and three bytes a pixel rather than
    /// four is a quarter off a multi-megabyte transmission — which is a
    /// quarter off the pause on the frame that first shows it. The scan for an
    /// alpha channel costs one pass over pixels that are about to be copied
    /// anyway.
    ///
    /// Written through `unsafeUninitializedCapacity` rather than an append a
    /// channel: a full-screen image at a Retina cell is over two million
    /// pixels, and eight million bounds-checked appends is a visible pause of
    /// its own.
    fileprivate static func pixelBytes(
        _ image: RGBAImage
    ) -> (bytes: [UInt8], format: KittyGraphics.PixelFormat) {
        let pixels = image.pixels
        let format: KittyGraphics.PixelFormat =
            pixels.contains { $0.a != .max } ? .rgba : .rgb
        let stride = format.stride
        let capacity = pixels.count * stride
        let bytes = [UInt8](unsafeUninitializedCapacity: capacity) { buffer, initialized in
            var index = 0
            for pixel in pixels {
                buffer[index] = pixel.r
                buffer[index + 1] = pixel.g
                buffer[index + 2] = pixel.b
                if stride == 4 { buffer[index + 3] = pixel.a }
                index += stride
            }
            initialized = index
        }
        return (bytes, format)
    }
}

// MARK: - Coverage as claims

extension ASCIIArt {
    /// What this picture's cells owe the compositor, in the buffer's own coordinates.
    ///
    /// The glyph path's half of the claim/bytes pairing: every cell the converter drew
    /// at less than full coverage states its colour at full strength — an emitter has no
    /// backdrop to composite against — and this says which cells owe a blend, so the
    /// compositor resolves them against what is actually behind the image rather than
    /// against the black the flatten used to assume (§42).
    ///
    /// A run per rectangle, one row tall, which is what `CoverageRun` already coalesced
    /// to. `[]` for a fully opaque picture, which is nearly every picture: one `isEmpty`
    /// and no allocation.
    ///
    /// Its own named property rather than four lines inside `_ImageCore` because
    /// `_ImageCore` is private and this is the only part of it worth asserting directly
    /// — the raster view has no in-memory source, so the end-to-end path cannot be
    /// rendered from pixels in a test.
    var claims: [OpacityRegion] {
        coverage.compactMap { run in
            OpacityRegion.claim(
                offsetX: run.columns.lowerBound, offsetY: run.line,
                width: run.columns.count, height: 1, inkAlpha: run.ink, fieldAlpha: run.field)
        }
    }
}
