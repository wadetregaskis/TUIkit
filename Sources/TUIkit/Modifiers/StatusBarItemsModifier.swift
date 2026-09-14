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
        guard renderContext.environment.statusBar != nil else {
            return TUIkit.renderToBuffer(content, context: renderContext)
        }

        // Declared to any value-memoizing ancestor. The status bar's items are
        // rebuilt from scratch every render pass (`beginRenderPass()`), so a
        // subtree served from the cache that did not register again would lose
        // its items from the bar, a disappearance nothing in the buffer reveals.
        // Declared as REPLAYABLE, as `onKeyPress` is: the buffer memo stores the
        // entry recorded below and registers the items again on every hit, at
        // this position in the walk, so a section's last registration still
        // replaces the ones before it.
        renderContext.environment.volatileReadTracker?.recordReplayableEffect()

        let sectionID = renderContext.environment.activeFocusSectionID
        StatusBarItemsRegistrar.register(
            items: items, composition: composition, contextName: context,
            sectionID: sectionID, context: renderContext)
        if let journal = renderContext.recordingEffectJournal {
            // Built only while a memo records. The section is captured, as
            // `onKeyPress` captures it: the memo checks that the section where
            // it is served is the one the items were registered in.
            journal.append(
                EffectJournal.Entry(
                    kind: StatusBarItemsRegistrar.kind,
                    channelToken: renderContext.environment.keyChannelToken
                ) { [items, composition, context] replay in
                    StatusBarItemsRegistrar.register(
                        items: items, composition: composition, contextName: context,
                        sectionID: sectionID, context: replay)
                })
        }

        return TUIkit.renderToBuffer(content, context: renderContext)
    }
}

// MARK: - Registration

/// The one registration `.statusBarItems` makes, shared by the live render and
/// by a value memo replaying it — see `EffectJournal`.
enum StatusBarItemsRegistrar {
    /// The journal kind of a `.statusBarItems` registration.
    static let kind = EffectJournal.Kind("statusBarItems")

    /// Registers `items` with `context`'s status bar, silently, because it runs
    /// during a render and must not ask for another:
    /// - pushed to `contextName`, for the legacy push/pop API;
    /// - otherwise filed under `sectionID` with `composition`, inside a focus
    ///   section;
    /// - otherwise as the global items.
    ///
    /// It looks the status bar up in `context` rather than taking one, so a
    /// replay registers into the bar of the frame that serves it.
    @MainActor
    static func register(
        items: [any StatusBarItemProtocol], composition: StatusBarItemComposition,
        contextName: String?, sectionID: String?, context: RenderContext
    ) {
        guard let statusBar = context.environment.statusBar else { return }
        if let contextName {
            statusBar.pushSilently(context: contextName, items: items)
        } else if let sectionID {
            statusBar.registerSectionItems(sectionID: sectionID, items: items, composition: composition)
        } else {
            statusBar.setItemsSilently(items)
        }
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
