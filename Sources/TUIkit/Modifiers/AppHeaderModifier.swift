//  🖥️ TUIkit — Terminal UI Kit for Swift
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
        // Through the backdrop isolation: a header is CHROME the app draws
        // around every screen, and chrome is not a Tab stop. Left on the real
        // focus manager, a `Button` in the header joined the page's focus ring
        // — so Tab walked out of the content and into the title bar, and the
        // header's `onKeyPress` and `.keyboardShortcut` registrations were live
        // alongside the page's. Its buffer still publishes hit-test regions, so
        // it stays clickable, which is the whole point of putting a control
        // there.
        //
        // At the width the header is actually DRAWN at, less what the style
        // spends on itself: a bordered header takes two columns for its walls,
        // and content laid out at the full width simply lost its last two cells
        // to the right wall ("TUIkit v0.6" for "TUIkit v0.6.0"). The style is
        // known here because it lives on the same state object this writes into.
        //
        // From the width the header will be DRAWN at, NOT this context's. This
        // modifier is applied inside the view tree, where any padding on the way
        // down has already narrowed `availableWidth`, while the header is drawn
        // across the whole terminal. Laying out at the narrower figure and
        // padding to the wider one is a trailing gap the size of that padding —
        // an app with a one-column gutter got two columns of air on the right of
        // its header and one on the left. See ``AppHeaderState/renderWidth``.
        var headerContext = context.isolatedForBackground()
        headerContext.availableWidth = max(
            0,
            (appHeader.renderWidth ?? context.availableWidth)
                - appHeader.style.contentWidthInset)
        // Declared for the same reason `.mouseSupport` and `.statusBarItems`
        // declare theirs: `contentBuffer` is cleared every render pass and a
        // memoized ancestor would leave it nil, which draws no header at all.
        // No realistic tree puts `.appHeader` under a memo — it is applied at
        // the root, above every row — but the omission is the same one.
        context.environment.volatileReadTracker?.recordRenderSideEffect()
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
