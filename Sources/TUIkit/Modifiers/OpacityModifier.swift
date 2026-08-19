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
        let factor = min(max(opacity, 0), 1)
        // Fully opaque is the identity, and taking it means an untouched
        // subtree cannot be changed by this code path at all.
        guard factor < 1, !buffer.isEmpty else { return buffer }

        // Resolve first: a semantic colour makes `opacity(_:over:)` a silent
        // no-op and makes `ANSIRenderer` trap outright.
        let palette = context.environment.palette
        let surface = palette.background.resolve(with: palette)
        let defaultForeground = palette.foreground.resolve(with: palette)

        // Nothing is injected and nothing is appended: every run the renderer
        // emits already names its own colour and ends in a reset, so rewriting
        // the colours it named is enough to fade all of it. `OpacityTests`
        // pins that precondition across the view surface.
        let faded = buffer.lines.map { line in
            OpacityFade.fading(
                line, by: factor, over: surface, defaultForeground: defaultForeground)
        }
        return buffer.replacingLines(faded)
    }
}

/// The colour arithmetic behind ``View/opacity(_:)``, kept out of
/// the generic view so there is one copy of it and tests can reach it.
enum OpacityFade {
    /// Rewrites every colour in `line`'s SGR sequences, leaving everything else
    /// — bold, dim, underline, inverse, cursor moves — exactly as it was.
    static func fading(
        _ line: String, by factor: Double, over surface: Color, defaultForeground: Color
    ) -> String {
        var result = ""
        for segment in line.ansiSegments() {
            switch segment {
            case .visible(let character):
                result.append(character)
            case .ansi(let sequence, _):
                result += Self.fadingSGR(
                    sequence, by: factor, over: surface,
                    defaultForeground: defaultForeground)
            }
        }
        return result
    }

    /// One escape sequence, faded if it is an SGR that names a colour.
    private static func fadingSGR(
        _ sequence: String, by factor: Double, over surface: Color, defaultForeground: Color
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
                    let faded = color.opacity(factor, over: surface)
                    rewritten += parameter == 38
                        ? ANSIRenderer.foregroundCodes(for: faded)
                        : ANSIRenderer.backgroundCodes(for: faded)
                } else {
                    rewritten.append(parameters[index])
                }
                index += consumed
                continue
            case 30...37, 90...97, 40...47, 100...107:
                rewritten += Self.fadedBasic(parameter, by: factor, over: surface)
            case 39:
                // "Default foreground" — which IS the palette foreground
                // here, so it fades rather than snapping back to full
                // strength.
                rewritten += ANSIRenderer.foregroundCodes(
                    for: defaultForeground.opacity(factor, over: surface))
            case 49:
                rewritten += ANSIRenderer.backgroundCodes(
                    for: surface.opacity(factor, over: surface))
            default:
                // 0 (reset), 1 (bold), 2 (dim), 4 (underline), 7 (inverse), …
                rewritten.append(parameters[index])
            }
            index += 1
        }
        return "\u{1B}[" + rewritten.joined(separator: ";") + "m"
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
    private static func fadedBasic(
        _ parameter: Int, by factor: Double, over surface: Color
    ) -> [String] {
        let isBackground = (40...47).contains(parameter) || (100...107).contains(parameter)
        let isBright = parameter >= 90
        let base = parameter - (isBright ? (isBackground ? 100 : 90) : (isBackground ? 40 : 30))
        guard base >= 0, base < Self.basicColors.count else { return ["\(parameter)"] }
        let (standard, bright) = Self.basicColors[base]
        let faded = (isBright ? bright : standard).opacity(factor, over: surface)
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
