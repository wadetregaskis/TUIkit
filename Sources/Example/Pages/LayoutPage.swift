//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LayoutPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkit

/// Collects the indices of the ``LazyVStack`` rows that actually rendered this
/// frame. Because a row only emits its preference when it renders — and a
/// `LazyVStack` inside a `ScrollView` now windows to the visible viewport — the
/// union is exactly the set of rows on screen, and it changes as you scroll.
private struct LazyRenderedRowsKey: PreferenceKey {
    static let defaultValue: Set<Int> = []
    static func reduce(value: inout Set<Int>, nextValue: () -> Set<Int>) {
        value.formUnion(nextValue())
    }
}

/// Collects the indices of rows that participated in LAYOUT (were measured),
/// reported by the framework's `.onRenderPass` instrumentation. A plain sink
/// class: the callbacks fire in the middle of the measure/render passes, where
/// view state must not be mutated — the page snapshots it from a `.task` loop
/// instead.
@MainActor
private final class LazyMeasureSink {
    private var measured: Set<Int> = []

    func record(_ index: Int) { measured.insert(index) }

    /// The rows measured since the last snapshot (and resets the window).
    func snapshot() -> Set<Int> {
        defer { measured.removeAll(keepingCapacity: true) }
        return measured
    }
}

/// Wraps its subviews onto as many lines as they need, like text — the layout a
/// terminal has no built-in for, and the one that shows what ``Layout`` is for.
///
/// Both passes route through `lines(of:in:)` so the size reported and the
/// arrangement drawn cannot disagree. Note the widths accumulate per line
/// rather than being divided up front: dividing first is what silently loses
/// cells when the geometry is integers.
private struct Flow: Layout {
    var spacing = 1

    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        let limit = proposal.width ?? 40
        let rows = lines(of: subviews, in: limit)
        return ViewSize(
            width: rows.map(\.width).max() ?? 0,
            height: rows.count)
    }

    func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) {
        for (row, line) in lines(of: subviews, in: bounds.width).enumerated() {
            var x = bounds.x
            for index in line.indices {
                subviews[index].place(at: (x: x, y: bounds.y + row), proposal: .unspecified)
                x += subviews[index].sizeThatFits(.unspecified).width + spacing
            }
        }
    }

    /// Greedily packs subviews into lines no wider than `limit`.
    private func lines(
        of subviews: Subviews, in limit: Int
    ) -> [(indices: [Int], width: Int)] {
        var rows: [(indices: [Int], width: Int)] = []
        var current: [Int] = []
        var width = 0
        for index in subviews.indices {
            let itemWidth = subviews[index].sizeThatFits(.unspecified).width
            let advance = current.isEmpty ? itemWidth : spacing + itemWidth
            if !current.isEmpty, width + advance > limit {
                rows.append((current, width))
                current = [index]
                width = itemWidth
            } else {
                current.append(index)
                width += advance
            }
        }
        if !current.isEmpty { rows.append((current, width)) }
        return rows
    }
}

/// Sample data for the custom-layout demo, deliberately of varied widths so the
/// wrap points move as the terminal resizes. Tokens, not chrome — they are the
/// demo's *content*, so they are not translated (as file names in the browser
/// demo are not).
private let flowChips = [
    "swift", "terminal", "layout", "cells", "unicode", "ansi", "focus",
    "scroll", "render", "cache", "guides", "measure", "place", "anchor",
    "wrap", "flow", "column", "cell grid", "proposal", "subview",
]

/// Layout system demo page.
///
/// Shows various layout options including:
/// - VStack (vertical stacking)
/// - HStack (horizontal stacking)
/// - Spacer (flexible space)
/// - Padding and frame modifiers
/// - Lazy stacks windowing to a ScrollView's viewport (live rendered-row set)
/// - Alignment guides, GeometryReader, and a custom `Layout`
struct LayoutPage: View {
    /// The locale the app is running in, so the money column formats — and
    /// aligns — the way its reader writes numbers. Populated from the app's
    /// localization service each frame, so switching language on the Theme page
    /// re-formats and re-aligns this column with it.
    @Environment(\.locale) private var locale

    /// The width the reflow demo wraps its prose into. Published once per
    /// frame and stable across measure and render, which a `GeometryReader`
    /// here would not be — a reader is greedy in HEIGHT too, and inside this
    /// page's `ScrollView` that would give the section the whole viewport.
    @Environment(\.terminalWidth) private var terminalWidth

    /// Whether the bullet hangs off the stack's alignment line.
    @State private var hangBullet = true

    /// How far the third guide demo pushes its own alignment line, in cells.
    /// A guide is just a number, so a stepper can drive one directly.
    @State private var guideOffset = 0

    /// Whether the chips flow onto wrapped lines or stack in one column.
    @State private var flowChipsLayout = true

    /// How far right the ZStack demos' TOP layer is drawn, in cells. One slider
    /// for all five, because the point being made is the same in each: the top
    /// layer owns the cells it lands on and nothing shows through, so what
    /// changes as it slides is only WHICH cells those are.
    @State private var zstackTopOffset = 0.0

    /// The furthest right the ZStack demos' top layer slides. Every band in the
    /// section is sized so its label still fits inside at this offset.
    private static let zstackMaxOffset = 6.0

    /// Which axes the resize demo offers, driven by the toggles beside it.
    @State private var resizableWidth = true
    @State private var resizableHeight = true

    /// The demo box: flexible inside, bounded outside — it fills whatever the
    /// resizable wrapper offers, and the wrapper offers the range's ceiling
    /// until someone drags it. A FIXED frame in here would pin the border and
    /// the resize would only pad around it, which is right: a fixed size is the
    /// author saying "this size".
    ///
    /// The size is reported from inside, through a `GeometryReader`, so it is
    /// the size the content was actually given rather than the size anybody
    /// asked for — and it updates as the drag runs.
    @ViewBuilder
    private var resizableBox: some View {
        let box = GeometryReader { proxy in
            VStack(alignment: .center, spacing: 0) {
                Spacer()
                Text("page.layout.resizableBody")
                Text(verbatim: "\(proxy.size.width) × \(proxy.size.height)")
                    .foregroundStyle(.palette.foregroundSecondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .border(.palette.border)

        // An axis the user turned off is the LAYOUT's business again, and the
        // content inside is greedy — so without a frame on that axis the box
        // fills the page rather than staying a box. The size it holds still at
        // is the middle of the range the other axis is bounded to.
        switch (resizableWidth, resizableHeight) {
        case (true, true):
            box.userResizable(width: 12...40, height: 3...8)
        case (true, false):
            box.frame(height: 6).userResizable(width: 12...40)
        case (false, true):
            box.frame(width: 30).userResizable(height: 3...8)
        case (false, false):
            box.frame(width: 30, height: 6)
        }
    }

    /// The rows the windowed `LazyVStack` rendered in the last frame.
    @State private var renderedRows: Set<Int> = []

    /// The rows measured (layout participation) in the last sampling window —
    /// genuinely instrumented via `.onRenderPass`, not inferred.
    @State private var measuredRows: Set<Int> = []

    /// Raw sink the instrumentation callbacks write into mid-pass.
    @State private var measureSink = LazyMeasureSink()

    private let lazyRowCount = 40

    /// Amounts whose whole parts differ in width, so aligning on the decimal
    /// point is visibly not the same as aligning on either edge.
    ///
    /// Numbers rather than pre-split strings, because the point of the demo is
    /// that the alignment follows the CONTENT — and the content is whatever the
    /// reader's locale makes of these. In English `1240.05` is "1,240.05" and
    /// the line to align on is a full stop; in German it is "1.240,05" and the
    /// line is a comma, with a full stop three digits earlier that must not be
    /// mistaken for it.
    private static let amounts: [Double] = [7.5, 1240.05, 96.125, 3.7, 58021.4]

    /// One line of the acrostic, split around the letter that sits on the spine.
    ///
    /// Deliberately not localized — the same call `OutlineDemoTree` makes about
    /// path names, for a stronger reason: the poem's point is that its seventh
    /// column spells a word, and no translation can be asked to keep that.
    struct AcrosticLine: Hashable {
        let before: String
        let letter: Character
        let after: String
    }

    /// Seven lines whose spine reads "aligned".
    private static let acrostic = [
        AcrosticLine(before: "we st", letter: "a", after: "rt with a line,"),
        AcrosticLine(before: "and every ", letter: "l", after: "etter finds it —"),
        AcrosticLine(before: "the column ", letter: "i", after: "s not a margin"),
        AcrosticLine(before: "but a lon", letter: "g", after: " thread"),
        AcrosticLine(before: "drawn dow", letter: "n", after: " the page,"),
        AcrosticLine(before: "holding ", letter: "e", after: "ach row"),
        AcrosticLine(before: "in one accor", letter: "d", after: "."),
    ]

    /// A block of prose with one word in it that has to line up with the other
    /// blocks' words, whatever the wrap does.
    struct Keyworded {
        let before: String
        let keyword: String
        let after: String
    }

    /// The keyword sits early in the first block, in the middle of the second and
    /// at the very end of the third, so the guide has visibly different amounts
    /// of text to hoist above it in each column. With the word in the same place
    /// in all three the blocks line up almost by accident, and the demo shows
    /// nothing the eye could not have got from a plain row.
    private static let keywordBlocks = [
        Keyworded(
            before: "the child",
            keyword: "answers",
            after: "first, and the stack takes the number it is given: a guide is"
                + " a question asked of the content, never a position imposed on it."),
        Keyworded(
            before: "the wrap moves the words about as the terminal changes width,"
                + " and the row this word lands on",
            keyword: "answers",
            after: "differently every time — so a column written down once would"
                + " be wrong by the second resize."),
        Keyworded(
            before: "the guide is recomputed from the wrap rather than remembered"
                + " from the last one, which is how a column can go on following"
                + " the content wherever the content",
            keyword: "answers",
            after: "."),
    ]

    /// How wide each of the three prose columns is, given the terminal and the
    /// two cells of gap between them. Floored so a narrow terminal still gets
    /// something wrappable rather than a division by nothing.
    private var keywordColumnWidth: Int {
        max(12, (terminalWidth - 8) / Self.keywordBlocks.count)
    }

    /// A locale whose decimal separator is not this one's, so the pair of
    /// columns always shows the contrast rather than the same thing twice.
    private var contrastingLocale: Locale {
        (locale.decimalSeparator ?? ".") == "," ? Locale(identifier: "en_US") : Locale(identifier: "de_DE")
    }

    /// One column of amounts, formatted and aligned for `columnLocale`.
    private func amountColumn(in columnLocale: Locale) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: columnLocale.identifier)
                .foregroundStyle(.palette.foregroundTertiary)
            VStack(alignment: .decimalPoint, spacing: 0) {
                ForEach(Self.amounts, id: \.self) { amount in
                    let parts = localizedParts(of: amount, in: columnLocale)
                    HStack(spacing: 0) {
                        Text(parts.whole)
                        Text(parts.separator)
                            .foregroundStyle(.palette.accent)
                        Text(parts.fraction)
                            .foregroundStyle(.palette.foregroundSecondary)
                    }
                    // The guide sits on the ROW, not on the separator inside
                    // it: a stack reads the guides of the children it places,
                    // and a guide set deeper down does not travel up through
                    // the row to reach it. (SwiftUI resolves a custom alignment
                    // recursively, so there the guide can sit on the point
                    // itself — the gap is recorded in
                    // `SwiftUI-compatibility.md`.) The line is still the
                    // content's own: the separator sits exactly past the whole
                    // part, in CELLS, and the whole part is whatever this
                    // locale's grouping made of it.
                    .alignmentGuide(.decimalPoint) { _ in
                        Double(localizedParts(of: amount, in: columnLocale).whole.strippedLength)
                    }
                }
            }
            .border(.brightBlack)
        }
    }

    /// An amount formatted for ``locale``, split at the decimal separator that
    /// locale actually uses.
    ///
    /// Searched from the END, which is what makes it right in both directions:
    /// English writes "1,240.05", where the separator appears once, and German
    /// writes "1.240,05", where a full stop appears first and means something
    /// else entirely.
    private func localizedParts(of amount: Double, in numberLocale: Locale)
        -> (whole: String, separator: String, fraction: String)
    {
        let text = amount.formatted(
            .number.grouping(.automatic).precision(.fractionLength(0...3)).locale(numberLocale))
        let separator = numberLocale.decimalSeparator ?? "."
        guard let split = text.range(of: separator, options: .backwards) else {
            return (text, "", "")
        }
        return (
            String(text[..<split.lowerBound]), separator, String(text[split.upperBound...])
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection("page.layout.section.vstack") {
                VStack(spacing: 0) {
                    Text("\(L("page.layout.item")) 1")
                    Text("\(L("page.layout.item")) 2")
                    Text("\(L("page.layout.item")) 3")
                }
                .border(.brightBlack)
            }

            DemoSection("page.layout.section.hstack") {
                HStack(spacing: 2) {
                    Text("page.layout.left")
                    Text("page.layout.center")
                    Text("page.layout.right")
                }
                .border()
            }

            DemoSection("page.layout.section.spacer") {
                HStack {
                    Text("page.layout.start")
                    Spacer()
                    Text("page.layout.end")
                }
                .border()
            }

            DemoSection("page.layout.section.paddingFrame") {
                HStack(spacing: 2) {
                    VStack {
                        Text(".padding()").dim()
                        Text("page.layout.padded")
                            .frame(width: 25, alignment: .center)
                            .padding(EdgeInsets(all: 1))
                            .border()  // Uses appearance default
                    }
                    VStack {
                        Text(".frame()").dim()
                        Text("page.layout.framed")
                            .frame(width: 15, alignment: .center)
                            .border()  // Uses appearance default
                    }
                }
            }

            DemoSection("page.layout.section.viewThatFits") {
                // A single row when there is room; the same items stacked
                // vertically when the terminal is too narrow for the row.
                ViewThatFits {
                    HStack(spacing: 2) {
                        Text("[ \(L("page.layout.profile")) ]")
                        Text("[ \(L("page.layout.settings")) ]")
                        Text("[ \(L("page.layout.signOut")) ]")
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text("[ \(L("page.layout.profile")) ]")
                        Text("[ \(L("page.layout.settings")) ]")
                        Text("[ \(L("page.layout.signOut")) ]")
                    }
                }
                .border(.brightBlack)
            }

            DemoSection("page.layout.section.zstack") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.layout.zstack.explain")
                        .foregroundStyle(.palette.foregroundSecondary)

                    // Slide every example's top layer at once: the partial
                    // overlaps are where the "no transparency, no blending"
                    // claim above is actually visible, and they only appear
                    // once the layers stop lining up.
                    //
                    // Each band below is wide enough that its top layer, from
                    // where alignment puts it, still fits inside at the full
                    // offset: a centred label of width L needs a band of at
                    // least L + 2 × the maximum offset. `.offset` does not clip
                    // — the displaced content paints wherever it lands, border
                    // included — and a label chewing through the box's right
                    // edge reads as a rendering fault rather than as the point
                    // being made.
                    HStack(spacing: 1) {
                        Slider(value: $zstackTopOffset, in: 0...Self.zstackMaxOffset, step: 1) {
                            Text("page.layout.zstack.offset")
                                .foregroundStyle(.palette.foregroundSecondary)
                        }
                        Text(verbatim: "+\(Int(zstackTopOffset))")
                            .bold()
                            .foregroundStyle(.palette.accent)
                    }

                    // 1 — What it does. Children stack back-to-front and
                    // alignment positions them within the union of their sizes.
                    Text("page.layout.zstack.case1")
                        .foregroundStyle(.palette.foregroundTertiary)
                    ZStack(alignment: .center) {
                        Text(String(repeating: "▒", count: 28)).foregroundStyle(.palette.accent)
                        Text(" \(L("page.layout.onTop")) ").bold().inverted()
                            .offset(x: Int(zstackTopOffset))
                    }
                    .border(.brightBlack)

                    // 2 — There is no transparency, and this is the demo that
                    // says so. The label's own SPACES are cells like any other,
                    // so they punch a hole in the band rather than letting it
                    // through. Beside it, the same label with no padding: the
                    // hole shrinks to exactly the glyphs.
                    Text("page.layout.zstack.case2")
                        .foregroundStyle(.palette.foregroundTertiary)
                    HStack(spacing: 3) {
                        ZStack(alignment: .center) {
                            Text(String(repeating: "▒", count: 22))
                                .foregroundStyle(.palette.accent)
                            Text(verbatim: "   \(L("page.layout.zstack.word"))   ")
                                .offset(x: Int(zstackTopOffset))
                        }
                        .border(.brightBlack)
                        ZStack(alignment: .center) {
                            Text(String(repeating: "▒", count: 20))
                                .foregroundStyle(.palette.accent)
                            Text(verbatim: L("page.layout.zstack.word"))
                                .offset(x: Int(zstackTopOffset))
                        }
                        .border(.brightBlack)
                    }

                    // 3 — Nor is there any blending. Two words over each other
                    // give the top one's cells, not a mixture of both; the
                    // lower one survives only where the upper does not reach.
                    Text("page.layout.zstack.case3")
                        .foregroundStyle(.palette.foregroundTertiary)
                    ZStack(alignment: .leading) {
                        Text(verbatim: "UNDERNEATH·UNDERNEATH")
                            .foregroundStyle(.palette.foregroundSecondary)
                        Text(verbatim: "OVER")
                            .bold()
                            .foregroundStyle(.palette.warning)
                            .offset(x: Int(zstackTopOffset))
                    }
                    .border(.brightBlack)

                    // 4 — What to reach for instead. `.opacity` is not
                    // compositing: it moves a COLOUR toward the background and
                    // the cell stays as opaque as it was, which is why it can
                    // fade text that has nothing behind it and cannot show what
                    // does.
                    Text("page.layout.zstack.case4")
                        .foregroundStyle(.palette.foregroundTertiary)
                    ZStack(alignment: .center) {
                        Text(String(repeating: "▒", count: 36)).foregroundStyle(.palette.accent)
                        Text(" \(L("page.layout.zstack.faded")) ")
                            .foregroundStyle(.palette.foreground)
                            .opacity(0.45)
                            .offset(x: Int(zstackTopOffset))
                    }
                    .border(.brightBlack)

                    // 5 — Backgrounds, which is where "the last child to draw
                    // a cell owns it" stops being an abstraction. Both layers
                    // paint a background across their whole box, including the
                    // cells their text does not use, so the top layer's colour
                    // arrives as a solid block with a hard edge — no tint of
                    // the layer beneath anywhere in it, and no seam. Slide it
                    // and the lower background reappears cell for cell exactly
                    // where the upper one stops.
                    Text("page.layout.zstack.case5")
                        .foregroundStyle(.palette.foregroundTertiary)
                    ZStack(alignment: .leading) {
                        // The lower block's own label sits at its far end,
                        // beyond anything the upper block can reach, so what
                        // moves in this demo is the colours rather than a word
                        // being eaten a letter at a time.
                        Text("page.layout.zstack.under")
                            .padding(.trailing, 1)
                            .frame(width: 36, alignment: .trailing)
                            .foregroundStyle(.palette.background)
                            .background(.palette.info)
                        Text("page.layout.zstack.over")
                            .frame(width: 12, alignment: .center)
                            .foregroundStyle(.palette.background)
                            .background(.palette.warning)
                            .offset(x: Int(zstackTopOffset))
                    }
                    .border(.brightBlack)
                }
            }

            DemoSection("page.layout.section.alignmentGuide") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.layout.guideExplain")
                        .foregroundStyle(.palette.foregroundSecondary)

                    // 1 — A guide read off the view's OWN dimensions.
                    //
                    // With the bullet's leading guide at its own TRAILING edge,
                    // the bullet hangs to the left of the line and everything
                    // else shifts right to meet it, so the column ends up WIDER
                    // than its widest child. The border is what makes that
                    // visible, and it is the whole point: a guide moves the
                    // line, and the line decides the stack's width.
                    Text("page.layout.guideCase1")
                        .foregroundStyle(.palette.foregroundTertiary)
                    Toggle("page.layout.guideToggle", isOn: $hangBullet)

                    VStack(alignment: .leading, spacing: 0) {
                        if hangBullet {
                            Text("•")
                                .foregroundStyle(.palette.accent)
                                .alignmentGuide(.leading) { $0[.trailing] }
                        } else {
                            Text("•").foregroundStyle(.palette.accent)
                        }
                        Text("page.layout.guideItem")
                        Text("page.layout.guideItem2")
                    }
                    .border(.brightBlack)

                    // 2 — A guide that is a plain NUMBER, driven by a stepper.
                    //
                    // Nothing about a guide requires it to be an edge: the
                    // closure returns a position, and any expression will do.
                    // Stepping it moves one row's line while its neighbours
                    // stay put, which is the clearest way to see that alignment
                    // is per-child and not a property of the stack.
                    Text("page.layout.guideCase2")
                        .foregroundStyle(.palette.foregroundTertiary)
                    // No value in the label: `Stepper` prints its own read-out,
                    // and two copies of the same number read as a bug.
                    Stepper("page.layout.guideOffsetLabel", value: $guideOffset, in: -6...6)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("page.layout.guideFixed")
                        Text("page.layout.guideMoving")
                            .foregroundStyle(.palette.accent)
                            .alignmentGuide(.leading) { _ in Double(-guideOffset) }
                        Text("page.layout.guideFixed2")
                    }
                    .border(.brightBlack)

                    // 3 — A CUSTOM alignment: a line of one's own.
                    //
                    // `.leading` and `.trailing` can only align edges. A custom
                    // `AlignmentID` names a line that means something to the
                    // content — here the decimal point — and every row places
                    // it wherever its own text puts it. The numbers line up on
                    // the point even though they share no edge and no width.
                    Text("page.layout.guideCase3")
                        .foregroundStyle(.palette.foregroundTertiary)

                    // The same amounts twice, in two locales, each column
                    // aligning on the separator ITS locale writes. Side by side
                    // because that is the part worth seeing: the second column
                    // has a full stop in it that is NOT the point, and a column
                    // aligned on "the full stop" would be three digits out.
                    HStack(alignment: .top, spacing: 4) {
                        amountColumn(in: locale)
                        amountColumn(in: contrastingLocale)
                    }

                    // 4 — The same idea, with nothing numeric about it.
                    //
                    // A guide is a number the CONTENT chooses, so it can be
                    // anything the content can find — including "the letter I
                    // want in the column". Read the accented letters downward.
                    Text("page.layout.guideCase4")
                        .foregroundStyle(.palette.foregroundTertiary)

                    VStack(alignment: .spine, spacing: 0) {
                        ForEach(Self.acrostic, id: \.self) { line in
                            HStack(spacing: 0) {
                                Text(verbatim: line.before)
                                Text(verbatim: String(line.letter))
                                    .bold()
                                    .foregroundStyle(.palette.accent)
                                Text(verbatim: line.after)
                            }
                            .alignmentGuide(.spine) { _ in
                                Double(line.before.strippedLength)
                            }
                        }
                    }
                    .border(.brightBlack)

                    // 5 — A guide across a VERTICAL alignment, which is where
                    // this stops being a curiosity.
                    //
                    // Three blocks of prose, each with one word that matters,
                    // side by side. Resize the terminal: the text reflows, the
                    // word lands on a different line of its own block every
                    // time, and the three stay on ONE row of the screen.
                    //
                    // The catch, and the lesson: you cannot align on something
                    // whose position you have not decided. A `Text` that wraps
                    // itself knows which row its keyword ended on and cannot
                    // tell anyone, so each block wraps its own words here and
                    // reports the row it found. That is the whole trick.
                    Text("page.layout.guideCase5")
                        .foregroundStyle(.palette.foregroundTertiary)

                    HStack(alignment: .keywordRow, spacing: 2) {
                        ForEach(Self.keywordBlocks, id: \.before) { block in
                            KeywordBlock(block: block, width: keywordColumnWidth)
                                // On the child the STACK places, not inside the
                                // block's own body — a guide set deeper down
                                // does not travel up to the stack that reads it.
                                .alignmentGuide(.keywordRow) { _ in
                                    Double(
                                        KeywordBlock.keywordRow(
                                            of: block, width: keywordColumnWidth))
                                }
                        }
                    }
                    .border(.brightBlack)
                }
            }

            DemoSection("page.layout.section.geometryReader") {
                // The one thing an app could not work around before: reading the
                // space it was actually given. Resize the terminal and watch both
                // the numbers and the chosen arrangement change.
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.layout.geometryExplain")
                        .foregroundStyle(.palette.foregroundSecondary)

                    GeometryReader { proxy in
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 1) {
                                Text("page.layout.geometryOffered")
                                    .foregroundStyle(.palette.foregroundSecondary)
                                Text("\(proxy.size.width)×\(proxy.size.height)")
                                    .foregroundStyle(.palette.accent)
                                    .bold()
                                Text("page.layout.geometryCells")
                                    .foregroundStyle(.palette.foregroundTertiary)
                            }
                            if proxy.size.width >= 60 {
                                Text("page.layout.geometryWide")
                                    .foregroundStyle(.palette.success)
                            } else {
                                Text("page.layout.geometryNarrow")
                                    .foregroundStyle(.palette.warning)
                            }
                        }
                    }
                    .frame(height: 2)
                    .border(.brightBlack)
                }
            }

            DemoSection("page.layout.section.customLayout") {
                // `Flow` is a real custom Layout — no stack arranges things this
                // way. `AnyLayout` erases the two so the switch keeps ONE
                // identity, and the chips are not rebuilt when it flips.
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.layout.flowExplain")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Toggle("page.layout.flowToggle", isOn: $flowChipsLayout)

                    let layout = flowChipsLayout ? AnyLayout(Flow()) : AnyLayout(VStackLayout())
                    layout {
                        ForEach(flowChips, id: \.self) { chip in
                            Text(" \(chip) ").inverted()
                        }
                    }
                    .border(.brightBlack)
                }
            }

            DemoSection("page.layout.section.divider") {
                VStack(alignment: .leading, spacing: 0) {
                    Text("page.layout.above")
                    Divider()
                    Text("page.layout.between")
                    Divider(character: "═")
                    Text("page.layout.below")
                }
                .border(.brightBlack)
            }

            DemoSection("page.layout.section.lazy") {
                // Same API shape as VStack/HStack, but rows are realised lazily.
                // Inside a ScrollView the LazyVStack windows to the visible
                // viewport — only those rows render (and fire onAppear). Each row
                // reports its index via a preference when it renders, so the
                // read-out below is exactly the on-screen set; scroll the list
                // (wheel, or Tab to focus it and use ↑/↓/PageUp/PageDown) and
                // watch the range-set slide.
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.layout.lazyExplain")
                        .foregroundStyle(.palette.foregroundSecondary)

                    HStack(spacing: 1) {
                        Text("page.layout.lazyRendered")
                            .foregroundStyle(.palette.foregroundSecondary)
                        Text(rangeSetDescription(renderedRows))
                            .foregroundStyle(.palette.accent)
                            .bold()
                        Text("(\(renderedRows.count)/\(lazyRowCount))")
                            .foregroundStyle(.palette.foregroundTertiary)
                    }
                    // Layout participation ≠ rendering: the stack may measure
                    // rows (to size the scroll extent) that it never draws.
                    // Reported by the framework's own `.onRenderPass` hook.
                    HStack(spacing: 1) {
                        Text("page.layout.lazyMeasured")
                            .foregroundStyle(.palette.foregroundSecondary)
                        Text(rangeSetDescription(measuredRows))
                            .foregroundStyle(.palette.success)
                            .bold()
                        Text("(\(measuredRows.count)/\(lazyRowCount))")
                            .foregroundStyle(.palette.foregroundTertiary)
                    }

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(0..<lazyRowCount, id: \.self) { index in
                                Text("\(L("page.layout.lazyRow")) \(index)")
                                    .onRenderPass { pass in
                                        if pass == .measure { measureSink.record(index) }
                                    }
                                    .preference(key: LazyRenderedRowsKey.self, value: [index])
                            }
                        }
                    }
                    .frame(height: 8)
                    .border(.palette.border)
                    .onPreferenceChange(LazyRenderedRowsKey.self) { renderedRows = $0 }
                    .task {
                        await runMeasureSampler()
                    }

                    LazyHStack(spacing: 2) {
                        Text("\(L("page.layout.col")) 1")
                        Text("\(L("page.layout.col")) 2")
                        Text("\(L("page.layout.col")) 3")
                    }
                    .border(.brightBlack)
                }
            }

            // `.userResizable` — the size becomes the user's, not the layout's.
            // Bounded on both axes here so the demo shows the limits holding;
            // the ranges ARE the axis selection, so a `.userResizable(width:)`
            // alone would leave the height to the layout.
            DemoSection("page.layout.resizableSection") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.layout.resizableHint")
                        .foregroundStyle(.palette.foregroundSecondary)
                    // Naming an axis is what makes it resizable, so the toggles
                    // choose between the four spellings of the modifier rather
                    // than setting a property on one of them. Turning an axis
                    // off gives its size back to the layout — which is the same
                    // thing Escape does, and worth seeing.
                    HStack(spacing: 3) {
                        Toggle("page.layout.resizableWidth", isOn: $resizableWidth)
                        Toggle("page.layout.resizableHeight", isOn: $resizableHeight)
                    }
                    resizableBox
                }
            }

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader("menu.item.layout")
        }
    }

    /// Snapshots the mid-pass measure sink on a safe async cadence — the
    /// `.onRenderPass` callbacks fire during layout/render, where view state
    /// must not be mutated, so the sink is drained from here instead.
    private func runMeasureSampler() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(300))
            let measured = measureSink.snapshot()
            if !measured.isEmpty, measured != measuredRows {
                measuredRows = measured
            }
        }
    }

    /// Collapses a set of indices into a compact range-set string, e.g.
    /// `{3,4,5,7}` → `"3–5, 7"`. `"—"` when empty.
    private func rangeSetDescription(_ set: Set<Int>) -> String {
        guard !set.isEmpty else { return "—" }
        let sorted = set.sorted()
        var runs: [String] = []
        var start = sorted[0]
        var previous = sorted[0]
        func flush() { runs.append(start == previous ? "\(start)" : "\(start)–\(previous)") }
        for value in sorted.dropFirst() {
            if value == previous + 1 {
                previous = value
            } else {
                flush()
                start = value
                previous = value
            }
        }
        flush()
        return runs.joined(separator: ", ")
    }
}

// MARK: - A custom alignment

/// The line a decimal point sits on.
///
/// `.leading` and `.trailing` can only ever align an edge. An `AlignmentID`
/// names a line the CONTENT cares about, and each child says where its own
/// copy of that line is — so a column of numbers can line up on the point
/// while sharing neither a width nor an edge.
private enum DecimalPointID: AlignmentID {
    /// Where the guide sits on a view that never mentions it. Leading, so a row
    /// without a decimal point still lines up somewhere predictable rather than
    /// floating.
    static func defaultValue(in context: ViewDimensions) -> Double { 0 }
}

extension HorizontalAlignment {
    /// Aligns children on their decimal point. See ``DecimalPointID``.
    fileprivate static let decimalPoint = Self(DecimalPointID.self)
}

/// The column an acrostic's letters stand in.
private enum SpineID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> Double { 0 }
}

extension HorizontalAlignment {
    /// Aligns children on the letter each has chosen. See ``SpineID``.
    fileprivate static let spine = Self(SpineID.self)
}

/// The ROW a block's keyword wrapped onto — a vertical line, not a horizontal
/// one, which is the half of alignment that only pays off when something moves.
private enum KeywordRowID: AlignmentID {
    /// The first row, so a block with nothing to say still starts at the top
    /// rather than floating.
    static func defaultValue(in context: ViewDimensions) -> Double { 0 }
}

extension VerticalAlignment {
    /// Aligns blocks on the row their keyword wrapped onto. See ``KeywordRowID``.
    fileprivate static let keywordRow = Self(KeywordRowID.self)
}

/// A paragraph that wraps itself, so it can say which row its keyword ended on.
///
/// A `Text` wraps too, and better — but it does it while rendering and keeps
/// the answer to itself, and a guide has to be a number the stack can read
/// while it is placing children. So the words are broken here, where the answer
/// is in hand.
private struct KeywordBlock: View {
    let block: LayoutPage.Keyworded
    let width: Int

    /// One word of the paragraph, and whether it is THE word.
    private struct Word {
        let text: String
        let isKeyword: Bool
    }

    private static func words(of block: LayoutPage.Keyworded) -> [Word] {
        block.before.split(separator: " ").map { Word(text: String($0), isKeyword: false) }
            + [Word(text: block.keyword, isKeyword: true)]
            + block.after.split(separator: " ").map { Word(text: String($0), isKeyword: false) }
    }

    /// Greedy wrap, in CELLS — the same unit the terminal measures in, so a
    /// wide character costs what it draws.
    private static func rows(of block: LayoutPage.Keyworded, width: Int) -> [[Word]] {
        var rows: [[Word]] = [[]]
        var used = 0
        for word in words(of: block) {
            let cells = word.text.strippedLength
            if used > 0, used + 1 + cells > width {
                rows.append([word])
                used = cells
            } else {
                used += used > 0 ? cells + 1 : cells
                rows[rows.count - 1].append(word)
            }
        }
        return rows
    }

    /// Which wrapped row the keyword landed on — the guide's value.
    ///
    /// Static, and called from the CALL SITE rather than from `body`: a stack
    /// reads the guides of the children it places, and a guide set inside a
    /// child's own body does not travel up to reach it. (The same rule the
    /// decimal-point column above is written around.)
    static func keywordRow(of block: LayoutPage.Keyworded, width: Int) -> Int {
        rows(of: block, width: width).firstIndex { $0.contains(where: \.isKeyword) } ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let wrapped = Array(Self.rows(of: block, width: width).enumerated())
            ForEach(wrapped, id: \.offset) { _, row in
                HStack(spacing: 1) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, word in
                        if word.isKeyword {
                            Text(verbatim: word.text)
                                .bold()
                                .foregroundStyle(.palette.accent)
                        } else {
                            Text(verbatim: word.text)
                                .foregroundStyle(.palette.foregroundSecondary)
                        }
                    }
                }
            }
        }
        .frame(width: width, alignment: .leading)
    }
}
