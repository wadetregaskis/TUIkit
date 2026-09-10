//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AppHeader.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - App Header View

/// A header bar rendered at the top of the terminal, outside the view tree.
///
/// `AppHeader` is an internal view used by `RenderLoop` to render the
/// app header content. It renders the content buffer from `AppHeaderState`
/// and appends a thin divider line below.
///
/// ## Layout
///
/// ```
/// ┌──────────────────────────────────────────────────────────────────┐
/// │ My App Title                                       TUIkit v0.1.0 │
/// │──────────────────────────────────────────────────────────────────│
/// ```
struct AppHeader: View {
    /// The pre-rendered content buffer from the modifier.
    let contentBuffer: FrameBuffer

    /// How the header frames itself against the page below it.
    let style: ChromeStyle

    var body: Never {
        fatalError("AppHeader renders via Renderable")
    }
}

// MARK: - Renderable

extension AppHeader: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let width = context.availableWidth
        let palette = context.environment.palette
        var lines: [String] = []
        /// The row a `.rule` style's rule landed on, for its opacity claim.
        var ruleRow: Int?

        // The box's walls eat two columns, so its content is laid out narrower;
        // the other two styles get the full width. Same figure the modifier
        // proposed to the content, from the same place.
        let contentWidth = max(0, width - style.contentWidthInset)
        for line in contentBuffer.lines {
            lines.append(line.padToVisibleWidth(contentWidth))
        }

        switch style {
        case .rule:
            // A thin rule below the content, drawn from the same place the
            // status bar draws its own — that shared source is what keeps the
            // two ends of the frame looking like a pair, and it follows the
            // current appearance so a custom border restyles both at once.
            lines.append(ChromeStyle.ruleRow(width: width, context: context))
            // The rule is the last line, so its row is what the content already
            // occupies — claimed after `replacingLines` below, where the content's
            // own claims are already in these coordinates.
            ruleRow = lines.count - 1
        case .bordered:
            let border = context.environment.appearance.borderStyle
            let innerWidth = max(0, width - BorderRenderer.borderWidthOverhead)
            lines = lines.map {
                BorderRenderer.standardContentLine(
                    content: $0, innerWidth: innerWidth, style: border, color: palette.border)
            }
            lines.insert(
                BorderRenderer.standardTopBorder(
                    style: border, innerWidth: innerWidth, color: palette.border),
                at: 0)
            lines.append(
                BorderRenderer.standardBottomBorder(
                    style: border, innerWidth: innerWidth, color: palette.border))
        case .compact:
            break  // content alone; the background colour is the only boundary
        }

        // `FrameBuffer(lines:)` builds a fresh buffer, so every side payload the
        // header content emitted has to be carried over ONE BY ONE — and each
        // one that was not is a feature that silently does nothing inside
        // `.appHeader { … }`. That is the bare-`FrameBuffer(lines:)` tell: hit
        // regions went first (`e5382a77`, a Button in the header that could not
        // be clicked), opacity followed, and the two below were still missing.
        //
        // `replacingLines` does all four at once, with the shift a box needs —
        // right by its wall, down by its top rule — applied to each. Written as
        // four assignments it was four chances to forget one, which is what
        // happened twice.
        var framed = contentBuffer.replacingLines(
            lines,
            // Animated runs: a `Spinner` or any `.animatedCells` in the header
            // was frozen at frame 0, because a dropped run does not look like a
            // dropped animation — it looks like a still one.
            //
            // Overlays: a `Menu`, `.popover` or `.alert` declared in the header
            // OPENED (its state flipped, its hit region was live) and then drew
            // nothing at all, because the layer carrying its picture was thrown
            // away before anything could composite it.
            overlayShiftX: style == .bordered ? 1 : 0,
            overlayShiftY: style == .bordered ? 1 : 0)
        // The chrome's own cells, when the theme's `border` is faded. Appended
        // AFTER `replacingLines` has shifted the content's own claims inward, so
        // the two sets are in the same coordinates.
        if style == .bordered {
            framed.opacityRegions += BorderRenderer.opacityClaims(
                outerWidth: width, height: lines.count,
                style: context.environment.appearance.borderStyle, color: palette.border)
        }
        if let ruleRow,
            let claim = ChromeStyle.ruleClaim(width: width, offsetY: ruleRow, context: context)
        {
            framed.opacityRegions.append(claim)
        }
        return framed
    }
}
