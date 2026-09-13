//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContainerViewCore.swift
//
//  The procedural half of ``ContainerView``: the `Renderable` + `Layoutable`
//  core that assembles a titled, bordered box out of a body and a footer. Split
//  out of `ContainerView.swift` because the two together outgrew the file-length
//  budget — the public view, its config and the shared render/measure entry
//  points stay there, and everything that draws lives here.
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Container View Core

/// Internal rendering implementation for ContainerView.
///
/// This private struct contains all the complex rendering logic, allowing
/// ContainerView to have a proper `body: some View` that enables modifiers
/// to work correctly.
struct _ContainerViewCore<Content: View, Footer: View>: View, Renderable, Layoutable {
    /// The container title (rendered in border or header section).
    let title: String?

    /// The title color.
    let titleColor: Color?

    /// The main content.
    let content: Content

    /// The footer content (typically buttons).
    let footer: Footer?

    /// The container style configuration.
    let style: ContainerStyle

    /// The inner padding for the body.
    let padding: EdgeInsets

    /// Padding applied around the footer. A single source of truth shared by
    /// `renderToBuffer`, `sizeThatFits` and `verticalBudget` (in
    /// `ContainerView.swift`) so they cannot disagree about the footer's width
    /// budget.
    var footerPadding: EdgeInsets { EdgeInsets(horizontal: 1, vertical: 0) }

    /// Pads `buffer` to `width` cells, offsetting its content — and its hit
    /// regions/overlays — per `alignment`. A no-op for `.leading` (offset 0) or
    /// when the buffer already fills `width`. Used to place the footer; centring
    /// it here (at render, where the final width is known) rather than with a
    /// flexible frame avoids inflating the container to the full available width.
    private func aligned(_ buffer: FrameBuffer, toWidth width: Int, alignment: HorizontalAlignment) -> FrameBuffer {
        let offset = max(0, alignment.childOffset(childWidth: buffer.width, in: width))
        guard offset > 0 else { return buffer }
        let lines = buffer.lines.map { line -> String in
            let used = line.strippedLength
            let rightPad = max(0, width - offset - used)
            // Built in place (borrowed spaces, no `String(repeating:)` temporaries
            // or `+`-chain): byte-identical to the leading/trailing concatenation.
            var aligned = ""
            aligned.reserveCapacity(line.utf8.count + offset + rightPad)
            aligned += asciiSpaces(offset)
            aligned += line
            if rightPad > 0 { aligned += asciiSpaces(rightPad) }
            return aligned
        }
        return buffer.replacingLines(lines, overlayShiftX: offset)
    }

    var body: Never {
        fatalError("_ContainerViewCore renders via Renderable")
    }

    /// Measures the container analytically — mirroring `renderToBuffer`'s
    /// geometry but *measuring* the body and footer (cheap, and recursive
    /// through `Layoutable` children) instead of rendering the whole subtree
    /// and assembling its border chrome.
    ///
    /// `.border()` is a title- and footer-less `ContainerView`, so before this
    /// every bordered measure fell through `measureChild`'s render-to-measure
    /// fallback, which rendered the entire subtree to measure it — at the time
    /// *twice* (a second render at `naturalWidth + 8` probed flexibility, since
    /// retired). Nested borders multiplied that: the layout-heavy RenderHarness
    /// trees (`alignment`, `nested` — deeply nested `.border()`s) ran ~12× and
    /// ~45× slower than the border-free `frames` tree. Measuring instead of
    /// rendering removes that cost; the measure/render equivalence tests pin the
    /// two passes together.
    /// The context a structural child gets, with the axis this box lays it out
    /// along published on it — the same thing `_VStackCore` does for a real
    /// column, and for the same reader: ``Divider``.
    ///
    /// A multi-view body is an implicit column. `@ViewBuilder` packs it into a
    /// `TupleView`, whose `renderToBuffer` stacks the children vertically, and
    /// nothing in that path publishes an axis — so the body inherited the axis
    /// of whatever stack the BOX sits in. Inside an `HStack` that made a
    /// `Divider` between two stacked children a full-height `│`, which then
    /// took the interior's whole height and pushed the children after it out of
    /// the box.
    ///
    /// Not published for a single child, which is not stacked at all: a box
    /// around one view is a modifier (`.border()` is spelled as one), so it
    /// stays transparent to the axis and `Divider().border()` in a row remains
    /// the vertical rule it is in SwiftUI.
    func publishingStackAxis(
        _ context: RenderContext, stacking child: (any View)?
    ) -> RenderContext {
        guard let child, child is any ChildInfoProvider else { return context }
        return context.publishingContainerAxis(.vertical)
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        // Resolve the space we were offered (proposal wins over the context,
        // exactly as renderChild sets availableWidth/Height before rendering).
        var base = context
        base.availableWidth = proposal.width ?? context.availableWidth
        base.availableHeight = proposal.height ?? context.availableHeight

        // Inner context between the side borders (width − 2 when bordered, full
        // width when borderless), matching render.
        let hasBorder = style.hasBorder
        var innerContext = base.forBorderedContent(hasBorder: hasBorder)
        innerContext.environment.focusIndicator = nil
        // A detented sheet's height belongs to the box, and to this box only —
        // see ``EnvironmentValues/sheetDetentHeight``. Consumed here so a
        // nested container does not stretch to the sheet's height as well.
        let sheetHeight = base.environment.sheetDetentHeight.map {
            min($0, max(0, base.availableHeight))
        }
        innerContext.environment.sheetDetentHeight = nil
        let innerWidthAvailable = innerContext.availableWidth

        // The body and footer are distinct structural children, so they get
        // distinct identities (index 0 / 1) rather than both inheriting the
        // container's. Otherwise their `@State` would share a storage slot, and
        // — since a footerless container's empty footer measures to height 0,
        // giving the body the same available height — they would collide on a
        // memoized-measurement key. Must match `renderToBuffer` exactly.
        let bodyInner = publishingStackAxis(
            innerContext.withChildIdentity(type: Content.self, index: 0), stacking: content)
        let footerInner = publishingStackAxis(
            innerContext.withChildIdentity(type: Footer.self, index: 1), stacking: footer)

        // Vertical chrome: top + bottom border (only when bordered), plus the
        // optional footer separator — the same arithmetic renderToBuffer uses.
        let hasFooter = footer != nil
        let borderRows = hasBorder ? 2 : 0
        let chromeHeight = borderRows + ((hasFooter && style.showFooterSeparator) ? 1 : 0)
        let innerAvailableHeight = RenderContext.extent(
            base.availableHeight, insideChrome: chromeHeight)

        // Footer at its natural (full inner) width: gives the height the body
        // must share and the footer's contribution to the inner-width vote.
        var footerNaturalWidth = 0
        var footerNaturalHeight = 0
        var footerFlexibleHeight = false
        if let footerView = footer {
            var footerContext = footerInner
            footerContext.availableHeight = innerAvailableHeight
            let size = measureChild(
                footerView.padding(footerPadding),
                proposal: ProposedSize(width: innerWidthAvailable, height: innerAvailableHeight),
                context: footerContext)
            footerNaturalWidth = min(size.width, innerWidthAvailable)
            footerNaturalHeight = min(size.height, innerAvailableHeight)
            footerFlexibleHeight = size.isHeightFlexible
        }

        // Body into the space the chrome and footer leave. A scrolling body
        // goes through the SAME routine the render uses — it measures the
        // wrapped tree and applies the preferred-width policy, and measuring it
        // any other way here would put this pass and the render back into
        // disagreement (see `scrollableBodySize`).
        let bodyAvailableHeight = RenderContext.extent(
            innerAvailableHeight, insideChrome: footerNaturalHeight)
        var bodyContext = bodyInner
        bodyContext.availableHeight = bodyAvailableHeight
        let bodyWidth: Int
        let bodyHeight: Int
        // A scrolling body is pinned to a definite height by `scrollableBody`,
        // so it does not stretch its container. (The wrapped tree cannot answer
        // this: a ScrollView always reports flexible, masking its content.)
        var bodyFlexibleHeight = false
        if style.scrollsOverflowingBody {
            let size = scrollableBodySize(
                availableHeight: bodyAvailableHeight, innerWidth: innerWidthAvailable,
                context: bodyContext)
            bodyWidth = min(size.width, innerWidthAvailable)
            bodyHeight = min(size.height, bodyAvailableHeight)
        } else {
            let bodySize = measureChild(
                content.padding(padding),
                proposal: ProposedSize(width: innerWidthAvailable, height: bodyAvailableHeight),
                context: bodyContext)
            bodyWidth = min(bodySize.width, innerWidthAvailable)
            bodyHeight = min(bodySize.height, bodyAvailableHeight)
            bodyFlexibleHeight = bodySize.isHeightFlexible
        }

        // Bordering empty content with no footer produces nothing: render's
        // `bodyBuffer.isEmpty` short-circuit returns the (empty) body as-is,
        // WITHOUT the border chrome. A body that measures to zero width or
        // height renders to an empty buffer — e.g. `EmptyView().border()`, or
        // a border squeezed so narrow (`availableWidth <= 2`) that no content
        // column survives. Mirror that here so a collapsed border doesn't
        // measure two rows/cols taller than it renders.
        if (bodyWidth == 0 || bodyHeight == 0) && footer == nil {
            return ViewSize.fixed(bodyWidth, bodyHeight)
        }

        // Inner width: the widest of title / body / footer, capped at the
        // space between the side borders.
        let titleWidth = title.map { $0.strippedLength + 4 } ?? 0
        let contentBasedWidth = max(titleWidth, bodyWidth, footerNaturalWidth)
        let innerWidth = base.resolveContainerWidth(
            contentWidth: contentBasedWidth, innerAvailableWidth: innerWidthAvailable)

        // Footer re-measured at the resolved inner width — a narrower footer
        // may wrap taller, exactly as the constrained re-render does.
        var footerFinalHeight = 0
        if let footerView = footer {
            let footerWidth = max(0, innerWidth - footerPadding.leading - footerPadding.trailing)
            var footerContext = footerInner
            footerContext.availableWidth = footerWidth
            footerContext.availableHeight = innerAvailableHeight
            let size = measureChild(
                footerView.padding(footerPadding),
                proposal: ProposedSize(width: footerWidth, height: innerAvailableHeight),
                context: footerContext)
            footerFinalHeight = min(size.height, innerAvailableHeight)
        }

        let footerPresent = hasFooter && footerFinalHeight > 0
        let separator = (footerPresent && style.showFooterSeparator) ? 1 : 0
        // Top + bottom border rows / left + right border columns only when bordered.
        // A sheet's detent overrides the content's own answer — the box IS the
        // named height, and `renderToBuffer` pads its body to match.
        let totalHeight =
            sheetHeight
            ?? (borderRows / 2 + bodyHeight + separator + (footerPresent ? footerFinalHeight : 0)
                + borderRows / 2)
        let totalWidth = innerWidth + (hasBorder ? 2 : 0)

        // Width-flexibility is render-derived, not inherited from the body's
        // (sometimes soft) flag: `resolveContainerWidth` caps the inner width at
        // what's available, so the container fills exactly when its content
        // wants at least that much. Reading the child's `isWidthFlexible`
        // instead would mislabel a container whose body merely *wraps* (a
        // wrapping `Text`) as filling when it actually shrinks to content.
        let fillsWidth = contentBasedWidth >= innerWidthAvailable
        return ViewSize(
            width: min(totalWidth, max(0, base.availableWidth)),
            height: min(totalHeight, max(0, base.availableHeight)),
            isWidthFlexible: fillsWidth,
            isHeightFlexible: bodyFlexibleHeight || footerFlexibleHeight
        )
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let appearance = context.environment.appearance
        let effectiveBorderStyle = style.borderStyle ?? appearance.borderStyle
        let palette = context.environment.palette
        // Every frame of the border's colour, not just the one on screen: a
        // border handed an animating colour leaves runs for its own cells
        // (`borderRuns`), which is the whole point of the type.
        let borderAnimation =
            Self.animating(style.borderColor, context: context)?.resolved(with: palette)
            ?? AnimatedColor(palette.border)
        let borderColor = borderAnimation.current
        let hasBorder = style.hasBorder

        // Inner context for content between the side borders (width − 2 when
        // bordered, full width when borderless).
        // Padding width reduction is handled by PaddingModifier.adjustContext.
        var innerContext = context.forBorderedContent(hasBorder: hasBorder)

        // Consume focus indicator so nested containers don't also show it.
        let indicator = context.environment.focusIndicator
        innerContext.environment.focusIndicator = nil
        // Likewise the sheet detent's height: this box takes it, its children
        // do not (see ``EnvironmentValues/sheetDetentHeight``).
        let sheetHeight = context.environment.sheetDetentHeight.map {
            min($0, max(0, context.availableHeight))
        }
        innerContext.environment.sheetDetentHeight = nil

        // Distinct identities for the body and footer (see `sizeThatFits` — must
        // match it exactly so the two passes agree on identity, hence on
        // `@State` slots and focus IDs).
        let bodyInner = publishingStackAxis(
            innerContext.withChildIdentity(type: Content.self, index: 0), stacking: content)
        let footerInner = publishingStackAxis(
            innerContext.withChildIdentity(type: Footer.self, index: 1), stacking: footer)

        // Vertical chrome: top + bottom border (only when bordered), plus the
        // optional footer separator. The body and footer must share whatever is
        // left so the assembled container never grows taller than `availableHeight`.
        // The footer is measured first (without side-effects) so the body knows
        // how much vertical space is left. Real focus registration happens in
        // the constrained re-render below, after the body — preserving Tab order.
        // `verticalBudget` is shared with `bodyHeight(in:)`, which a `List` sizes
        // its rows by before it hands them over, so the two cannot disagree.
        let (chromeHeight, innerAvailableHeight, measuredFooter, bodyAvailableHeight) = verticalBudget(
            availableHeight: context.availableHeight, innerWidth: innerContext.availableWidth,
            footerContext: footerInner)
        let footerHeight = measuredFooter?.height ?? 0

        // Render the body into the space the chrome and footer leave.
        var bodyContext = bodyInner
        bodyContext.availableHeight = bodyAvailableHeight
        var bodyBuffer =
            style.scrollsOverflowingBody
            ? scrollableBody(
                availableHeight: bodyAvailableHeight, innerWidth: innerContext.availableWidth,
                context: bodyContext)
            : TUIkit.renderToBuffer(content.padding(padding), context: bodyContext)
                .clamped(toWidth: innerContext.availableWidth, height: bodyAvailableHeight)

        // A sheet's detent names a height for the box, so a body that does not
        // fill it gets the rest as empty interior — rows the border encloses,
        // rather than blank rows below the box. Content that CAN fill already
        // did: it was offered `bodyAvailableHeight`, which the host set from
        // the detent.
        if let sheetHeight {
            let bodyTarget = max(0, sheetHeight - chromeHeight - footerHeight)
            if bodyBuffer.height < bodyTarget, !bodyBuffer.isEmpty {
                bodyBuffer.lines.append(
                    contentsOf: repeatElement(
                        String(repeating: " ", count: bodyBuffer.width),
                        count: bodyTarget - bodyBuffer.height))
            }
        }

        // Bordering empty content with no footer produces nothing
        // (e.g. `EmptyView().border()`).
        if bodyBuffer.isEmpty && footer == nil {
            return bodyBuffer
        }

        // Inner width: the widest of title / body / footer, capped at the
        // space available between the side borders.
        let titleWidth = title.map { $0.strippedLength + 4 } ?? 0  // " Title " + borders
        let footerNaturalWidth = measuredFooter?.width ?? 0
        let contentBasedWidth = max(titleWidth, bodyBuffer.width, footerNaturalWidth)
        let innerWidth = context.resolveContainerWidth(
            contentWidth: contentBasedWidth,
            innerAvailableWidth: innerContext.availableWidth
        )

        // Re-render the footer constrained to the final inner width — this is
        // the real render and registers focus, after the body.
        let footerBuffer: FrameBuffer?
        if let footerView = footer {
            var footerContext = footerInner
            footerContext.availableWidth = max(0, innerWidth - footerPadding.leading - footerPadding.trailing)
            footerContext.availableHeight = innerAvailableHeight
            let rendered = TUIkit.renderToBuffer(footerView.padding(footerPadding), context: footerContext)
                .clamped(toWidth: innerWidth, height: innerAvailableHeight)
            // Place the (narrower-than-the-box) footer per the configured
            // alignment. A no-op for `.leading`; `.center`/`.trailing` shift the
            // content and its hit regions so a centred button stays clickable.
            footerBuffer = aligned(rendered, toWidth: innerWidth, alignment: style.footerAlignment)
        } else {
            footerBuffer = nil
        }

        let assembled =
            hasBorder
            ? renderStandardStyle(
                bodyBuffer: bodyBuffer,
                footerBuffer: footerBuffer,
                innerWidth: innerWidth,
                borderStyle: effectiveBorderStyle,
                borderColor: borderAnimation,
                context: context,
                focusIndicator: indicator
            )
            : renderBorderless(
                bodyBuffer: bodyBuffer,
                footerBuffer: footerBuffer,
                innerWidth: innerWidth,
                borderColor: borderColor,
                context: context
            )
        // Final guard: never exceed the space the container was given.
        return assembled.clamped(toWidth: context.availableWidth, height: context.availableHeight)
    }

    /// The body wrapped in a `ScrollView` so an over-tall one scrolls instead of
    /// being clipped, leaving the title (in the top border) and the footer
    /// pinned — they are assembled separately, so they are outside the scrolling
    /// region by construction.
    ///
    /// The wrapper is applied UNCONDITIONALLY, not only when the body
    /// overflows, so the body's identity path does not change as the terminal is
    /// resized across the overflow threshold. Wrapping conditionally would
    /// re-key every `@State` inside the dialog on the frame it starts scrolling
    /// — the colour picker would silently lose its selected tab on a resize.
    ///
    /// The explicit `.frame(height:)` is what makes the always-on wrapper safe.
    /// A `ScrollView` takes any DEFINITE proposed height wholesale, so simply
    /// nesting one would inflate every short dialog to the full content area
    /// (measured: `Dialog { 3 rows }` is 9 rows, but wrapping its body naively
    /// makes it 40 in a 40-row area). Pinning the frame to the body's own
    /// natural height while it fits keeps a short dialog exactly the size it is
    /// today — and with nothing to scroll, the ScrollView draws no chrome and
    /// takes no focus stop, so it is invisible until it is needed.
    /// The size a scrolling body will lay out at, and the width chosen for it.
    ///
    /// Shared by `sizeThatFits` and `scrollableBody` so the two passes cannot
    /// disagree — the whole class of bug this container has already produced
    /// twice.
    ///
    /// Measures the tree that will actually be RENDERED, wrapper and all.
    /// `@State` binds by identity and the ScrollView adds identity components,
    /// so measuring the BARE body resolved every `@State` inside it to a
    /// different box than the render — and reported the body at its INITIAL
    /// state forever. A dialog whose body had since grown (a colour picker
    /// switched to its 256-swatch tab, a disclosure opened) was built to the
    /// size it started at and scrolled with most of the screen still free.
    ///
    /// Neither axis is ever proposed, so the report comes from the content
    /// itself: a ScrollView passes an unproposed axis straight through to its
    /// child (its ideal size is its content's), which keeps a dialog hugging
    /// its content rather than filling the terminal, and yields the height AT
    /// the width being tried — the only width whose answer means anything for
    /// wrapped text.
    ///
    /// ## Choosing the width
    ///
    /// A dialog prefers ``EnvironmentValues/dialogPreferredWidth`` (100 cells
    /// by default) because long prose is unpleasant to read as very long lines.
    /// It spends more only when that genuinely buys vertical room: a paragraph
    /// re-wraps shorter as it widens, a fixed-width form does not. So the wider
    /// layout is taken only if it is actually shorter, and then at the
    /// NARROWEST width that reaches that height — a dialog that gains nothing
    /// from the space stays slim.
    private func scrollableBodySize(
        availableHeight: Int, innerWidth: Int, context: RenderContext
    ) -> (width: Int, height: Int) {
        // Measured against a generous budget: a nil height proposal is not
        // "unbounded" here, because every stack clamps its report to
        // `availableHeight` — measuring in `context` would return the capped
        // height and never reveal the overflow.
        //
        // Generous, and a ceiling all the same, so be exact about what it
        // bounds. NOT the dialog's height: that is clamped to the screen a
        // moment later, so a body of 9,000 lines and one of 4,096 size the
        // dialog identically. NOT the scrolling: the dialog renders a real
        // `ScrollView`, which measures its own content through
        // ``measureNaturalExtent``'s ladder and has no ceiling. What it bounds
        // is the WIDTH CHOICE below — two candidate widths whose bodies both
        // overflow the budget report the same height, tie, and the narrower
        // wins. For a body past the budget that is a cosmetic difference in a
        // case nobody has, and the alternatives are worse: the ladder returns
        // this same first rung here, because a `ScrollView` reports
        // `isHeightFlexible` and that is where the ladder stops.
        var probe = context
        probe.availableHeight = naturalExtentStartingBudget(forVisible: availableHeight)
        let probeView = ScrollView(.vertical) { content.padding(padding) }
        func measure(at width: Int) -> ViewSize {
            var sized = probe
            sized.availableWidth = max(1, width)
            return measureChild(
                probeView, proposal: ProposedSize(width: nil, height: nil), context: sized)
        }

        let preferred = min(innerWidth, max(1, context.environment.dialogPreferredWidth))
        var chosenWidth = preferred
        var chosen = measure(at: preferred)

        // A body that reports back WIDER than the width it was offered has a
        // definite natural width and cannot re-flow into anything narrower —
        // the 256-swatch grid with its numbers showing is 120 cells, full stop.
        // The preferred width is a ceiling on how wide a dialog should get for
        // COMFORT; applied to such a body it is not a ceiling but a guillotine,
        // and the grid lost every column past the 100th (visibly: the top row
        // stopped after the swatch for 14). Give it what it asked for, up to
        // the space that actually exists.
        if chosen.width > chosenWidth, innerWidth > chosenWidth {
            chosenWidth = min(innerWidth, chosen.width)
            chosen = measure(at: chosenWidth)
        }

        if chosen.height > availableHeight, innerWidth > chosenWidth, availableHeight > 0 {
            // It doesn't fit at the comfortable width. Widening is only worth it
            // if the content actually re-flows shorter.
            let widest = measure(at: innerWidth)
            if widest.height < chosen.height {
                // Aim to fit outright; failing that, for the least height going.
                let target = max(availableHeight, widest.height)
                var low = chosenWidth + 1
                var high = innerWidth
                chosenWidth = innerWidth
                chosen = widest
                // Binary search assumes height never grows as width grows, which
                // holds for wrapped text and reflowing grids. The result is
                // checked below rather than trusted, so content that violates it
                // degrades to the full width instead of laying out wrong.
                while low <= high {
                    let mid = low + (high - low) / 2
                    let size = measure(at: mid)
                    if size.height <= target {
                        chosenWidth = mid
                        chosen = size
                        high = mid - 1
                    } else {
                        low = mid + 1
                    }
                }
                if chosen.height > target {
                    chosenWidth = innerWidth
                    chosen = widest
                }
            }
        }
        return (min(max(chosen.width, 0), chosenWidth), max(chosen.height, 0))
    }

    private func scrollableBody(
        availableHeight: Int, innerWidth: Int, context: RenderContext
    ) -> FrameBuffer {
        let natural = scrollableBodySize(
            availableHeight: availableHeight, innerWidth: innerWidth, context: context)
        let naturalWidth = min(max(natural.width, 0), innerWidth)
        let height = min(max(natural.height, 0), availableHeight)
        // The ScrollView is ALWAYS in the tree, whether or not the body
        // overflows — only its frame changes. An earlier version wrapped only on
        // overflow, which is a structural difference: crossing the threshold
        // swapped `content` for `ScrollView { content }`, changing the identity
        // path of everything inside, so every `@State` in the body was recreated
        // and snapped back to its initial value.
        //
        // That was not theoretical. The colour picker's tab selection is a
        // `@State` in `_ColorPickerBody`; selecting a TALL tab (the 256 grid,
        // Named, Crayons, …) pushed the body past the threshold, which rebuilt
        // the state and reset the selection to `.rgb` — so the tab appeared not
        // to switch, and only a second click (with the wrapper now settled) took
        // effect. The short channel editors never crossed the threshold and so
        // always worked, which is what made the bug look like it was about
        // *which* tab was clicked.
        //
        // BOTH axes are pinned to what the probe measured. A ScrollView takes
        // any size it is GIVEN, so leaving either axis free would make the
        // dialog fill the terminal. Pinning the height to the natural height
        // while the body fits is also what keeps the always-present ScrollView
        // inert: nothing to scroll, so no indicators, no clipping and no focus
        // stop, and the container's own `clamped(toWidth:)` still does the
        // horizontal ellipsis.
        let overflows = natural.height > availableHeight && availableHeight > 0
        let scrolled = ScrollView(.vertical) { content.padding(padding) }
            .frame(
                width: naturalWidth,
                height: overflows ? height : max(natural.height, 0))
        return TUIkit.renderToBuffer(scrolled, context: context)
            .clamped(toWidth: innerWidth, height: availableHeight)
    }

    // MARK: - Standard Style Rendering

    /// Renders with title in top border (line, rounded, doubleLine, heavy).
    private func renderStandardStyle(
        bodyBuffer: FrameBuffer,
        footerBuffer: FrameBuffer?,
        innerWidth: Int,
        borderStyle: BorderStyle,
        borderColor: AnimatedColor,
        context: RenderContext,
        focusIndicator: AnimatedColor? = nil
    ) -> FrameBuffer {
        let palette = context.environment.palette
        let borderNow = borderColor.current
        var lines: [String] = []

        // Top border (with title if present)
        if let titleText = title {
            lines.append(
                BorderRenderer.standardTopBorder(
                    style: borderStyle,
                    innerWidth: innerWidth,
                    color: borderNow,
                    title: titleText,
                    titleColor: titleColor?.resolve(with: palette) ?? palette.accent,
                    focusIndicatorColor: focusIndicator?.current
                )
            )
        } else {
            lines.append(
                BorderRenderer.standardTopBorder(
                    style: borderStyle,
                    innerWidth: innerWidth,
                    color: borderNow,
                    focusIndicatorColor: focusIndicator?.current
                )
            )
        }

        // Body lines (no background color applied). One batch call so the
        // coloured vertical border is built once for the whole body, not
        // per line. When the body buffer is uniform-width, hand its known width
        // through so each line skips its own `strippedLength` re-measure — the
        // dominant cost down a deeply-nested bordered spine, where each level
        // otherwise re-measures the whole growing body.
        lines.append(
            contentsOf: BorderRenderer.standardContentLines(
                contents: bodyBuffer.lines,
                innerWidth: innerWidth,
                style: borderStyle,
                color: borderNow,
                contentWidth: bodyBuffer.linesAreUniformWidth ? bodyBuffer.width : nil
            )
        )

        // Footer section (if present)
        if let footerBuf = footerBuffer, !footerBuf.isEmpty {
            if style.showFooterSeparator {
                lines.append(
                    BorderRenderer.standardDivider(
                        style: borderStyle,
                        innerWidth: innerWidth,
                        color: borderNow
                    )
                )
            }

            // Footer lines (no background - footer has its own styling)
            lines.append(
                contentsOf: BorderRenderer.standardContentLines(
                    contents: footerBuf.lines,
                    innerWidth: innerWidth,
                    style: borderStyle,
                    color: borderNow
                )
            )
        }

        // Bottom border
        lines.append(
            BorderRenderer.standardBottomBorder(
                style: borderStyle,
                innerWidth: innerWidth,
                color: borderNow
            )
        )

        // The width is known without re-measuring every line: the top/bottom
        // borders, the divider, and `standardContentLines` all sit between two
        // border cells with content padded to `innerWidth`, so each line is
        // exactly `innerWidth + 2` cells — EXCEPT a titled top border, which can
        // overflow `innerWidth + 2` when the box is squeezed narrower than its
        // title. So only a present title needs the top line (`lines.first`)
        // measured; the common border (no title) needs no measurement at all.
        // This matters because `FrameBuffer(lines:)` → `computeWidth` re-measures
        // every line's Unicode/ANSI width, and on the deeply-nested `deep` stress
        // scenario that recompute was ~51% inclusive — each enclosing border
        // re-measured the whole growing buffer.
        let knownWidth = title == nil
            ? innerWidth + 2
            : max(innerWidth + 2, lines.first?.strippedLength ?? 0)
        // Every line a border emits — top/bottom border, divider, and each
        // `standardContentLines` line — is forced to exactly `innerWidth + 2`
        // visible cells, so the assembled buffer is uniform-width UNLESS a titled
        // top border overflowed (then `knownWidth` exceeds `innerWidth + 2`).
        // Flagging it lets an enclosing padding/border skip re-measuring this
        // whole buffer — bordering is thus a uniformity *producer*, which is what
        // collapses the O(depth²) re-measure down a nested spine to O(depth).
        var result = FrameBuffer(
            lines: lines, width: knownWidth, uniformWidth: knownWidth == innerWidth + 2)
        // Carry overlay layers and hit-test regions from the body and
        // footer. The body content sits one row below the top border
        // and one column inside the left border; the footer follows
        // the body and its optional separator.
        var carriedOverlays = bodyBuffer.shiftedOverlays(byX: 1, y: 1)
        // The shift moves the body's regions past the border; it does not grow
        // them, so the rule itself is outside every rect a reveal can see and a
        // focused control lands with its frame one row off-screen. Record the
        // rule against the regions it is flush with — only those, so a row in
        // the middle of a list is unaffected — and let `revealTarget` add it
        // back on the whole-control path.
        let hasFooter = !(footerBuffer?.isEmpty ?? true)
        /// Marks the rule against the regions it is flush with — only those, so
        /// a row in the middle of a list is unaffected.
        func outset(_ regions: [HitTestRegion], top: Int, bottom: Int?) -> [HitTestRegion] {
            regions.map { region in
                var region = region
                if region.offsetY == top { region.revealOutsetTop += 1 }
                if let bottom, region.offsetY + region.height == bottom {
                    region.revealOutsetBottom += 1
                }
                return region
            }
        }
        var carriedRegions = outset(
            bodyBuffer.shiftedHitTestRegions(byX: 1, y: 1), top: 1,
            // With a footer below it, the body's last row is not against the
            // bottom rule — the footer's is.
            bottom: hasFooter ? nil : 1 + bodyBuffer.lines.count)
        if let footerBuf = footerBuffer, !footerBuf.isEmpty {
            let footerRow = 1 + bodyBuffer.lines.count + (style.showFooterSeparator ? 1 : 0)
            carriedOverlays += footerBuf.shiftedOverlays(byX: 1, y: footerRow)
            carriedRegions += outset(
                footerBuf.shiftedHitTestRegions(byX: 1, y: footerRow), top: -1,
                bottom: footerRow + footerBuf.lines.count)
        }
        result.overlays = carriedOverlays
        result.hitTestRegions = carriedRegions
        result.animatedCells = animatedCells(
            bodyBuffer: bodyBuffer, footerBuffer: footerBuffer, innerWidth: innerWidth,
            borderStyle: borderStyle, borderColor: borderColor,
            focusIndicator: focusIndicator, lineCount: lines.count, palette: palette)
        result.opacityRegions = opacityRegions(
            bodyBuffer: bodyBuffer, footerBuffer: footerBuffer, outerWidth: knownWidth,
            borderStyle: borderStyle, borderColor: borderColor,
            focusIndicator: focusIndicator, lineCount: lines.count, palette: palette)
        return result
    }

    /// Every translucent cell of a bordered container: the ones its content
    /// declared, moved past the border, plus the border's own.
    ///
    /// - Parameter outerWidth: The assembled buffer's width, walls included — the
    ///   figure the frame's claim is a frame OF.
    private func opacityRegions(
        bodyBuffer: FrameBuffer,
        footerBuffer: FrameBuffer?,
        outerWidth: Int,
        borderStyle: BorderStyle,
        borderColor: AnimatedColor,
        focusIndicator: AnimatedColor?,
        lineCount: Int,
        palette: any Palette
    ) -> [OpacityRegion] {
        // Content sits one cell inside the wall — the same shift its overlays and
        // hit regions take.
        var regions = bodyBuffer.shiftedOpacityRegions(byX: 1, y: 1)
        if let footerBuf = footerBuffer, !footerBuf.isEmpty {
            regions += footerBuf.shiftedOpacityRegions(
                byX: 1, y: 1 + bodyBuffer.lines.count + (style.showFooterSeparator ? 1 : 0))
        }
        // The border's OWN cells, when any of the colours it drew with was faded.
        // Every frame goes through `BorderRenderer.band` at its opaque spelling, so
        // the alpha is only ever in this claim, and a replayed frame is blended under
        // it — so it is stated only when it is true of every frame: a still colour, or
        // an animating one whose frames share one alpha (§59). Frames at several alphas
        // state NOTHING here and state it per frame on the runs instead (§69.3), because
        // no one rectangle is true of them all. That is an XOR, and the resolver asserts
        // it: a claim here beside a payload there would fold twice and fade the border
        // at the product of the two. This used to skip every animating border and call
        // it loud; it stopped being loud at §18.3, when `band` began stating the opaque
        // spelling.
        guard !borderColor.isAnimating || borderColor.hasOneAlpha else { return regions }
        // The ● is claimed at its current frame, so it must be one alpha too. Its one
        // producer, `activeSection`, spends both of its ends.
        assert(focusIndicator?.hasOneAlpha != false, "a focus ●'s frames disagree about alpha (§59)")
        // Resolved only when there IS a title: `resolve(with:)` walks the palette
        // up to sixteen hops, and an untitled `.border()` never reads the answer.
        // Not attributable to a measured regression — the border work bisected clean
        // — but a bordered spine reaches here once per level per frame, so a walk
        // whose result is discarded is worth not doing.
        let titleNow: Color? =
            title == nil ? nil : (titleColor?.resolve(with: palette) ?? palette.accent)
        let claims = BorderRenderer.opacityClaims(
            outerWidth: outerWidth, height: lineCount, style: borderStyle,
            color: borderColor.current, title: title, titleColor: titleNow,
            focusIndicatorColor: focusIndicator?.current,
            dividerRow: dividerRow(bodyBuffer: bodyBuffer, footerBuffer: footerBuffer))
        // `regions + claims` allocates a third array whatever is in them, and an
        // opaque box — every box in nearly every app — has nothing to add.
        guard !claims.isEmpty else { return regions }
        return regions + claims
    }

    /// Every animated cell of a bordered container: the ones its content
    /// declared, moved past the border, plus the border's own.
    ///
    /// Dropping a carried run does not merely stop an animation, it FREEZES
    /// one: the run loop keeps the clock alive from the runs on the final
    /// buffer, so a run that never arrives takes the clock down with it.
    @MainActor
    private func animatedCells(
        bodyBuffer: FrameBuffer,
        footerBuffer: FrameBuffer?,
        innerWidth: Int,
        borderStyle: BorderStyle,
        borderColor: AnimatedColor,
        focusIndicator: AnimatedColor?,
        lineCount: Int,
        palette: any Palette
    ) -> [AnimatedCellRun] {
        var runs = bodyBuffer.shiftedAnimatedCells(byX: 1, y: 1)
        if let footerBuf = footerBuffer, !footerBuf.isEmpty {
            let footerRow = 1 + bodyBuffer.lines.count + (style.showFooterSeparator ? 1 : 0)
            runs += footerBuf.shiftedAnimatedCells(byX: 1, y: footerRow)
        }
        let showsIndicator =
            focusIndicator != nil
            && BorderRenderer.showsFocusIndicator(innerWidth: innerWidth, hasTitle: title != nil)
        if borderColor.isAnimating {
            // The border itself moves, so the whole frame it draws is replayed —
            // and the ● lives IN the top border's line. A separate run for it
            // would be a second claim on the same cell, spliced in whatever
            // order the loop happened to hold them: the two are folded into one
            // set of frames instead, in phase because they share the clock.
            runs += borderRuns(
                borderColor, indicator: showsIndicator ? focusIndicator : nil,
                borderStyle: borderStyle, innerWidth: innerWidth, lineCount: lineCount,
                dividerRow: dividerRow(bodyBuffer: bodyBuffer, footerBuffer: footerBuffer),
                palette: palette)
        } else if let indicatorRun = showsIndicator
            ? focusIndicator?.focusIndicatorRun(offsetX: 1, offsetY: 0) : nil
        {
            // The section's ● breathes on its own, at the one cell the top
            // border just drew it in — `BorderRenderer.showsFocusIndicator` is
            // the SAME condition the border drew under, so a box too narrow for
            // the ● leaves no run repainting a corner.
            runs.append(indicatorRun)
        }
        return runs
    }

    /// The row the footer separator sits on, or `nil` when there is none. Its
    /// end caps are `leftT`/`rightT` rather than the plain wall, so it is drawn
    /// (and replayed) as a whole line rather than as two side cells.
    private func dividerRow(bodyBuffer: FrameBuffer, footerBuffer: FrameBuffer?) -> Int? {
        guard style.showFooterSeparator, !(footerBuffer?.isEmpty ?? true) else { return nil }
        return 1 + bodyBuffer.lines.count
    }

    /// Every cell of a border whose colour moves, as runs.
    ///
    /// The horizontal rules — top, bottom and the footer separator — are whole
    /// lines, rebuilt per frame through the same `BorderRenderer` calls that
    /// drew them, so a title and a focus ● come along at the right colours.
    /// Everything between is two single cells per row, and every one of those
    /// rows draws the identical wall, so the frames are built once and shared
    /// (an array is copy-on-write, so sharing them costs nothing).
    ///
    /// - Parameter indicator: The focus ●, when the top border is drawing one.
    ///   It is folded into the top line's frames rather than left as its own
    ///   run, because two runs over one cell have no defined order.
    @MainActor
    private func borderRuns(
        _ borderColor: AnimatedColor,
        indicator: AnimatedColor?,
        borderStyle: BorderStyle,
        innerWidth: Int,
        lineCount: Int,
        dividerRow: Int?,
        palette: any Palette
    ) -> [AnimatedCellRun] {
        guard lineCount >= 2 else { return [] }
        let titleText = title
        let titleColour = titleColor?.resolve(with: palette) ?? palette.accent
        var runs: [AnimatedCellRun] = []

        // What each frame's cells owe, for the border whose frames DISAGREE about alpha
        // — the case `opacityRegions` declines to claim, because no one rectangle is
        // true of them all (§59.2). Stated per frame on the runs instead (§69).
        //
        // `nil` for every other border: one whose frames share an alpha is claimed
        // statically, and claiming it here as well would fold it twice. That XOR is the
        // one rule this pairing asks a reader to hold, and the two branches are four
        // lines apart so it can be checked by eye.
        //
        // Built once per STEP, not once per run: the same call `opacityRegions` makes,
        // at each frame's colours, so the claim cannot drift from the bytes — both come
        // from one colour per step. Each run then slices its own cells out of that.
        let perStepClaims: [[OpacityRegion]]? =
            borderColor.isAnimating && !borderColor.hasOneAlpha
            ? BorderRenderer.perFrameOpacityClaims(
                borderColor, indicator: indicator,
                outerWidth: innerWidth + BorderRenderer.borderWidthOverhead,
                height: lineCount, style: borderStyle, title: titleText,
                titleColor: titleColour, dividerRow: dividerRow)
            : nil

        /// The payload for a run of `width` cells at `(offsetX, row)`. Run-relative, so
        /// a shifted copy carries it unchanged.
        func payload(row: Int, offsetX: Int, width: Int) -> AnimatedRunAlpha? {
            guard let perStepClaims else { return nil }
            return AnimatedRunAlpha(
                slicing: perStepClaims, row: row, offsetX: offsetX, width: width,
                drawnIndex: borderColor.drawnIndex)
        }

        if let top = borderColor.run(offsetX: 0, offsetY: 0, drawAtStep: { step, colour in
            let dot = indicator?.color(atStep: step)
            guard let titleText else {
                return BorderRenderer.standardTopBorder(
                    style: borderStyle, innerWidth: innerWidth, color: colour,
                    focusIndicatorColor: dot)
            }
            return BorderRenderer.standardTopBorder(
                style: borderStyle, innerWidth: innerWidth, color: colour, title: titleText,
                titleColor: titleColour, focusIndicatorColor: dot)
        }) {
            var top = top
            top.alpha = payload(row: 0, offsetX: 0, width: top.width)
            runs.append(top)
        }

        if let bottom = borderColor.run(offsetX: 0, offsetY: lineCount - 1, draw: {
            BorderRenderer.standardBottomBorder(
                style: borderStyle, innerWidth: innerWidth, color: $0)
        }) {
            var bottom = bottom
            bottom.alpha = payload(row: lineCount - 1, offsetX: 0, width: bottom.width)
            runs.append(bottom)
        }

        if let dividerRow, dividerRow > 0, dividerRow < lineCount - 1,
            let divider = borderColor.run(offsetX: 0, offsetY: dividerRow, draw: {
                BorderRenderer.standardDivider(
                    style: borderStyle, innerWidth: innerWidth, color: $0)
            })
        {
            var divider = divider
            divider.alpha = payload(row: dividerRow, offsetX: 0, width: divider.width)
            runs.append(divider)
        }

        // The side walls. `innerWidth + 1` rather than the buffer's width: a
        // titled top border may be WIDER than the box below it, and the wall is
        // where `standardContentLines` put it.
        guard let wall = borderColor.run(offsetX: 0, offsetY: 0, draw: {
            BorderRenderer.wall(style: borderStyle, color: $0)
        }) else { return runs }
        // The payload is worked out ONCE per side and carried by every shifted copy —
        // spans are run-relative, so a shift is the identity for them, exactly as it
        // already is for the frames. A box of height H emits 2 × (H − 2) wall runs (44
        // for a 24-row section), and computing a payload inside that loop would be ~950
        // array allocations per box per render for an answer that is the same every
        // time. The rule is one payload per DISTINCT claim geometry — here three shapes,
        // not 2H − 1 rows.
        let interiorRow = (1..<(lineCount - 1)).first { $0 != dividerRow } ?? 1
        var leftWall = wall
        leftWall.alpha = payload(row: interiorRow, offsetX: 0, width: wall.width)
        var rightWall = wall
        rightWall.alpha = payload(row: interiorRow, offsetX: innerWidth + 1, width: wall.width)
        for row in 1..<(lineCount - 1) where row != dividerRow {
            runs.append(leftWall.shifted(byX: 0, y: row))
            runs.append(rightWall.shifted(byX: innerWidth + 1, y: row))
        }
        return runs
    }

    // MARK: - Borderless Rendering

    /// Renders without any border chrome: the title (if any), body, optional
    /// footer separator, and footer are emitted at full width with no top/bottom
    /// border rows and no side walls. Used by ``ContainerConfig/hasBorder`` ==
    /// `false` (e.g. `.listStyle(.plain)`), so a plain list reads as flush
    /// content with no box around it.
    ///
    /// Body and footer content already sit at column 0, so their overlays and
    /// hit-test regions shift only vertically (by the rows above them) — there is
    /// no left wall to step past.
    private func renderBorderless(
        bodyBuffer: FrameBuffer,
        footerBuffer: FrameBuffer?,
        innerWidth: Int,
        borderColor: Color,
        context: RenderContext
    ) -> FrameBuffer {
        let palette = context.environment.palette
        var lines: [String] = []

        // Pads a content line to the full inner width (no side walls).
        func padded(_ line: String) -> String {
            let used = line.strippedLength
            guard used < innerWidth else { return line }
            return line + asciiSpaces(innerWidth - used)
        }

        // Optional title line, rendered plainly (no border decoration) since
        // there is no top border to host it. Through `ClaimingRow`, like the
        // separator below, so a faded colour — the title's defaults to the accent,
        // which a faded tint fades — states its opaque spelling and claims its
        // alpha (§65).
        var titleRows = 0
        var chromeClaims: [OpacityRegion] = []
        if let titleText = title {
            var drawn = ClaimingRow()
            drawn.append(
                titleText, cells: titleText.strippedLength,
                ink: titleColor?.resolve(with: palette) ?? palette.accent)
            lines.append(padded(drawn.text))
            chromeClaims += drawn.claims
            titleRows = 1
        }

        // Body lines at full width.
        for line in bodyBuffer.lines { lines.append(padded(line)) }

        // Footer section (separator + footer lines), if present.
        var footerSeparatorRows = 0
        if let footerBuf = footerBuffer, !footerBuf.isEmpty {
            if style.showFooterSeparator {
                var rule = ClaimingRow()
                rule.append(
                    String(repeating: "─", count: max(0, innerWidth)), cells: max(0, innerWidth),
                    ink: borderColor)
                chromeClaims += rule.claims.map { $0.shifted(byX: 0, y: lines.count) }
                lines.append(rule.text)
                footerSeparatorRows = 1
            }
            for line in footerBuf.lines { lines.append(padded(line)) }
        }

        var result = FrameBuffer(lines: lines, width: innerWidth, uniformWidth: true)
        // Content sits at column 0 (no wall), shifted down by the title rows.
        var carriedOverlays = bodyBuffer.shiftedOverlays(byX: 0, y: titleRows)
        var carriedRuns = bodyBuffer.shiftedAnimatedCells(byX: 0, y: titleRows)
        var carriedRegions = bodyBuffer.shiftedHitTestRegions(byX: 0, y: titleRows)
        var carriedOpacity = bodyBuffer.shiftedOpacityRegions(byX: 0, y: titleRows)
        if let footerBuf = footerBuffer, !footerBuf.isEmpty {
            let footerRow = titleRows + bodyBuffer.lines.count + footerSeparatorRows
            carriedOverlays += footerBuf.shiftedOverlays(byX: 0, y: footerRow)
            carriedRegions += footerBuf.shiftedHitTestRegions(byX: 0, y: footerRow)
            carriedRuns += footerBuf.shiftedAnimatedCells(byX: 0, y: footerRow)
            carriedOpacity += footerBuf.shiftedOpacityRegions(byX: 0, y: footerRow)
        }
        result.overlays = carriedOverlays
        result.hitTestRegions = carriedRegions
        result.animatedCells = carriedRuns
        // The fourth payload. This rebuilds with a bare `FrameBuffer(lines:)`,
        // so anything not re-attached here is simply gone — and the title and the
        // separator, drawn here, add their own.
        result.opacityRegions = carriedOpacity + chromeClaims
        return result
    }
}

// MARK: - Equatable Conformance

extension _ContainerViewCore: @preconcurrency Equatable where Content: Equatable, Footer: Equatable {
    static func == (lhs: _ContainerViewCore<Content, Footer>, rhs: _ContainerViewCore<Content, Footer>) -> Bool {
        lhs.title == rhs.title && lhs.titleColor == rhs.titleColor && lhs.content == rhs.content && lhs.footer == rhs.footer
            && lhs.style == rhs.style && lhs.padding == rhs.padding
    }
}

// MARK: - A border colour that changed

extension _ContainerViewCore {
    /// The border's colour, faded when it changed inside
    /// ``withAnimation(_:_:)``.
    ///
    /// Only a *still* colour is put through the animator. One that already
    /// carries a cycle is a decoration — a focus pulse — and is on the run
    /// loop's replay path, which is both cheaper and not a change to animate
    /// between. Interpolating one cycle into another would be neither.
    @MainActor
    static func animating(_ colour: AnimatedColor?, context: RenderContext) -> AnimatedColor? {
        guard let colour, !colour.isAnimating else { return colour }
        return AnimatedColor(
            ColorAnimation.resolving(colour.current, owner: Self.self, context: context))
    }
}
