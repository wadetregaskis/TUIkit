//  🖥️ TUIKit — Terminal UI Kit for Swift
//  AppHeaderModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - AppHeaderModifier

/// A modifier that declares the app header content for a view.
///
/// The header content is rendered to a ``FrameBuffer`` and stored in
/// `AppHeaderState` during the render pass. The `RenderLoop` then
/// renders it at the top of the terminal, outside the view tree.
///
/// If multiple views set `.appHeader { ... }`, the last one rendered wins.
///
/// # Example
///
/// ```swift
/// VStack {
///     Text("Page content")
/// }
/// .appHeader {
///     HStack {
///         Text("My App").bold().foregroundStyle(.palette.accent)
///         Spacer()
///         Text("v1.0").foregroundStyle(.palette.foregroundTertiary)
///     }
/// }
/// ```
struct AppHeaderModifier<Content: View, Header: View>: View {
    /// The content view.
    let content: Content

    /// The header content builder.
    let header: Header

    var body: Never {
        fatalError("AppHeaderModifier renders via Renderable")
    }
}

// MARK: - Renderable

extension AppHeaderModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Without an app there is no header to hand the buffer to, and
        // rendering it would be work nothing reads.
        guard let appHeader = context.environment.appHeader else {
            return TUIkit.renderToBuffer(content, context: context)
        }

        // Render the header content to a buffer and store it in state.
        // The RenderLoop will pick it up and render it separately.
        //
        // At the width the STYLE leaves it, not the terminal's: a bordered
        // header spends two columns on its walls, and content laid out at the
        // full width simply lost its last two cells to the right wall
        // ("TUIkit v0.6" for "TUIkit v0.6.0"). The style is known here because
        // it lives on the same state object this writes into.
        var headerContext = context
        headerContext.availableWidth = max(
            0, context.availableWidth - appHeader.style.contentWidthInset)
        let headerBuffer = TUIkit.renderToBuffer(header, context: headerContext)
        appHeader.contentBuffer = headerBuffer

        return TUIkit.renderToBuffer(content, context: context)
    }
}

// MARK: - Layoutable

extension AppHeaderModifier: Layoutable {
    /// The header renders separately (the RenderLoop draws it from
    /// `appHeader.contentBuffer`); this view returns `content` inline, so it
    /// measures as `content`. Forwarding also keeps the header-buffer write to
    /// the render pass.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}
