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
    /// A terminal cell is opaque — it holds one character in one colour, and
    /// there is no alpha channel to write. What there IS, is the colour itself:
    /// so opacity blends every colour the subtree draws toward the background,
    /// by `1 - opacity`. At `1` nothing changes; at `0` everything reaches the
    /// background exactly and the subtree becomes invisible while still
    /// occupying its space — which is what SwiftUI's `opacity(0)` does too.
    ///
    /// ```swift
    /// Text("Not yet available")
    ///     .opacity(0.4)
    /// ```
    ///
    /// The blend preserves hue: a red heading at `0.5` stays recognisably red,
    /// halfway to the background, rather than flattening to grey. Text with no
    /// colour of its own blends from the palette's foreground, so a whole
    /// subtree fades evenly whether or not its parts were styled.
    ///
    /// > Note: This is a *blend*, not compositing. It cannot see what is behind
    ///   the view — a terminal has no layers below the cell — so it blends
    ///   toward the palette background rather than toward whatever the view
    ///   happens to sit on. The two agree except over a non-background fill.
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
    /// - Returns: A view whose colours are blended toward the background.
    public func opacity(_ opacity: Double) -> some View {
        _OpacityView(content: self, opacity: opacity)
    }
}

/// Blends everything `content` draws toward the palette background.
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
        let buffer = TUIkit.renderToBuffer(content, context: context)
        // `isEmpty` asks about the LINES, and a subtree can draw nothing in
        // flow while drawing plenty in an overlay: `.offset` and `.position`
        // return a placeholder of zero-width lines and put the content in a
        // layer. Short-circuiting on that made `Text("x").offset(x: 2)
        // .opacity(0.5)` a complete no-op — the fade never ran at all.
        guard !buffer.isEmpty || !buffer.overlays.isEmpty else { return buffer }

        // Resolve first: a semantic colour makes `opacity(_:over:)` a silent
        // no-op and makes `ANSIRenderer` trap outright.
        let palette = context.environment.palette
        let surface = palette.background.resolve(with: palette)
        let defaultForeground = palette.foreground.resolve(with: palette)

        // Nothing is injected and nothing is appended: every run the renderer
        // emits already names its own colour and ends in a reset, so rewriting
        // the colours it named is enough to fade all of it. `OpacityTests`
        // pins that precondition across the view surface.
        func faded(by factor: Double) -> [String] {
            let clamped = min(max(factor, 0), 1)
            // Fully opaque is the identity, and taking it means an untouched
            // subtree cannot be changed by this code path at all.
            guard clamped < 1 else { return buffer.lines }
            return buffer.lines.map { line in
                OpacityFade.fading(
                    line, by: clamped, over: surface, defaultForeground: defaultForeground)
            }
        }

        if let cycling = cycling(
            buffer, faded: faded, over: surface, defaultForeground: defaultForeground,
            context: context)
        {
            return cycling
        }
        let factor = min(max(opacity, 0), 1)
        guard factor < 1 else { return buffer }
        var result = buffer.replacingLines(faded(by: factor))
        result.overlays = Self.fadingOverlays(
            buffer.overlays, by: factor, over: surface, defaultForeground: defaultForeground)
        return result
    }

    /// The whole fade, pre-rendered, when the opacity is on a repeating
    /// animation — or `nil` when it is not (the ordinary, transient case).
    ///
    /// A fade that never ends would otherwise cost a render pass for as long as
    /// the view is on screen. It need not: `.opacity` renders its content ONCE
    /// and then re-colours the finished lines, so every point of the cycle is a
    /// re-colouring of the same buffer, and the run loop can replay them.
    /// See ``AnimatedBufferCycle``.
    private func cycling(
        _ buffer: FrameBuffer, faded: (Double) -> [String], over surface: Color,
        defaultForeground: Color, context: RenderContext
    ) -> FrameBuffer? {
        guard !context.isMeasuring, let storage = context.stateStorage else { return nil }
        let key = AnimationStore.Key(
            identity: context.identity, owner: ObjectIdentifier(Self.self))
        guard
            let cycle: AnimationCycle<Double> = storage.animations.cycle(
                for: key,
                nowNanos: context.environment.frameNowNanos,
                tick: context.environment.animationTick),
            let runs = AnimatedBufferCycle.runs(phases: cycle.values.map(faded))
        else { return nil }

        // An ANCHORED layer — an `.offset`/`.position` child, a popover — is
        // part of what this subtree draws, so it has to breathe with the rest
        // of it. Its runs are built in the LAYER's own coordinate space and
        // attached to the layer's content, because that is the space a run on
        // it is in; the compositor shifts them by wherever it places the layer
        // (`FrameBuffer.composited` lifts an overlay's `animatedCells` exactly
        // as it lifts its regions).
        //
        // This used to decline the pre-rendered path outright when an anchored
        // layer was present, and pay a render per frame for as long as the fade
        // ran. That was the safe answer while the alternative was a layer
        // frozen at one phase; it is not needed now that the layer can carry
        // its own frames.
        guard
            let layers = Self.cyclingOverlays(
                buffer.overlays, phases: cycle.values, current: cycle.current,
                over: surface, defaultForeground: defaultForeground)
        else { return nil }

        // Nothing anywhere changes across the cycle — every row identical at
        // every phase. Serving it costs nothing and stops the clock; declining
        // would re-render forever for a fade nobody can see.
        guard !runs.isEmpty || layers.carriesRuns else { return nil }

        // Only now: a cycle that could not be turned into runs must keep being
        // rendered for, or the fade freezes on whatever frame it stopped at.
        storage.animations.noteServedByRuns(key)

        // Drawn at the CYCLE's current value, not at this frame's continuous
        // one, so replaying the run at the tick just rendered is a no-op — the
        // property every run has to have.
        var result = buffer.replacingLines(faded(cycle.current))
        result.animatedCells += runs
        result.overlays = layers.overlays
        return result
    }

    /// `overlays` faded to `current` and carrying their own runs for the rest
    /// of the cycle — or `nil` when any of them cannot be expressed as runs, in
    /// which case the whole fade must stay on the per-frame path rather than
    /// animate half of itself.
    ///
    /// Screen-level layers are passed through untouched, exactly as
    /// ``fadingOverlays(_:by:over:defaultForeground:)`` leaves them: a dialog
    /// the subtree opened is not the subtree's drawing and does not fade with
    /// it, cycling or not.
    ///
    /// Recursive, because a layer's content can carry layers.
    private static func cyclingOverlays(
        _ overlays: [OverlayLayer], phases: [Double], current: Double, over surface: Color,
        defaultForeground: Color
    ) -> (overlays: [OverlayLayer], carriesRuns: Bool)? {
        var result: [OverlayLayer] = []
        var carriesRuns = false
        result.reserveCapacity(overlays.count)
        for layer in overlays {
            guard !layer.isScreenLevel else {
                result.append(layer)
                continue
            }
            func fade(_ lines: [String], by factor: Double) -> [String] {
                let clamped = min(max(factor, 0), 1)
                guard clamped < 1 else { return lines }
                return lines.map {
                    OpacityFade.fading(
                        $0, by: clamped, over: surface, defaultForeground: defaultForeground)
                }
            }
            guard
                let runs = AnimatedBufferCycle.runs(
                    phases: phases.map { fade(layer.content.lines, by: $0) }),
                let nested = cyclingOverlays(
                    layer.content.overlays, phases: phases, current: current,
                    over: surface, defaultForeground: defaultForeground)
            else { return nil }

            var faded = layer
            faded.content = layer.content.replacingLines(
                fade(layer.content.lines, by: current))
            faded.content.animatedCells += runs
            faded.content.overlays = nested.overlays
            result.append(faded)
            carriesRuns = carriesRuns || !runs.isEmpty || nested.carriesRuns
        }
        return (result, carriesRuns)
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
    static func fadingOverlays(
        _ overlays: [OverlayLayer], by factor: Double, over surface: Color,
        defaultForeground: Color
    ) -> [OverlayLayer] {
        guard factor < 1 else { return overlays }
        return overlays.map { layer in
            guard !layer.isScreenLevel else { return layer }
            var faded = layer
            faded.content = layer.content.replacingLines(
                layer.content.lines.map {
                    OpacityFade.fading(
                        $0, by: factor, over: surface, defaultForeground: defaultForeground)
                })
            faded.content.overlays = fadingOverlays(
                layer.content.overlays, by: factor, over: surface,
                defaultForeground: defaultForeground)
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
        ) { $0.opacity(factor, over: surface) }
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
