//  🖥️ TUIKit — Terminal UI Kit for Swift
//  OpacityModifier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling
import TUIkitView

// MARK: - opacity

extension View {
    /// Sets the transparency of this view. Matches SwiftUI's `opacity(_:)`.
    ///
    /// A terminal cell is opaque — it holds one character in one foreground
    /// colour on one background colour, and there is no alpha channel to write.
    /// So this is real compositing done with the two things a cell does have:
    /// the subtree renders to its own layer, and where that layer is drawn onto
    /// what is behind it, each cell is resolved against the cell beneath.
    ///
    /// ```swift
    /// Text("Not yet available")
    ///     .opacity(0.4)
    /// ```
    ///
    /// The blend preserves hue: a red heading at `0.5` stays recognisably red,
    /// halfway to what it sits on, rather than flattening to grey. Text with no
    /// colour of its own blends from the palette's foreground, so a whole
    /// subtree fades evenly whether or not its parts were styled. Nesting
    /// multiplies, as in SwiftUI: `0.5` inside `0.5` shows at `0.25`.
    ///
    /// > Important: Colours compose exactly; **characters cannot**. Two
    ///   characters cannot share one cell at half strength each, so where a
    ///   character behind this view contests the same cell, alpha becomes a
    ///   decision rather than a mix: **at or above `0.5` this view's character
    ///   is drawn, and below it the character behind shows instead** — colours
    ///   keep blending at every alpha; only the choice of character snaps.
    ///   Text over different text therefore swaps characters at the midpoint
    ///   rather than dissolving through it — there is no way around that in a
    ///   cell grid — though where the characters MATCH there is no contest and
    ///   the cell cross-fades exactly, so a colour change on unchanged text
    ///   never snaps.
    ///   Over anything blank there is no contest and nothing snaps: this
    ///   view's characters simply fade all the way out, and `opacity(0)`
    ///   genuinely reveals what is behind, rather than painting an
    ///   invisible-coloured rectangle over it.
    ///
    /// > Note: A space is not a character for this purpose. A faded view's
    ///   blank cells composite their background and let what is behind them
    ///   show through, so fading a `VStack` does not blank the rectangle it
    ///   occupies. And what is behind keeps its own foreground colour: a
    ///   translucent pane over text tints the surface under the text, not the
    ///   text.
    ///
    /// Changed inside ``withAnimation(_:_:)``, it fades rather than jumps —
    /// this view is ``Animatable``, and opacity is what it interpolates:
    ///
    /// ```swift
    /// Text("Saved")
    ///     .opacity(hasSaved ? 1 : 0)
    ///     .animation(.easeInOut(duration: 0.4), value: hasSaved)
    /// ```
    ///
    /// - Parameter opacity: `0` (invisible) through `1` (unchanged).
    /// - Returns: A view composited at that opacity over whatever it is drawn on.
    public func opacity(_ opacity: Double) -> some View {
        _OpacityView(content: self, opacity: opacity)
    }
}

/// Marks everything `content` draws as translucent, for the compositor to
/// resolve against what is behind it. See ``FrameBuffer/resolvingOpacity(over:at:surface:palette:)``.
struct _OpacityView<Content: View>: View {
    let content: Content
    var opacity: Double

    var body: Never {
        fatalError("_OpacityView renders via Renderable")
    }
}

extension _OpacityView: Animatable {
    /// Opacity is the one continuous thing about this view, so a change to it
    /// inside ``withAnimation(_:_:)`` is a fade rather than a jump.
    ///
    /// A `var` rather than a `let` above only so this setter has somewhere to
    /// write; nothing else mutates it.
    var animatableData: Double {
        get { opacity }
        set { opacity = newValue }
    }
}

extension _OpacityView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = TUIkit.renderToBuffer(content, context: context)
        // `isEmpty` asks about the LINES, and a subtree can draw nothing in
        // flow while drawing plenty in an overlay: `.offset` and `.position`
        // return a placeholder of zero-width lines and put the content in a
        // layer. Short-circuiting on that made `Text("x").offset(x: 2)
        // .opacity(0.5)` a complete no-op — the fade never ran at all.
        guard !buffer.isEmpty || !buffer.overlays.isEmpty else { return buffer }

        // A repeating fade is stamped as the WHOLE cycle rather than as this
        // frame's value, so the compositor can colour every phase once and hand
        // the run loop the lot. Otherwise a fade that never ends costs a render
        // pass for as long as the view is on screen.
        let repeating = cycling(context)
        let factor = min(max(repeating?.current ?? opacity, 0), 1)
        // Fully opaque is the identity, and taking it means an untouched
        // subtree cannot be changed by this code path at all.
        guard factor < 1 || repeating != nil else { return buffer }

        buffer.opacityRegions = Self.fading(
            buffer.opacityRegions, by: factor, cycle: repeating?.cycle,
            wholeOf: buffer, appendingRectangle: !buffer.isEmpty)
        // A layer is its own picture at its own place, so it gets the cycle
        // too: the compositor bakes its phases where the layer lands.
        buffer.overlays = Self.fadingOverlays(
            buffer.overlays, by: factor, cycle: repeating?.cycle)
        return buffer
    }

    /// The repeating fade this view is on, if it is on one — the values it
    /// passes through, and the one this frame is drawn at.
    ///
    /// Declining leaves the ordinary path, which renders per frame. That is
    /// correct, just not cheap, and is what a cycle too long to hold as frames
    /// falls back to.
    private func cycling(_ context: RenderContext) -> (cycle: OpacityCycle, current: Double)? {
        guard !context.isMeasuring, let storage = context.stateStorage else { return nil }
        let key = AnimationStore.Key(
            identity: context.identity, owner: ObjectIdentifier(Self.self))
        guard
            let cycle: AnimationCycle<Double> = storage.animations.cycle(
                for: key,
                nowNanos: context.environment.frameNowNanos,
                tick: context.environment.animationTick)
        else { return nil }
        // Told now rather than after the bake: the bake happens at the
        // compositor, frames later in the same pass and out of this view's
        // reach, and a cycle still marked "needs rendering" wakes the loop
        // every tick regardless of what the compositor went on to produce.
        //
        // The compositor may still decline — phases that disagree about the
        // shape of a row cannot be a run — in which case the fade freezes at
        // the value drawn. That is the one thing this ordering costs, and it is
        // bounded: `AnimatedBufferCycle` only declines on a width change, and a
        // re-colouring cannot change a width.
        storage.animations.noteServedByRuns(key)
        return (OpacityCycle(phases: cycle.values, clock: .cursor), cycle.current)
    }

    /// `regions` multiplied by `factor`, with this view's own rectangle after
    /// them.
    ///
    /// **Nesting multiplies**, as it does in SwiftUI: a `0.5` group inside a
    /// `0.5` group shows at `0.25`. Doing it here rather than at the composite
    /// is what makes that fall out — an inner region already carries the
    /// product of everything inside it, so scaling by this view's factor is the
    /// whole of the rule.
    ///
    /// The order is load-bearing: the resolution takes the FIRST region
    /// covering a cell, so the inner product has to come before the outer
    /// rectangle that also covers it. See
    /// ``FrameBuffer/resolvingOpacity(over:at:surface:palette:)``.
    static func fading(
        _ regions: [OpacityRegion], by factor: Double, cycle: OpacityCycle?,
        wholeOf buffer: FrameBuffer, appendingRectangle: Bool
    ) -> [OpacityRegion] {
        var result = regions.map { region -> OpacityRegion in
            var scaled = region
            scaled.opacity *= factor
            // An inner cycle scales with everything else about the inner
            // region: a breathing badge inside a half-faded panel breathes
            // between half the values it would alone.
            scaled.cycle = region.cycle?.scaled(by: factor)
            return scaled
        }
        guard appendingRectangle else { return result }
        // The whole of what this subtree drew. Ragged lines are not a problem:
        // a rectangle claiming columns a line does not reach resolves to
        // nothing there, because there is no source cell to blend.
        result.append(
            OpacityRegion(
                offsetX: 0, offsetY: 0, width: buffer.width, height: buffer.lines.count,
                opacity: factor, cycle: cycle))
        return result
    }
}

extension _OpacityView {
    /// `overlays`, with the ones this view actually DREW faded to match its
    /// lines — and the ones it merely hosts left alone.
    ///
    /// The distinction is ``OverlayLayer/isScreenLevel``, and it is the same one
    /// `.hidden()` and `.allowsHitTesting(false)` turn on:
    ///
    /// - an **anchored** layer — an `.offset`/`.position` child, a popover — is
    ///   this subtree's own drawing, displaced. Fading the subtree without
    ///   fading it left the displaced part at full strength beside faded
    ///   siblings.
    /// - a **centred** layer is a `.sheet`/`.alert` panel over the whole
    ///   screen. `.opacity` recolours what this view draws; it is not a way to
    ///   dim a dialog the view opened, any more than it is in SwiftUI, where
    ///   the sheet is hosted by the window and a modifier on the presenter
    ///   cannot reach it.
    ///
    /// Recursive, because a layer's own content can carry layers.
    ///
    /// A layer is marked rather than faded, for the same reason the lines are:
    /// where it lands is where what is behind it is known, and `composited`
    /// lifts an overlay's opacity regions along with the rest of its payload.
    static func fadingOverlays(
        _ overlays: [OverlayLayer], by factor: Double, cycle: OpacityCycle? = nil
    ) -> [OverlayLayer] {
        guard factor < 1 || cycle != nil else { return overlays }
        return overlays.map { layer in
            guard !layer.isScreenLevel else { return layer }
            var faded = layer
            faded.content.opacityRegions = fading(
                layer.content.opacityRegions, by: factor, cycle: cycle,
                wholeOf: layer.content, appendingRectangle: !layer.content.isEmpty)
            faded.content.overlays = fadingOverlays(
                layer.content.overlays, by: factor, cycle: cycle)
            return faded
        }
    }
}

/// The colour arithmetic behind ``View/opacity(_:)``, kept out of
/// the generic view so there is one copy of it and tests can reach it.
enum OpacityFade {
    /// Fades every colour in `line` toward `surface`.
    ///
    /// A thin face on ``SGRColorRewrite``, which is the general form: every
    /// colour effect in the framework is the same walk over the same escape
    /// sequences with a different function of the colour.
    static func fading(
        _ line: String, by factor: Double, over surface: Color, defaultForeground: Color
    ) -> String {
        SGRColorRewrite.rewriting(
            line, defaultForeground: defaultForeground, defaultBackground: surface
        ) { $0.compositing(factor, over: surface) }
    }
}

/// Rewrites every colour a rendered line names, leaving everything else — bold,
/// dim, underline, inverse, cursor moves — exactly as it was.
///
/// The one place that knows how an SGR sequence carries a colour: the basic
/// 30–37 / 90–97 forms and their background twins, the extended `38;5;n` and
/// `38;2;r;g;b`, and the "default" 39 / 49 (which are the palette's own colours
/// here, so they transform rather than snapping back to full strength).
///
/// Everything that changes how a subtree *looks* without changing what it draws
/// goes through here — opacity, brightness, contrast, saturation, grayscale,
/// inversion, hue rotation, transitions' fades. Each is a function from colour
/// to colour; none of them has to learn ANSI.
enum SGRColorRewrite {
    /// `line` with `transform` applied to every colour it names.
    ///
    /// - Parameters:
    ///   - line: A rendered line, escapes and all.
    ///   - defaultForeground: What `39` (default foreground) means here.
    ///   - defaultBackground: What `49` (default background) means here.
    ///   - transform: The colour effect. Called with resolved colours only.
    static func rewriting(
        _ line: String, defaultForeground: Color, defaultBackground: Color,
        transform: (Color) -> Color
    ) -> String {
        var result = ""
        for segment in line.ansiSegments() {
            switch segment {
            case .visible(let character):
                result.append(character)
            case .ansi(let sequence, _):
                result += Self.rewritingSGR(
                    sequence, defaultForeground: defaultForeground,
                    defaultBackground: defaultBackground, transform: transform)
            }
        }
        return result
    }

    /// One escape sequence, transformed if it is an SGR that names a colour.
    private static func rewritingSGR(
        _ sequence: String, defaultForeground: Color, defaultBackground: Color,
        transform: (Color) -> Color
    ) -> String {
        // Only SGR (`ESC [ … m`) carries colour; anything else passes through
        // untouched rather than being guessed at.
        guard sequence.hasPrefix("\u{1B}["), sequence.hasSuffix("m") else { return sequence }
        let body = sequence.dropFirst(2).dropLast()
        let parameters = body.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        guard !parameters.isEmpty else { return sequence }

        var rewritten: [String] = []
        var index = 0
        while index < parameters.count {
            let parameter = Int(parameters[index]) ?? 0
            switch parameter {
            case 38, 48:
                // Extended colour: `38;5;n` or `38;2;r;g;b` (48 for background).
                let (color, consumed) = Self.extendedColor(parameters, from: index)
                if let color {
                    let faded = transform(color)
                    rewritten += parameter == 38
                        ? ANSIRenderer.foregroundCodes(for: faded)
                        : ANSIRenderer.backgroundCodes(for: faded)
                } else {
                    rewritten.append(parameters[index])
                }
                index += consumed
                continue
            case 30...37, 90...97, 40...47, 100...107:
                rewritten += Self.rewrittenBasic(parameter, transform: transform)
            case 39:
                // "Default foreground" — which IS the palette foreground
                // here, so it transforms rather than snapping back to full
                // strength.
                rewritten += ANSIRenderer.foregroundCodes(for: transform(defaultForeground))
            case 49:
                rewritten += ANSIRenderer.backgroundCodes(for: transform(defaultBackground))
            default:
                // 0 (reset), 1 (bold), 2 (dim), 4 (underline), 7 (inverse), …
                rewritten.append(parameters[index])
            }
            index += 1
        }
        return "\u{1B}[" + rewritten.joined(separator: ";") + "m"
    }

    /// Which colour an SGR parameter set, for ``readingColors(_:_:)``.
    enum ColorSlot {
        case foreground
        case background
        /// SGR 0 — both colours back to the terminal's default at once.
        case reset
    }

    /// Reports every colour `sequence` names, in order, WITHOUT rewriting it.
    ///
    /// The reading half of ``rewriting(_:defaultForeground:defaultBackground:transform:)``,
    /// sharing its tables rather than repeating them: the same 38/48 extended
    /// forms, the same basic 30–37 / 90–97 ladder, the same 39/49 defaults.
    /// A caller that has to know what a cell IS drawn in — opacity resolution,
    /// which blends against what is behind the cell — needs the parse without
    /// the rewrite.
    ///
    /// `nil` in the callback means the terminal's default, which is what 39 and
    /// 49 select; the caller decides what that means for it.
    static func readingColors(_ sequence: String, _ report: (ColorSlot, Color?) -> Void) {
        guard sequence.hasPrefix("\u{1B}["), sequence.hasSuffix("m") else { return }
        let body = sequence.dropFirst(2).dropLast()
        let parameters = body.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        while index < parameters.count {
            // An empty parameter is 0 — `ESC[m` and `ESC[;m` are both resets —
            // which is the same reading `rewritingSGR` takes.
            let parameter = Int(parameters[index]) ?? 0
            switch parameter {
            case 0:
                report(.reset, nil)
            case 38, 48:
                let (color, consumed) = Self.extendedColor(parameters, from: index)
                // An unparseable extended form is left alone by the rewrite, so
                // it is left unreported here: guessing at it would be worse than
                // treating the cell as unchanged.
                if let color { report(parameter == 38 ? .foreground : .background, color) }
                index += consumed
                continue
            case 30...37, 90...97, 40...47, 100...107:
                let isBackground = (40...47).contains(parameter) || (100...107).contains(parameter)
                let isBright = parameter >= 90
                let base = parameter - (isBright ? (isBackground ? 100 : 90) : (isBackground ? 40 : 30))
                if base >= 0, base < Self.basicColors.count {
                    let (standard, bright) = Self.basicColors[base]
                    report(isBackground ? .background : .foreground, isBright ? bright : standard)
                }
            case 39:
                report(.foreground, nil)
            case 49:
                report(.background, nil)
            default:
                break
            }
            index += 1
        }
    }

    /// The colour named by `38;5;n` / `38;2;r;g;b` (or the `48` background
    /// forms) at `index`, and how many parameters it spans.
    private static func extendedColor(
        _ parameters: [String], from index: Int
    ) -> (Color?, consumed: Int) {
        guard index + 1 < parameters.count else { return (nil, 1) }
        switch parameters[index + 1] {
        case "5":
            guard index + 2 < parameters.count, let value = UInt8(parameters[index + 2]) else {
                return (nil, 1)
            }
            return (Color.palette(value), 3)
        case "2":
            guard index + 4 < parameters.count,
                let red = UInt8(parameters[index + 2]),
                let green = UInt8(parameters[index + 3]),
                let blue = UInt8(parameters[index + 4])
            else { return (nil, 1) }
            return (Color.rgb(red, green, blue), 5)
        default:
            return (nil, 1)
        }
    }

    /// The eight named colours in SGR order, standard and bright, so a code's
    /// last digit indexes straight into them.
    private static let basicColors: [(standard: Color, bright: Color)] = [
        (.black, .brightBlack), (.red, .brightRed), (.green, .brightGreen),
        (.yellow, .brightYellow), (.blue, .brightBlue), (.magenta, .brightMagenta),
        (.cyan, .brightCyan), (.white, .brightWhite),
    ]

    /// A basic (30–37 / 90–97) or background (40–47 / 100–107) colour code,
    /// faded. The named colours have no fixed RGB — a terminal's palette
    /// decides — so they are faded via their standard xterm values, which is
    /// what the 256-cube downsampling already assumes.
    private static func rewrittenBasic(
        _ parameter: Int, transform: (Color) -> Color
    ) -> [String] {
        let isBackground = (40...47).contains(parameter) || (100...107).contains(parameter)
        let isBright = parameter >= 90
        let base = parameter - (isBright ? (isBackground ? 100 : 90) : (isBackground ? 40 : 30))
        guard base >= 0, base < Self.basicColors.count else { return ["\(parameter)"] }
        let (standard, bright) = Self.basicColors[base]
        let faded = transform(isBright ? bright : standard)
        return isBackground
            ? ANSIRenderer.backgroundCodes(for: faded)
            : ANSIRenderer.foregroundCodes(for: faded)
    }
}

extension _OpacityView: Layoutable {
    /// Fading rewrites colours in place: same characters, same cells, same
    /// size. An invisible view still occupies its space, as in SwiftUI.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}
