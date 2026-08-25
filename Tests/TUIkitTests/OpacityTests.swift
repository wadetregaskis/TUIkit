//  🖥️ TUIKit — Terminal UI Kit for Swift
//  OpacityTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

/// `.opacity(_:)` — a blend toward the background, since a cell has no alpha.
///
/// The properties worth pinning are the two ends (1 is the identity, 0 reaches
/// the background) and the thing that makes this better than a flat dim: the
/// colour that comes out is still the colour that went in, moved.
@MainActor
@Suite("Opacity")
struct OpacityTests {

    /// The foreground colour the renderer would emit for `color`, as a set of
    /// SGR parameters — the form the buffer actually carries.
    private func codes(_ color: Color) -> String {
        ANSIRenderer.foregroundCodes(for: color).joined(separator: ";")
    }

    @Test("Full opacity changes nothing at all")
    func opaqueIsTheIdentity() {
        let context = makeRenderContext(width: 24, height: 2)
        let plain = renderToScreen(Text("hello").foregroundStyle(.red), context: context)
        let faded = renderToScreen(
            Text("hello").foregroundStyle(.red).opacity(1), context: context)
        // Byte-for-byte, not just visually: an opaque view must not pay for,
        // or be perturbed by, a rewrite it doesn't need.
        #expect(faded.lines == plain.lines)
    }

    @Test("Zero opacity draws nothing, and keeps its space")
    func transparentDrawsNothing() {
        let context = makeRenderContext(width: 24, height: 2)
        let plain = renderToScreen(Text("hello").foregroundStyle(.red), context: context)
        let faded = renderToScreen(
            Text("hello").foregroundStyle(.red).opacity(0), context: context)

        // Not "drawn in the background colour" — not drawn. That distinction is
        // invisible over the plain page and is the whole point over anything
        // else: a view faded to nothing must REVEAL what is behind it, and text
        // painted in the background colour hides it just as well as text
        // painted in any other.
        #expect(faded.lines[0].stripped.trimmingCharacters(in: .whitespaces).isEmpty)
        #expect(!faded.lines[0].contains(codes(.red)))
        // Opacity does not remove a view; it makes it invisible. The space is
        // still claimed, so nothing around it moves.
        #expect(faded.lines.count == plain.lines.count)
        #expect(faded.width == plain.width)
    }

    @Test("What is behind a fully transparent view is untouched")
    func transparentRevealsWhatIsBehind() {
        let context = makeRenderContext(width: 24, height: 2)
        let composed = renderToScreen(
            ZStack {
                Text("world").foregroundStyle(.blue)
                Text("hello").foregroundStyle(.red).opacity(0)
            },
            context: context)

        // The case the render-time fade got wrong, and the reason for all of
        // this: it painted "hello" in a near-background colour ON TOP of the
        // blue text, which is neither invisible nor revealing.
        #expect(composed.lines[0].stripped.hasPrefix("world"))
        #expect(composed.lines[0].contains(codes(.blue)))
    }

    @Test("A half-faded colour is between the colour and the background")
    func blendIsBetween() {
        let context = makeRenderContext(width: 24, height: 2)
        let background = context.environment.palette.background
        let faded = renderToScreen(
            Text("hello").foregroundStyle(.red).opacity(0.5), context: context)

        // Neither endpoint: this is the whole difference between a blend and
        // a switch.
        #expect(!faded.lines[0].contains(codes(.red)))
        #expect(!faded.lines[0].contains(codes(background)))
        #expect(faded.lines[0].contains(codes(Color.red.opacity(0.5, over: background))))
    }

    @Test("Hue survives the fade")
    func hueIsPreserved() {
        // The reason to parse the colour back out rather than flatten to a
        // single dim grey: a red heading at 0.5 must still read as red.
        let background = Color.rgb(0, 0, 0)
        let red = Color.rgb(200, 20, 20).opacity(0.5, over: background)
        let blue = Color.rgb(20, 20, 200).opacity(0.5, over: background)
        #expect(codes(red) != codes(blue))

        let context = makeRenderContext(width: 24, height: 2)
        let line = renderToScreen(
            HStack {
                Text("r").foregroundStyle(Color.rgb(200, 20, 20))
                Text("b").foregroundStyle(Color.rgb(20, 20, 200))
            }.opacity(0.5),
            context: context
        ).lines[0]
        let surface = context.environment.palette.background
        #expect(line.contains(codes(Color.rgb(200, 20, 20).opacity(0.5, over: surface))))
        #expect(line.contains(codes(Color.rgb(20, 20, 200).opacity(0.5, over: surface))))
    }

    @Test("Text with no colour of its own still fades")
    func unstyledTextFades() {
        // Without this, a subtree of plain Text would be completely unaffected
        // by .opacity — which is the failure a user would notice first.
        let context = makeRenderContext(width: 24, height: 2)
        let plain = renderToScreen(Text("hello"), context: context)
        // Above the threshold, so the glyphs are still drawn and there is a
        // colour to check. Below it the view is not drawn at all, which is a
        // different property and is tested where it belongs.
        let faded = renderToScreen(Text("hello").opacity(0.6), context: context)
        #expect(faded.lines[0] != plain.lines[0])
        #expect(faded.lines[0].stripped.contains("hello"))

        let palette = context.environment.palette
        #expect(
            faded.lines[0].contains(
                codes(palette.foreground.opacity(0.6, over: palette.background))))
    }

    @Test("Every colour form is understood")
    func allColourEncodings() {
        // The four ways a colour reaches the buffer. A form this misses would
        // pass through at full strength — a partly-faded view, which is worse
        // than an unfaded one.
        let context = makeRenderContext(width: 32, height: 2)
        let surface = context.environment.palette.background
        for color in [Color.red, .brightCyan, .palette(93), .rgb(10, 200, 40)] {
            let faded = renderToScreen(
                Text("x").foregroundStyle(color).opacity(0.5), context: context)
            #expect(
                faded.lines[0].contains(codes(color.opacity(0.5, over: surface))),
                "\(color) did not fade")
            #expect(!faded.lines[0].contains(";\(codes(color))m"), "\(color) survived unfaded")
        }
    }

    @Test("Backgrounds fade too")
    func backgroundsFade() {
        let context = makeRenderContext(width: 24, height: 3)
        let surface = context.environment.palette.background
        let faded = renderToScreen(
            Text("hi").background(Color.blue).opacity(0.5), context: context)
        let expected = ANSIRenderer.backgroundCodes(for: Color.blue.opacity(0.5, over: surface))
            .joined(separator: ";")
        #expect(faded.lines[0].contains(expected))
    }

    @Test("Non-colour styling is left alone")
    func styleAttributesSurvive() {
        // Bold, underline and the rest have no colour to blend; rewriting or
        // dropping them would silently restyle the subtree.
        let context = makeRenderContext(width: 24, height: 2)
        let faded = renderToScreen(Text("hi").bold().underline().opacity(0.5), context: context)
        let sequences = faded.lines[0].ansiSegments().compactMap { segment -> String? in
            if case .ansi(let sequence, _) = segment { return sequence }
            return nil
        }.joined()
        #expect(sequences.contains("1"))  // bold
        #expect(sequences.contains("4"))  // underline
    }

    @Test("A faded view keeps its size and its hit regions")
    func layoutIsUnchanged() {
        let context = makeRenderContext(width: 40, height: 6)
        let plain = renderToScreen(Button("Press") {}, context: context)
        let faded = renderToScreen(Button("Press") {}.opacity(0.5), context: context)

        // SwiftUI's opacity(0) leaves the view in the layout and still
        // interactive; so does this.
        #expect(faded.width == plain.width)
        #expect(faded.lines.count == plain.lines.count)
        #expect(faded.hitTestRegions.count == plain.hitTestRegions.count)
        let proposal = ProposedSize(width: 40, height: 6)
        #expect(
            measureChild(Text("hello").opacity(0), proposal: proposal, context: context)
                == measureChild(Text("hello"), proposal: proposal, context: context))
    }

    @Test("Out-of-range values clamp")
    func clamping() {
        let context = makeRenderContext(width: 24, height: 2)
        let below = renderToScreen(Text("hi").foregroundStyle(.red).opacity(-2), context: context)
        let zero = renderToScreen(Text("hi").foregroundStyle(.red).opacity(0), context: context)
        #expect(below.lines == zero.lines)

        let above = renderToScreen(Text("hi").foregroundStyle(.red).opacity(5), context: context)
        let plain = renderToScreen(Text("hi").foregroundStyle(.red), context: context)
        #expect(above.lines == plain.lines)
    }

    @Test("Nested opacity compounds")
    func nesting() {
        let context = makeRenderContext(width: 24, height: 2)
        // Two stacked translucent layers, exactly as in SwiftUI: 0.8 through
        // 0.75 is 0.6, and 0.6 is what the picture must be — not two blends
        // applied in turn, which would round twice and, more importantly, would
        // apply the glyph threshold twice.
        let nested = renderToScreen(
            Text("hi").foregroundStyle(.red).opacity(0.8).opacity(0.75), context: context)
        // `0.8 * 0.75` rather than `0.6`: the two are not the same `Double`, and
        // the blend truncates, so spelling the product out is the difference
        // between comparing pictures and comparing rounding.
        let once = renderToScreen(
            Text("hi").foregroundStyle(.red).opacity(0.8 * 0.75), context: context)
        #expect(nested.lines == once.lines)
    }

    @Test("The threshold applies to the PRODUCT, not to each fade")
    func nestingCrossesTheThresholdOnce() {
        let context = makeRenderContext(width: 24, height: 2)
        // Half of a half is a quarter, which is below the threshold — so the
        // contested cells show the text BEHIND, even though neither fade alone
        // would have yielded them. Applying the threshold per layer would draw
        // the front text at full character strength, faded twice. (The contest
        // is what makes this observable: over a blank cell there is no
        // threshold to cross, and the glyph would simply fade.)
        let faded = renderToScreen(
            ZStack {
                Text("no").foregroundStyle(.green)
                Text("hi").foregroundStyle(.red).opacity(0.5).opacity(0.5)
            },
            context: context)
        #expect(faded.lines[0].stripped.trimmingCharacters(in: .whitespaces) == "no")
    }

    @Test("Every rendered run names its own colour and ends reset")
    func fadeableByConstruction() {
        // This is the precondition the fade relies on, and it is a property of
        // the RENDERER, not of opacity: because every visible run explicitly
        // names its foreground and every line ends in a reset, rewriting the
        // colours a line names is enough to fade all of it — no colour has to
        // be injected, and nothing bleeds into a sibling. A view that emitted
        // bare ink would fall through the fade unchanged, so the day one does,
        // this is what says so.
        let context = makeRenderContext(width: 30, height: 8)
        var bare: [String] = []
        var unterminated: [String] = []

        func audit(_ name: String, _ buffer: FrameBuffer) {
            for line in buffer.lines {
                var sawColour = false
                var terminated = true
                for segment in line.ansiSegments() {
                    switch segment {
                    case .ansi(let sequence, let isSGR):
                        if isSGR {
                            sawColour = true
                            terminated = sequence == ANSIRenderer.reset
                        }
                    case .visible(let character) where character != " ":
                        // A space carries no ink, so an uncoloured one is fine.
                        if !sawColour { bare.append(name) }
                        terminated = false
                    case .visible:
                        break
                    }
                }
                if !terminated { unterminated.append(name) }
            }
        }

        audit("Text", renderToScreen(Text("hi"), context: context))
        audit("Divider", renderToScreen(Divider(), context: context))
        audit("Spacer", renderToScreen(HStack { Text("a"); Spacer(); Text("b") }, context: context))
        audit("Button", renderToScreen(Button("Go") {}, context: context))
        audit("ProgressView", renderToScreen(ProgressView(value: 0.5), context: context))
        audit("Slider", renderToScreen(Slider(value: .constant(0.5), in: 0...1), context: context))
        audit("Toggle", renderToScreen(Toggle("t", isOn: .constant(true)), context: context))
        audit("List", renderToScreen(List { Text("a"); Text("b") }, context: context))
        struct Row: Identifiable { let id: Int; let name: String }
        audit("Table", renderToScreen(
            Table(
                [Row(id: 1, name: "one"), Row(id: 2, name: "two")],
                selection: .constant(nil as Int?)
            ) {
                TableColumn("Name", value: \Row.name)
            },
            context: context))
        audit("border", renderToScreen(Text("x").padding().border(), context: context))
        audit("Gauge", renderToScreen(Gauge(value: 0.5) { Text("g") }, context: context))
        audit("TextField", renderToScreen(TextField("p", text: .constant("v")), context: context))
        audit("background", renderToScreen(Text("b").background(Color.blue), context: context))
        audit("ZStack", renderToScreen(ZStack { Text("under"); Text("over") }, context: context))

        #expect(bare.isEmpty, "views drew ink in no colour: \(Set(bare).sorted())")
        #expect(unterminated.isEmpty, "views left a colour active: \(Set(unterminated).sorted())")
    }

    @Test("The default-colour codes fade to the palette's own colours")
    func defaultColourCodes() {
        // `39`/`49` mean "whatever the terminal's default is", which here is
        // the palette — so they have to become the FADED palette colours, not
        // pass through and snap the run back to full strength. No shipped view
        // emits them today, so this drives the parser directly.
        let foreground = Color.rgb(200, 200, 200)
        let surface = Color.rgb(0, 0, 0)
        let faded = OpacityFade.fading(
            "\u{1B}[39mx\u{1B}[49my", by: 0.5, over: surface, defaultForeground: foreground)
        #expect(faded.contains(
            ANSIRenderer.foregroundCodes(for: foreground.opacity(0.5, over: surface))
                .joined(separator: ";")))
        #expect(!faded.contains("[39m"))
        #expect(!faded.contains("[49m"))
        #expect(faded.stripped == "xy")
    }

    @Test("Escape sequences that are not SGR pass through untouched")
    func nonSGRSequencesSurvive() {
        // Cursor moves, erases and the rest carry no colour; rewriting one
        // would corrupt the frame rather than fade it.
        let moves = "\u{1B}[2A\u{1B}[Kx\u{1B}[1;1H"
        let faded = OpacityFade.fading(
            moves, by: 0.5, over: Color.rgb(0, 0, 0), defaultForeground: Color.rgb(255, 255, 255))
        #expect(faded == moves)
    }

    @Test("A malformed colour sequence is left alone rather than mangled")
    func malformedSequences() {
        let surface = Color.rgb(0, 0, 0)
        let white = Color.rgb(255, 255, 255)
        // Truncated extended-colour forms: too few parameters to name a
        // colour. Dropping or half-rewriting these would shift every
        // parameter after them.
        for broken in ["\u{1B}[38m", "\u{1B}[38;5m", "\u{1B}[38;2;10;20m", "\u{1B}[m"] {
            let faded = OpacityFade.fading(
                broken, by: 0.5, over: surface, defaultForeground: white)
            #expect(faded == broken, "mangled \(broken.debugDescription)")
        }
    }

    @Test("A palette built from semantic colours neither traps nor no-ops")
    func semanticPalette() {
        // Two failure modes meet here, and they are opposites: `ANSIRenderer`
        // TRAPS on an unresolved semantic colour, while `opacity(_:over:)`
        // silently returns the colour unchanged — so an unresolved surface
        // would either crash the app or make the fade quietly do nothing.
        // Resolving both palette colours up front is what avoids each.
        struct SemanticPalette: Palette {
            let id = "semantic-surface"
            let name = "Semantic surface"
            var background: Color { .palette.accent }
            var foreground: Color { .palette.info }
            let accent = Color.rgb(0, 0, 0)
            let success = Color.green
            let warning = Color.yellow
            let error = Color.red
            let info = Color.rgb(255, 255, 255)
            let border = Color.brightBlack
        }

        let palette = SemanticPalette()
        let context = makeRenderContext(width: 24, height: 2) { environment, _ in
            environment.palette = palette
        }
        let faded = renderToScreen(
            Text("hi").foregroundStyle(Color.rgb(200, 20, 20)).opacity(0.5), context: context)

        // The blend actually happened, against the RESOLVED background.
        #expect(faded.lines[0].contains(
            codes(Color.rgb(200, 20, 20).opacity(0.5, over: palette.accent))))
    }

    @Test("An empty buffer survives")
    func emptyContent() {
        let context = makeRenderContext(width: 20, height: 2)
        let faded = renderToScreen(EmptyView().opacity(0.5), context: context)
        #expect(faded.lines.allSatisfy { $0.stripped.trimmingCharacters(in: .whitespaces).isEmpty })
    }
}
