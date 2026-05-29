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

        // Content lines padded to full width
        for line in contentBuffer.lines {
            lines.append(line.padToVisibleWidth(width))
        }

        // Thin divider line
        let divider = String(repeating: "─", count: width)
        let styledDivider = ANSIRenderer.colorize(divider, foreground: palette.border)
        lines.append(styledDivider)

        // Preserve any hit-test regions the header content
        // emitted (e.g. a Button inside `.appHeader { ... }`).
        // Without this, `FrameBuffer(lines:)` builds a fresh
        // buffer with empty hitTestRegions and the regions
        // disappear before they can be merged into the
        // dispatcher's set in RenderLoop. Same class of bug
        // as the status-bar one fixed in commit e5382a77.
        var result = FrameBuffer(lines: lines)
        result.hitTestRegions = contentBuffer.hitTestRegions
        return result
    }
}
