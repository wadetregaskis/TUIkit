//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StyleCascadeAlphaTests.swift
//
//  `.style(.text) { $0.foreground = … }` and its six per-control spellings.
//  `Text` honoured a faded cascade colour; the six controls that read the same
//  cascade spent it on the escape. Row 10 of §16.1.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A faded style-cascade colour, in the controls that read it")
struct StyleCascadeAlphaTests {

    private func buffer<V: View>(_ view: V, width: Int = 30, height: Int = 3) -> FrameBuffer {
        let context = RenderContext(
            availableWidth: width, availableHeight: height, tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context)
    }

    private let faded = Color.rgb(200, 40, 40).opacity(0.5)

    /// Half of 255, rounded the way `OpacityRegion.claim` rounds it.
    private var half: Double { 128.0 / 255 }

    // MARK: - Button, both label paths and both variants

    @Test("A standard button's label claims the cells between its caps")
    func standardButtonLabelClaims() throws {
        let drawn = buffer(
            Button("Save") {}.buttonTextStyle { $0.foreground = faded })
        let claim = try #require(drawn.opacityRegions.first, "\(drawn.opacityRegions)")
        // One cell in: the `▐` cap is its own colour and, when focused, its own run.
        #expect(claim.offsetX == 1)
        #expect(claim.inkOpacity == half)
        #expect(claim.width == drawn.width - 2, "the label, not the caps")
    }

    @Test("A plain button's label claims past the cells the focus prefix reserves")
    func plainButtonLabelClaims() throws {
        let drawn = buffer(
            Button("Save") {}.buttonStyle(.plain).buttonTextStyle { $0.foreground = faded })
        let claim = try #require(drawn.opacityRegions.first, "\(drawn.opacityRegions)")
        #expect(claim.offsetX == BorderRenderer.focusIndicatorWidth)
        #expect(claim.inkOpacity == half)
    }

    /// The pairing's own invariant: whatever the claim says, the BYTES must state
    /// the opaque spelling. A migrated site that forgot this would render at full
    /// strength and then be faded again by the compositor.
    @Test("The bytes state the opaque colour, never the faded one")
    func bytesAreOpaque() {
        for view in [
            AnyView(Button("Save") {}.buttonTextStyle { $0.foreground = faded }),
            AnyView(Button("Save") {}.buttonStyle(.plain).buttonTextStyle { $0.foreground = faded }),
            AnyView(TextField("", text: .constant("hi")).textFieldTextStyle { $0.foreground = faded }),
            AnyView(Slider(value: .constant(0.5), in: 0...1).sliderTextStyle { $0.foreground = faded }),
            AnyView(Stepper(value: .constant(3), in: 0...9) { Text("n") }
                .stepperTextStyle { $0.foreground = faded }),
        ] {
            let drawn = buffer(view)
            let text = drawn.lines.joined()
            #expect(
                text.contains("38;2;200;40;40"),
                "the opaque spelling is missing: \(text.debugDescription)")
        }
    }

    @Test("An opaque cascade colour claims nothing")
    func opaqueCascadeClaimsNothing() {
        let drawn = buffer(
            Button("Save") {}.buttonTextStyle { $0.foreground = .rgb(200, 40, 40) })
        #expect(drawn.opacityRegions.isEmpty, "\(drawn.opacityRegions)")
    }

    // MARK: - The two fields

    @Test("An unfocused TextField claims its whole content field")
    func unfocusedFieldClaims() throws {
        let drawn = buffer(
            TextField("", text: .constant("hello")).textFieldTextStyle { $0.foreground = faded })
        let claim = try #require(drawn.opacityRegions.first, "\(drawn.opacityRegions)")
        #expect(claim.inkOpacity == half)
        #expect(claim.offsetX >= 1, "past the field's opening cap")
    }

    @Test("A SecureField claims the same way — they share one renderer")
    func secureFieldClaims() throws {
        let drawn = buffer(
            SecureField("", text: .constant("hunter2"))
                .secureFieldTextStyle { $0.foreground = faded })
        let claim = try #require(drawn.opacityRegions.first, "\(drawn.opacityRegions)")
        #expect(claim.inkOpacity == half)
    }

    /// A focused field claims per RUN, not one rectangle for the field: the
    /// selection's field is opaque by construction — and under this palette so is its
    /// text — while the entered text's are the cascade's, so one rectangle would fade
    /// the highlight along with the text.
    @Test("A focused field's claims stop at the selection, and cover the rest")
    func focusedFieldClaimsPerRun() {
        let renderer = TextFieldContentRenderer(
            prompt: nil, isDisabled: false, displayCharacter: { $0 }, surface: nil,
            contentForeground: faded)
        let content = renderer.buildContent(
            text: "abcdef", cursorPosition: 6, selectionRange: 1..<3, isFocused: true,
            palette: makeRenderContext(width: 20, height: 1).environment.palette,
            cursorStyle: TextCursorStyle(), cursorTimer: CursorTimer?.none, contentWidth: 10)
        #expect(!content.claims.isEmpty, "the cascade colour never left the renderer")
        // Every claim is at the cascade's alpha; the selected cells produce none: the
        // highlight is opaque by construction, and its text is this opaque palette's
        // own slot. Under a faded palette that text would claim (§60).
        for claim in content.claims {
            #expect(claim.inkOpacity == half, "\(claim)")
        }
        // The selection is cells 1..<3, so no single claim may span them.
        for claim in content.claims {
            let covered = claim.offsetX..<(claim.offsetX + claim.width)
            #expect(
                !(covered.contains(1) && covered.contains(2)),
                "a claim spanned the opaque selection: \(claim)")
        }
    }

    // MARK: - Slider and Stepper read-outs

    @Test("A Slider claims its value read-out and not its track")
    func sliderValueClaims() throws {
        let drawn = buffer(
            Slider(value: .constant(0.5), in: 0...1).sliderTextStyle { $0.foreground = faded },
            width: 30)
        let claim = try #require(drawn.opacityRegions.first, "\(drawn.opacityRegions)")
        #expect(claim.inkOpacity == half)
        // Past `"◀ " + track + " ▶ "`. The track's own colours are §16.1 row 8 and
        // still open, so a claim that reached them would double-fade once it lands.
        #expect(claim.offsetX > 5, "the read-out sits right of the track: \(claim)")
        #expect(drawn.opacityRegions.count == 1, "\(drawn.opacityRegions)")
    }

    @Test("A Stepper claims its read-out, measuring past the arrow rather than assuming one cell")
    func stepperValueClaims() throws {
        let drawn = buffer(
            Stepper(value: .constant(3), in: 0...9) { Text("n") }
                .stepperTextStyle { $0.foreground = faded })
        // TWO claims, and both are right: `Stepper` publishes its `controlKind`, so
        // the `Text("n")` label resolves the same `.control(.stepper)` entry and is
        // claimed by §14's uniform arm. The read-out's is the one this test is
        // about — identified by its width, since the label's is the label's.
        #expect(drawn.opacityRegions.count == 2, "\(drawn.opacityRegions)")
        for claim in drawn.opacityRegions {
            #expect(claim.inkOpacity == half, "\(claim)")
        }
        // The read-out's two pad spaces are inside the styled run — unlike a
        // Slider's, which are appended bare — so an underline from the cascade
        // lands on them and they are part of the rectangle.
        let readout = try #require(
            drawn.opacityRegions.first { $0.width == "3".strippedLength + 2 },
            "\(drawn.opacityRegions)")
        #expect(readout.width == 3)
        #expect(readout.offsetX >= TerminalSymbols.leftArrow.strippedLength, "\(readout)")
    }

    // MARK: - A breathing label spends rather than claims

    /// A `Link` (and anything `indicatesFocusInLabel`) breathes its LABEL, so its
    /// two ends must agree about alpha — and §29's rule is that both spend it
    /// against the stated surface. So the label is opaque by the time it is drawn
    /// and there is nothing left to claim. Recorded here rather than left to be
    /// discovered as a missing claim.
    @Test("A breathing label spends its cascade alpha, and so claims nothing")
    func breathingLabelSpends() {
        let drawn = buffer(
            Link("Open", destination: URL(string: "https://example.com")!)
                .buttonTextStyle { $0.foreground = faded })
        #expect(
            drawn.opacityRegions.isEmpty,
            "a breathing label cannot claim — see §29: \(drawn.opacityRegions)")
        // And it must not have reached the emitter with an alpha, which is what the
        // debug assertion would have caught. The colour drawn is the SPENT one.
        #expect(!drawn.lines.joined().isEmpty)
    }
}
