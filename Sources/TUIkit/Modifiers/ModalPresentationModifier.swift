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
            }
            return TUIkit.renderToBuffer(content, context: context)
        }

        let focusManager = context.environment.focusManager

        // Render dimmed base with an isolated context.
        // The base content's buttons and key handlers register into a
        // throwaway FocusManager and KeyEventDispatcher so they don't
        // interfere with the modal's interactive elements.
        let dimmedBase = DimmedModifier(content: content)
        let isolatedContext = context.isolatedForBackground()
        let dimmedBuffer = TUIkit.renderToBuffer(dimmedBase, context: isolatedContext)

        // Register the modal focus section and activate it. The modal section
        // becomes the active section, so Tab/arrows only navigate within the
        // modal's focusable elements.
        if !context.isMeasuring {
            focusManager?.registerSection(id: sectionID)
            focusManager?.activateSection(id: sectionID)

            // While the modal is on screen ESC should close it. Publish an
            // ESC=dismiss item on the status bar tied to the modal section
            // (composition: merge so non-ESC items the page declared still
            // show), and have it flip the presentation binding back to
            // false. The section items are cleared at the start of every
            // render pass, so closing the modal naturally drops the
            // override and restores the page's own ESC item.
            let isPresented = self.isPresented
            let dismissItem = StatusBarItem(
                shortcut: Shortcut.escape,
                label: "dismiss"
            ) {
                isPresented.wrappedValue = false
            }
            context.environment.statusBar.registerSectionItems(
                sectionID: sectionID,
                items: [dismissItem],
                composition: .merge
            )
        }

        // Set the modal section in the context so child focusables
        // (buttons in the modal) register in the modal section.
        var modalContext = context
        modalContext.environment.activeFocusSectionID = sectionID

        let modalBuffer = TUIkit.renderToBuffer(modal, context: modalContext)

        guard !dimmedBuffer.isEmpty else {
            return modalBuffer
        }

        guard !modalBuffer.isEmpty else {
            return dimmedBuffer
        }

        // Center relative to the full terminal area, not the content size.
        let screenWidth = context.availableWidth
        let screenHeight = context.availableHeight
        let modalWidth = modalBuffer.width
        let modalHeight = modalBuffer.height

        let horizontalOffset = max(0, (screenWidth - modalWidth) / 2)
        let verticalOffset = max(0, (screenHeight - modalHeight) / 2 - 2)

        return dimmedBuffer.composited(
            with: modalBuffer,
            at: (x: horizontalOffset, y: verticalOffset)
        )
    }
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
