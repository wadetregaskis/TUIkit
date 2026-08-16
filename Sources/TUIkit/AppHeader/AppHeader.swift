//  🖥️ TUIKit — Terminal UI Kit for Swift
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

        // The box's walls eat two columns, so its content is laid out narrower;
        // the other two styles get the full width.
        let contentWidth = style == .bordered ? max(0, width - 2) : width
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

        // Preserve any hit-test regions the header content
        // emitted (e.g. a Button inside `.appHeader { ... }`).
        // Without this, `FrameBuffer(lines:)` builds a fresh
        // buffer with empty hitTestRegions and the regions
        // disappear before they can be merged into the
        // dispatcher's set in RenderLoop. Same class of bug
        // as the status-bar one fixed in commit e5382a77.
        var result = FrameBuffer(lines: lines)
        // A box shifts the content right by its wall and down by its top rule;
        // the other styles leave it where it was.
        result.hitTestRegions =
            style == .bordered
            ? contentBuffer.shiftedHitTestRegions(byX: 1, y: 1)
            : contentBuffer.hitTestRegions
        return result
    }
}
