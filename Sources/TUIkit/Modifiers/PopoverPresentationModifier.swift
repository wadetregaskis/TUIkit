//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PopoverPresentationModifier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - PopoverAttachmentAnchor

/// Where a popover attaches to the view presenting it. Matches SwiftUI's type
/// of the same name for the two spellings that mean something in a terminal.
///
/// > Note: SwiftUI's `.rect(_:)` takes an `Anchor<CGRect>.Source`, which is
///   bitmap geometry TUIkit does not model (see `SwiftUI-compatibility.md` §4b).
///   ``PopoverAttachmentRect/bounds`` — the only source that has a cell-grid
///   meaning, and SwiftUI's own default — is spelled the same way, so
///   `.rect(.bounds)` compiles unchanged.
public enum PopoverAttachmentAnchor: Sendable, Equatable {
    /// Attach to the presenting view's frame, centring the popover on it.
    case rect(PopoverAttachmentRect)

    /// Attach at a point within the presenting view's frame.
    case point(UnitPoint)
}

/// The rectangle a popover attaches to.
public enum PopoverAttachmentRect: Sendable, Equatable {
    /// The presenting view's own frame.
    case bounds
}

// MARK: - popover(…)

extension View {
    /// Presents a popover anchored to this view. Matches SwiftUI's
    /// `popover(isPresented:attachmentAnchor:arrowEdge:content:)`.
    ///
    /// Unlike ``sheet(isPresented:onDismiss:content:)``, which centres a panel
    /// over a dimmed screen, a popover stays *next to the thing it belongs to* —
    /// a bordered panel below (or above, or beside) the presenting view, over an
    /// undimmed page. It is the same presentation `.contextMenu` and the
    /// `Picker` drop-down use, with your content instead of menu rows.
    ///
    /// Escape closes it, and so does a click anywhere outside it.
    ///
    /// ```swift
    /// Button("Details") { showing = true }
    ///     .popover(isPresented: $showing) {
    ///         VStack(alignment: .leading) {
    ///             Text("Ganymede").bold()
    ///             Text("Largest moon in the solar system")
    ///         }
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - isPresented: A binding controlling presentation.
    ///   - attachmentAnchor: Where on this view the popover attaches.
    ///   - arrowEdge: Which side of this view the popover sits on. A terminal
    ///     draws no arrow, but the edge still decides the side; `nil` (the
    ///     default) means below.
    ///   - content: A ViewBuilder returning the popover's content.
    public func popover<Content: View>(
        isPresented: Binding<Bool>,
        attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
        arrowEdge: Edge? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        PopoverPresentationModifier(
            content: self,
            isPresented: isPresented,
            popover: content(),
            attachmentAnchor: attachmentAnchor,
            arrowEdge: arrowEdge ?? .bottom)
    }

    /// Presents a popover for a currently-selected item. Matches SwiftUI's
    /// `popover(item:attachmentAnchor:arrowEdge:content:)`.
    ///
    /// - Parameters:
    ///   - item: A binding to an optional, identifiable item; non-`nil` presents.
    ///   - attachmentAnchor: Where on this view the popover attaches.
    ///   - arrowEdge: Which side of this view the popover sits on.
    ///   - content: A ViewBuilder building the popover from the unwrapped item.
    public func popover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
        arrowEdge: Edge? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        let isPresented = Binding<Bool>(
            get: { item.wrappedValue != nil },
            set: { presented in if !presented { item.wrappedValue = nil } }
        )
        return popover(
            isPresented: isPresented, attachmentAnchor: attachmentAnchor, arrowEdge: arrowEdge
        ) {
            if let value = item.wrappedValue {
                content(value)
            }
        }
    }
}

// MARK: - Modifier

/// Presents `popover` as a bordered panel anchored to `content`.
struct PopoverPresentationModifier<Content: View, Popover: View>: View {
    let content: Content
    let isPresented: Binding<Bool>
    let popover: Popover
    let attachmentAnchor: PopoverAttachmentAnchor
    let arrowEdge: Edge

    var body: Never {
        fatalError("PopoverPresentationModifier renders via Renderable")
    }
}

extension PopoverPresentationModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Distinct per instance, like every other presented surface's section
        // (`modal-`, `alert-`, `contextmenu-`), so two popovers in one frame
        // cannot share a section and steal each other's focus.
        let sectionID = "popover-\(context.identity.path)"
        let contentContext = context.withChildIdentity(type: Content.self, index: 0)

        guard isPresented.wrappedValue else {
            if !context.isMeasuring {
                context.environment.volatileReadTracker?.recordRenderSideEffect()
                context.environment.focusManager?.deactivateSection(id: sectionID)
            }
            return TUIkit.renderToBuffer(content, context: contentContext)
        }

        var baseBuffer = TUIkit.renderToBuffer(content, context: contentContext)
        guard !context.isMeasuring, context.environment.mouseEventDispatcher != nil else {
            return baseBuffer
        }

        // Presentation is a per-frame render side effect: a memoized replay
        // would skip the section registration and leave a popover that no
        // longer holds the keyboard.
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        let isPresented = self.isPresented
        // Content that forbade interactive dismissal keeps Escape and the
        // outside click from closing it — the presenter's two gestures, and
        // SwiftUI's swipe-down in terminal form. A `Done` button inside, or
        // `@Environment(\.dismiss)`, still works; that is the point.
        let dismissIsDisabled =
            presentationTrait(InteractiveDismissDisabling.self, of: popover)?
            .interactiveDismissIsDisabled ?? false
        let dismiss = {
            guard !dismissIsDisabled else { return }
            isPresented.wrappedValue = false
        }

        let focusManager = context.environment.focusManager
        focusManager?.registerSection(id: sectionID)
        focusManager?.activateSection(id: sectionID)
        // Input-grabbing, so the app's chrome hotkeys don't fire behind it.
        focusManager?.markSectionModal(id: sectionID)
        // A popover holds arbitrary content, which may be entirely
        // non-focusable (a paragraph of text). Without this the end of the
        // render pass would hand the focus to whatever it could find — outside
        // the popover.
        focusManager?.markSectionFocusOptional(id: sectionID)
        context.environment.keyEventDispatcher!.grabInput(sectionID: sectionID)
        if !dismissIsDisabled {
            context.environment.statusBar?.escapeLabelOverride = "close popover"
            context.environment.keyEventDispatcher!.addHandler(sectionID: sectionID) { event in
                guard event.key == .escape else { return false }
                dismiss()
                return true
            }
        }

        var popoverContext = context
            .withChildIdentity(type: Popover.self, index: 1)
            .withAvailableWidth(context.environment.terminalWidth)
            .withAvailableHeight(context.environment.overlayContentHeight)
        popoverContext.environment.activeFocusSectionID = sectionID
        // `@Environment(\.dismiss)` inside the popover closes the POPOVER — the
        // same act as its Escape handler above. Left unset it would mean the
        // top-level dismissal, which is to quit the application.
        popoverContext.environment.isPresented = true
        popoverContext.environment.dismiss = DismissAction {
            isPresented.wrappedValue = false
        }

        var panel = renderPresentedDialog(
            panelView(context: context), context: popoverContext,
            capHeight: context.environment.overlayContentHeight)
        guard !panel.isEmpty else { return baseBuffer }

        // The same screen-covering backdrop every menu presentation uses: a
        // click outside closes it, and the wheel still reaches the page. With
        // dismissal disabled the backdrop is still attached and `dismiss` is
        // the no-op above — so the click is SWALLOWED rather than passed
        // through. Letting it reach the page would be the opposite of what was
        // asked: the popover stays up and something behind it acts on a click
        // aimed at closing it.
        DropdownMenu.attachDismissBackdrop(to: &panel, context: context, onDismiss: dismiss)

        let placement = placement(
            panel: (width: panel.width, height: panel.height),
            over: (width: baseBuffer.width, height: baseBuffer.height))
        baseBuffer.overlays.append(
            OverlayLayer(
                offsetX: placement.x, offsetY: placement.y, content: panel,
                level: .popover, anchorHeight: placement.anchorHeight))
        return baseBuffer
    }

    /// The popover's content in its panel: a border and a cell of breathing
    /// room, over the app background so the page cannot show through the gaps
    /// between what the content draws — the same opaque fill the drop-down
    /// menus rely on.
    private func panelView(context: RenderContext) -> some View {
        popover
            .padding(EdgeInsets(horizontal: 1, vertical: 0))
            .background(context.environment.palette.background)
            .border(context.environment.palette.border)
    }

    /// Where the panel goes in the presenting view's own coordinate space.
    ///
    /// `anchorHeight` is what the compositor flips around when there is no room
    /// below, and what an enclosing `ScrollView` culls against — understating it
    /// lands the popover on the control that opened it, or throws it away
    /// entirely. See ``OverlayLayer/anchorHeight``.
    private func placement(
        panel: (width: Int, height: Int), over base: (width: Int, height: Int)
    ) -> (x: Int, y: Int, anchorHeight: Int) {
        // The unit point resolves against the presenting view once, floored
        // once: the layout-parity rule, since a fraction of an extent is the one
        // place a fractional value belongs.
        let point: (x: Int, y: Int)
        switch attachmentAnchor {
        case .rect(.bounds):
            // Centre on the view, as a keyboard-opened menu does — the popover
            // reads as belonging to it rather than as something that landed in
            // the corner.
            point = (max(0, (base.width - panel.width) / 2), 0)
        case .point(let unit):
            point = (
                Int((unit.x * Double(base.width)).rounded(.down)),
                Int((unit.y * Double(base.height)).rounded(.down))
            )
        }

        switch arrowEdge {
        case .bottom:
            return (point.x, base.height, base.height)
        case .top:
            return (point.x, -panel.height, 0)
        case .leading:
            return (-panel.width, point.y, 0)
        case .trailing:
            return (base.width, point.y, 0)
        }
    }
}

extension PopoverPresentationModifier: Layoutable {
    /// The popover floats over the page, so the layout footprint is the
    /// presenting content — presented or not. Forwarding also keeps the
    /// section registration on the render pass.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(
            content, proposal: proposal,
            context: context.withChildIdentity(type: Content.self, index: 0))
    }
}
