//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StatusBarItemsModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - StatusBarItemsModifier

/// A modifier that declares status bar items for a view.
///
/// Items are registered with the ``StatusBarState`` during rendering.
/// When used together with ``FocusSectionModifier``, the composition
/// strategy determines how items relate to parent items:
///
/// - **`.merge`** (default): Items are combined with parent items.
/// - **`.replace`**: Items replace all parent items (cascade barrier).
///
/// # Example
///
/// ```swift
/// struct MyView: View {
///     var body: some View {
///         VStack {
///             Text("Content")
///         }
///         .statusBarItems {
///             StatusBarItem(shortcut: "n", label: "new") { addItem() }
///             StatusBarItem(shortcut: Shortcut.escape, label: "back") { goBack() }
///         }
///     }
/// }
/// ```
struct StatusBarItemsModifier<Content: View>: View {
    /// The content view.
    let content: Content

    /// The status bar items to display.
    let items: [any StatusBarItemProtocol]

    /// The composition strategy for combining with parent items.
    let composition: StatusBarItemComposition

    /// Optional context identifier for legacy push/pop API.
    /// Nil for the new composition-based API.
    let context: String?

    var body: Never {
        fatalError("StatusBarItemsModifier renders via Renderable")
    }
}

// MARK: - Renderable

extension StatusBarItemsModifier: Renderable {
    func renderToBuffer(context renderContext: RenderContext) -> FrameBuffer {
        // No status bar (a headless render, a test): nothing to register
        // into, and the content still draws.
        guard let statusBar = renderContext.environment.statusBar else {
            return TUIkit.renderToBuffer(content, context: renderContext)
        }

        // Declare the registration to any value-memoizing ancestor, exactly as
        // the preference and `onKeyPress` modifiers do. The status bar's items
        // are rebuilt from scratch every render pass (`clearSectionItems()`),
        // so a subtree served from cache never re-registers and its items
        // silently vanish from the bar — a disappearance nothing in the
        // buffer reveals, since this modifier adds no hit region and reads no
        // volatile value, so every other gate lets it through.
        renderContext.environment.volatileReadTracker?.recordRenderSideEffect()

        // Set the items silently (without triggering re-render) to avoid render loops.
        // The modifier is called during rendering, so we must not trigger another render.
        if let contextName = self.context {
            // Legacy: push items to a named context
            statusBar.pushSilently(context: contextName, items: items)
        } else {
            // Register items with the focus section's composition strategy.
            // If inside a focus section, items are associated with that section.
            // Otherwise, they become global items.
            if let sectionID = renderContext.environment.activeFocusSectionID {
                statusBar.registerSectionItems(
                    sectionID: sectionID,
                    items: items,
                    composition: composition
                )
            } else {
                statusBar.setItemsSilently(items)
            }
        }

        return TUIkit.renderToBuffer(content, context: renderContext)
    }
}

// MARK: - Layoutable

extension StatusBarItemsModifier: Layoutable {
    /// Status-bar items render on a separate bar, not inline, so this measures as
    /// `content`. Forwarding also keeps the item-registration side-effect to the
    /// render pass — a measure must not mutate the status bar.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}
