//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ModalPresentationModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A modifier that presents content as a centered modal overlay when a binding is true.
///
/// This is a generic presentation modifier that dims the base content and shows
/// the provided content centered on top. Unlike `AlertPresentationModifier`, this
/// accepts any view content.
///
/// ## Example
///
/// ```swift
/// VStack {
///     Text("Main content")
/// }
/// .modal(isPresented: $showModal) {
///     Dialog(title: "Settings") {
///         Text("Setting 1")
///         Text("Setting 2")
///     }
/// }
/// ```
public struct ModalPresentationModifier<Content: View, Modal: View>: View {
    /// The base content to render.
    let content: Content

    /// Binding to control modal visibility.
    let isPresented: Binding<Bool>

    /// The modal content to present.
    let modal: Modal

    public var body: Never {
        fatalError("ModalPresentationModifier renders via Renderable")
    }
}

// MARK: - Renderable

extension ModalPresentationModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // A focus section unique to THIS modal instance (its position in the
        // tree), so stacked modals each get a distinct section. Only the topmost
        // (most recently activated) section is interactive, and focus can't leak
        // between modals or to the background. A fixed shared id would make two
        // modals register into one section and break that isolation.
        let sectionID = "modal-\(context.identity.path)"

        // If not presented, just return base content.
        guard isPresented.wrappedValue else {
            // Tear down the modal focus section if it's still active (the modal
            // was just dismissed). This reverts focus to the page's section AND
            // restores its remembered focus, so the page doesn't jump to its
            // first element — which a ScrollView would then snap-scroll to,
            // resetting the scroll position.
            if !context.isMeasuring {
                context.environment.focusManager?.deactivateSection(id: sectionID)
                // Recentre next time it opens.
                DialogDrag.reset(context: context, propertyIndex: StateIndex.dragHandler)
            }
            return TUIkit.renderToBuffer(content, context: context)
        }

        // Register the modal focus section and activate it FIRST — so the page
        // rendered beneath registers its controls in the now-inactive page
        // section (and can't steal focus or auto-scroll), while the modal's own
        // controls auto-focus. The active section means Tab/arrows navigate only
        // within the modal. (Skipped while measuring — a measure mustn't mutate
        // focus or the status bar.)
        if !context.isMeasuring {
            let focusManager = context.environment.focusManager
            focusManager?.registerSection(id: sectionID)
            focusManager?.activateSection(id: sectionID)
            // Mark this section input-grabbing so the app's global default key
            // bindings (appearance/theme) don't fire behind the modal.
            focusManager?.markSectionModal(id: sectionID)

            // While the modal is on screen ESC should close it. Publish an
            // ESC=dismiss item on the status bar tied to the modal section
            // (composition: merge so non-ESC items the page declared still
            // show), flipping the presentation binding back to false. Section
            // items are cleared each render pass, so closing the modal naturally
            // drops the override and restores the page's own ESC item.
            let isPresented = self.isPresented
            let dismissItem = StatusBarItem(shortcut: Shortcut.escape, label: "dismiss") {
                isPresented.wrappedValue = false
            }
            context.environment.statusBar.registerSectionItems(
                sectionID: sectionID, items: [dismissItem], composition: .merge)
        }

        // Render the page beneath as an inert backdrop, isolated from the live
        // focus / key / state systems (`isolatedForBackground`). The modal section
        // is already active, so a background control rendered into the real focus
        // manager would resolve to that section and steal the focus the modal's
        // own controls should auto-receive — and stay live to hotkeys. Isolation
        // keeps the real manager seeing only the modal, silences page `onKeyPress`,
        // and (via throwaway state) preserves the page's scroll/@State. The root
        // compositor dims this buffer for the backdrop; mouse is isolated by that
        // dimmed backdrop dropping the page's hit-test regions.
        var baseBuffer = TUIkit.renderToBuffer(content, context: context.isolatedForBackground())

        // Render the modal content against the FULL screen (not the attachment's
        // local area, which may be a tiny leaf) so it isn't clipped, in the modal
        // section so its focusables register there. The root compositor then
        // centres and clamps it.
        var modalContext = context
            .withAvailableWidth(context.environment.terminalWidth)
            .withAvailableHeight(context.environment.terminalHeight)
        modalContext.environment.activeFocusSectionID = sectionID
        var modalBuffer = TUIkit.renderToBuffer(modal, context: modalContext)

        guard !modalBuffer.isEmpty else { return baseBuffer }

        // Make the dialog draggable by its title/border, and read back the offset
        // to place it at. The compositor clamps it fully on screen.
        let dragOffset = DialogDrag.offset(
            for: &modalBuffer, context: context, propertyIndex: StateIndex.dragHandler)

        // Float the modal to the screen root: it composites centred over the whole
        // screen and dims everything beneath — so it presents over the full screen
        // no matter where in the view tree `.modal` was attached (rather than
        // centring on the attachment's local area).
        baseBuffer.overlays.append(
            OverlayLayer(
                offsetX: dragOffset.x, offsetY: dragOffset.y, content: modalBuffer,
                level: .modal, centered: true, dimsBackground: true))
        return baseBuffer
    }
}

/// StateStorage property indices for ``ModalPresentationModifier``. A free enum
/// because the modifier is generic (which can't hold static stored properties).
private enum StateIndex {
    static let dragHandler = 0
}

// MARK: - Layoutable

extension ModalPresentationModifier: Layoutable {
    /// The modal is *presented over* the page (a centred overlay on the dimmed
    /// base, which spans the page), so the layout footprint is the base
    /// `content` — both when dismissed and when presented. Forwarding also keeps
    /// the focus-section / status-bar side-effects on the render pass; a measure
    /// must not register or activate sections.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}
