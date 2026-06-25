//  🖥️ TUIKit — Terminal UI Kit for Swift
//  AlertPresentationModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A modifier that presents an alert dialog when a binding is true.
///
/// This modifier mirrors SwiftUI's `.alert(isPresented:)` API. When `isPresented`
/// is `true`, the base content is dimmed and the alert is shown centered on top.
/// When `false`, only the base content is rendered.
///
/// ## Example
///
/// ```swift
/// VStack {
///     Text("Main content")
/// }
/// .alert("Warning", isPresented: $showAlert) {
///     Button("Yes") { showAlert = false }
///     Button("No") { showAlert = false }
/// } message: {
///     Text("Are you sure?")
/// }
/// ```
public struct AlertPresentationModifier<Content: View, Actions: View, Message: View>: View {
    /// The base content to render.
    let content: Content

    /// Binding to control alert visibility.
    let isPresented: Binding<Bool>

    /// The alert title.
    let title: String

    /// The alert message content (optional).
    let message: Message?

    /// The alert action buttons.
    let actions: Actions

    /// Alert border style (optional).
    let borderStyle: BorderStyle?

    /// Alert border color (optional).
    let borderColor: Color?

    /// Alert title color (optional).
    let titleColor: Color?

    public var body: Never {
        fatalError("AlertPresentationModifier renders via Renderable")
    }
}

// MARK: - Renderable

extension AlertPresentationModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // A focus section unique to THIS alert instance, so stacked alerts /
        // modals each isolate (only the topmost active section is interactive).
        let sectionID = "alert-\(context.identity.path)"

        // If not presented, just return base content. Tear down the alert's
        // focus section if it's still active (the alert was just dismissed), so
        // the page's focus — and a ScrollView's scroll position — is restored
        // rather than jumping to the top.
        guard isPresented.wrappedValue else {
            if !context.isMeasuring {
                context.environment.focusManager?.deactivateSection(id: sectionID)
            }
            return TUIkit.renderToBuffer(content, context: context)
        }

        // Render message content to string if provided
        let messageString: String
        if let message {
            let messageBuffer = TUIkit.renderToBuffer(message, context: context)
            messageString = messageBuffer.lines.joined(separator: "\n").stripped
        } else {
            messageString = ""
        }

        // Build the alert view
        let alert = Alert(
            title: title,
            message: messageString,
            borderStyle: borderStyle,
            borderColor: borderColor,
            titleColor: titleColor,
            actions: { actions }
        )

        // Register the alert focus section and activate it FIRST, so the page
        // beneath registers its controls in the now-inactive page section (and
        // can't steal focus/scroll) while the alert's own controls auto-focus.
        if !context.isMeasuring {
            let focusManager = context.environment.focusManager
            focusManager?.registerSection(id: sectionID)
            focusManager?.activateSection(id: sectionID)
            // Mark this section input-grabbing so the app's global default key
            // bindings (appearance/theme) don't fire behind the alert.
            focusManager?.markSectionModal(id: sectionID)
        }

        // Register ESC handler to dismiss the alert (on the real dispatcher; the
        // page beneath renders with a throwaway one, so only the alert's ESC fires).
        let isPresentedBinding = isPresented
        context.environment.keyEventDispatcher!.addHandler { event in
            if event.key == .escape {
                isPresentedBinding.wrappedValue = false
                return true
            }
            return false
        }

        // Render the page beneath as an inert backdrop, isolated from the live
        // focus / key / state systems (`isolatedForBackground`). The alert section
        // is already active, so a background control rendered into the real focus
        // manager would resolve to that section and steal the focus the alert's
        // own actions should auto-receive — and stay live to hotkeys. Isolation
        // keeps the real manager seeing only the alert, silences page `onKeyPress`,
        // and (via throwaway state) preserves the page's scroll/@State. The root
        // compositor dims this buffer for the backdrop; mouse is isolated by that
        // dimmed backdrop dropping the page's hit-test regions.
        var baseBuffer = TUIkit.renderToBuffer(content, context: context.isolatedForBackground())

        // Render the alert against the FULL screen (not the attachment's local
        // area) so it isn't clipped, in the alert section.
        var alertContext = context
            .withAvailableWidth(context.environment.terminalWidth)
            .withAvailableHeight(context.environment.terminalHeight)
        alertContext.environment.activeFocusSectionID = sectionID
        let alertBuffer = TUIkit.renderToBuffer(alert, context: alertContext)

        guard !alertBuffer.isEmpty else { return baseBuffer }

        // Float the alert to the screen root: it composites centred over the whole
        // screen and dims everything beneath, from any attachment point.
        baseBuffer.overlays.append(
            OverlayLayer(
                offsetX: 0, offsetY: 0, content: alertBuffer,
                level: .alert, centered: true, dimsBackground: true))
        return baseBuffer
    }
}

// MARK: - Layoutable

extension AlertPresentationModifier: Layoutable {
    /// The alert is *presented over* the page (a centred overlay on the dimmed
    /// base, which spans the page), so the layout footprint is the base
    /// `content` — both when dismissed and when presented. Forwarding also keeps
    /// the focus-section / status-bar side-effects on the render pass; a measure
    /// must not register or activate sections.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}
