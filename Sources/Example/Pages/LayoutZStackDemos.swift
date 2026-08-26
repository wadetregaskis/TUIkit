//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LayoutZStackDemos.swift
//
//  The Layout System page's ZStack section: five bands making one claim from
//  five angles — the top layer owns every cell it lands on, and nothing shows
//  through.
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkit

extension LayoutPage {

    /// One band's geometry: how wide the layer underneath is, how wide the
    /// layer on top is, and how the two are aligned.
    ///
    /// Enough to answer where the top layer has to go to be clear of the one
    /// beneath it — which is what the travel control means, and which is a
    /// different number of cells in every band.
    struct ZStackBand {
        let under: Int
        let over: Int
        let alignment: HorizontalAlignment

        /// The cell offset for `travel` in `-1...1`.
        ///
        /// At `±1` the top layer is entirely off the layer beneath, with one
        /// cell of daylight between them — far enough that "which cells does it
        /// own" has the answer "none of these", which is the other end of the
        /// same demonstration.
        func offset(_ travel: Double) -> Int {
            let leading: Int =
                switch alignment {
                case .center: (under - over) / 2
                default: 0
                }
            let clearLeft = -(leading + over + 1)
            let clearRight = under - leading + 1
            let midpoint = travel < 0 ? Double(-clearLeft) : Double(clearRight)
            return Int((travel * midpoint).rounded())
        }

        /// How wide the band must be drawn for the displaced layer to stay
        /// inside its own border at either extreme.
        ///
        /// `.offset` does not clip — the displaced content paints wherever it
        /// lands, border included — and a label chewing through the box's edge
        /// reads as a rendering fault rather than as the point being made.
        var bandWidth: Int { under + 2 * (over + 1) }

        /// Where the band's own content sits inside that width, so the layer
        /// beneath stays put as the one on top sweeps past it.
        var inset: Int { over + 1 }
    }

    static let zstackCase1 = ZStackBand(under: 28, over: 8, alignment: .center)
    static let zstackCase2Padded = ZStackBand(under: 22, over: 10, alignment: .center)
    static let zstackCase2Bare = ZStackBand(under: 20, over: 4, alignment: .center)
    static let zstackCase3 = ZStackBand(under: 21, over: 4, alignment: .leading)
    static let zstackCase4 = ZStackBand(under: 36, over: 10, alignment: .center)
    static let zstackCase5 = ZStackBand(under: 36, over: 12, alignment: .leading)

    /// The travel the demos are actually drawn at: the control's, or the sweep
    /// while it is running.
    ///
    /// A triangle wave over the timeline's own clock rather than an animated
    /// `@State`: a sweep is a function of time, and reading it here means
    /// nothing has to be written back into state on every frame.
    static func zstackSweep(at date: Date) -> Double {
        let period = 8.0
        let phase = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: period) / period
        // 0 → 0, ¼ → 1, ½ → 0, ¾ → -1, 1 → 0.
        return sin(phase * 2 * .pi)
    }

    /// The whole section.
    @ViewBuilder var zstackSection: some View {
        DemoSection("page.layout.section.zstack") {
            // One `TimelineView` either way, with a schedule that stops rather
            // than a branch that swaps the view out: swapping would change the
            // subtree's IDENTITY every time the toggle moved, and take the
            // Slider's own state with it.
            TimelineView(AnimationTimelineSchedule(paused: !zstackAnimates)) { timeline in
                zstackBody(
                    travel: zstackAnimates
                        ? Self.zstackSweep(at: timeline.date) : zstackTravel)
            }
        }
    }

    @ViewBuilder private func zstackBody(travel: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("page.layout.zstack.explain")
                .foregroundStyle(.palette.foregroundSecondary)

            // Slide every example's top layer at once: the partial overlaps are
            // where the "no transparency, no blending" claim above is actually
            // visible, and they only appear once the layers stop lining up.
            HStack(spacing: 1) {
                // Bound to the travel being DRAWN, so the thumb sweeps with
                // the demos rather than sitting where it was last dropped.
                // Writes still land on the control's own value, which is what
                // the sweep hands back to when it stops.
                Slider(
                    value: Binding(get: { travel }, set: { zstackTravel = $0 }),
                    in: -1...1, step: 0.05
                ) {
                    Text("page.layout.zstack.offset")
                        .foregroundStyle(.palette.foregroundSecondary)
                }
                .sliderShowsValue(false)
                .disabled(zstackAnimates)
                // Signed, and read as "how far across its travel": the
                // slider's own readout is a percentage of the RANGE, which
                // calls the middle 50% when the middle is where the layers
                // line up.
                Text(verbatim: String(format: "%+.0f%%", travel * 100))
                    .frame(width: 5, alignment: .trailing)
                    .bold()
                    .foregroundStyle(.palette.accent)
                Toggle("page.layout.zstack.animate", isOn: $zstackAnimates)
            }

            // 1 — What it does. Children stack back-to-front and alignment
            // positions them within the union of their sizes.
            Text("page.layout.zstack.case1")
                .foregroundStyle(.palette.foregroundTertiary)
            band(Self.zstackCase1) {
                Text(String(repeating: "▒", count: Self.zstackCase1.under))
                    .foregroundStyle(.palette.accent)
                Text(" \(L("page.layout.onTop")) ").bold().inverted()
                    .offset(x: Self.zstackCase1.offset(travel))
            }

            // 2 — There is no transparency, and this is the demo that says so.
            // The label's own SPACES are cells like any other, so they punch a
            // hole in the band rather than letting it through. Beside it, the
            // same label with no padding: the hole shrinks to exactly the
            // glyphs.
            Text("page.layout.zstack.case2")
                .foregroundStyle(.palette.foregroundTertiary)
            HStack(spacing: 3) {
                band(Self.zstackCase2Padded) {
                    Text(String(repeating: "▒", count: Self.zstackCase2Padded.under))
                        .foregroundStyle(.palette.accent)
                    Text(verbatim: "   \(L("page.layout.zstack.word"))   ")
                        .offset(x: Self.zstackCase2Padded.offset(travel))
                }
                band(Self.zstackCase2Bare) {
                    Text(String(repeating: "▒", count: Self.zstackCase2Bare.under))
                        .foregroundStyle(.palette.accent)
                    Text(verbatim: L("page.layout.zstack.word"))
                        .offset(x: Self.zstackCase2Bare.offset(travel))
                }
            }

            zstackLowerCases(travel: travel)
        }
    }

    @ViewBuilder private func zstackLowerCases(travel: Double) -> some View {
        // 3 — Nor is there any blending. Two words over each other give the top
        // one's cells, not a mixture of both; the lower one survives only where
        // the upper does not reach.
        Text("page.layout.zstack.case3")
            .foregroundStyle(.palette.foregroundTertiary)
        band(Self.zstackCase3, alignment: .leading) {
            Text(verbatim: "UNDERNEATH·UNDERNEATH")
                .foregroundStyle(.palette.foregroundSecondary)
            Text(verbatim: "OVER")
                .bold()
                .foregroundStyle(.palette.warning)
                .offset(x: Self.zstackCase3.offset(travel))
        }

        // 4 — What to reach for instead. `.opacity` is not compositing: it
        // moves a COLOUR toward the background and the cell stays as opaque as
        // it was, which is why it can fade text that has nothing behind it and
        // cannot show what does.
        Text("page.layout.zstack.case4")
            .foregroundStyle(.palette.foregroundTertiary)
        band(Self.zstackCase4) {
            Text(String(repeating: "▒", count: Self.zstackCase4.under))
                .foregroundStyle(.palette.accent)
            Text(" \(L("page.layout.zstack.faded")) ")
                .foregroundStyle(.palette.foreground)
                .opacity(0.45)
                .offset(x: Self.zstackCase4.offset(travel))
        }

        // 5 — Backgrounds, which is where "the last child to draw a cell owns
        // it" stops being an abstraction. Both layers paint a background across
        // their whole box, including the cells their text does not use, so the
        // top layer's colour arrives as a solid block with a hard edge — no
        // tint of the layer beneath anywhere in it, and no seam. Slide it and
        // the lower background reappears cell for cell exactly where the upper
        // one stops.
        Text("page.layout.zstack.case5")
            .foregroundStyle(.palette.foregroundTertiary)
        band(Self.zstackCase5, alignment: .leading) {
            // The lower block's own label sits at its far end, beyond anything
            // the upper block can reach, so what moves in this demo is the
            // colours rather than a word being eaten a letter at a time.
            Text("page.layout.zstack.under")
                .padding(.trailing, 1)
                .frame(width: Self.zstackCase5.under, alignment: .trailing)
                .foregroundStyle(.palette.background)
                .background(.palette.info)
            Text("page.layout.zstack.over")
                .frame(width: Self.zstackCase5.over, alignment: .center)
                .foregroundStyle(.palette.background)
                .background(.palette.warning)
                .offset(x: Self.zstackCase5.offset(travel))
        }
    }

    /// One demo band: the layers stacked, inset far enough inside a bordered
    /// box that the top one stays in the box at either extreme of its travel.
    @ViewBuilder
    private func band<Content: View>(
        _ geometry: ZStackBand,
        alignment: Alignment = .center,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) { content() }
            .padding(.leading, geometry.inset)
            .padding(.trailing, geometry.inset)
            .frame(width: geometry.bandWidth, alignment: .leading)
            .border(.brightBlack)
    }
}
