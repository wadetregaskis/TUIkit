//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusSectionModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A modifier that declares a focus section for a view subtree.
///
/// Focus sections are named, focusable areas of the UI. They group interactive
/// children (buttons, menus, etc.) into a navigable unit. Tab/Shift+Tab cycles
/// between sections, while Up/Down arrows navigate within the active section.
///
/// During rendering, this modifier registers the section with the
/// `FocusManager` and sets the active section ID in the `RenderContext`
/// so that child views register their focusable elements in the correct section.
///
/// ## Example
///
/// ```swift
/// HStack {
///     PlaylistView()
///         .focusSection("playlist")
///
///     TrackListView()
///         .focusSection("tracklist")
/// }
/// ```
struct FocusSectionModifier<Content: View>: View {
    /// The content view rendered within this section.
    let content: Content

    /// The caller's identifier for this focus section, or `nil` to derive one.
    ///
    /// SwiftUI's `focusSection()` takes no identifier — a section there is just
    /// "these focusables form a cohort". TUIkit needs a name for one, because a
    /// section is also what the status bar scopes its items to and what
    /// ``FocusManager`` cycles between. Deriving it from the view's identity
    /// path, exactly as default focus IDs are derived, lets the SwiftUI
    /// spelling compile and mean the right thing without a name that could
    /// collide.
    let declaredSectionID: String?

    var body: Never {
        fatalError("FocusSectionModifier renders via Renderable")
    }
}

// MARK: - Renderable

extension FocusSectionModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let focusManager = context.environment.focusManager
        let sectionID = declaredSectionID ?? "section-\(context.identity.path)"

        // Register the section with the focus manager (idempotent, skip during
        // measurement). Only with a focus manager present, because without one
        // nothing happens and the subtree is as cacheable as its content.
        //
        // Declared to any value-memoizing ancestor either way. Sections are
        // rebuilt every pass (`FocusManager.beginSceneRender`), so a subtree
        // served from the cache would leave the frame with no section at all and
        // whatever registers under it would have nowhere to go.
        //
        // While the section is INACTIVE that registration is simply made again
        // on every hit, at the point in the walk where this modifier would have
        // rendered — so section order, which is Tab's order, is the same whether
        // the subtree rendered or was served.
        //
        // While it is ACTIVE it still declines, because active-ness is not
        // something registering again reproduces: it is the manager's to decide,
        // and it is what picks the breathing ● handed to the subtree below. That
        // ● is drawn into the buffer, and it is assigned straight into the
        // environment rather than applied through a modifier, so neither the
        // memo's key nor `noteAppliedEnvironment` can see it change.
        //
        // Asked after registering rather than before: the first section
        // registered on an empty manager becomes the active one.
        if !context.isMeasuring, let focusManager {
            FocusSectionRegistrar.register(sectionID: sectionID, context: context)
            if focusManager.isActiveSection(sectionID) {
                context.environment.volatileReadTracker?.recordRenderSideEffect()
            } else {
                context.environment.volatileReadTracker?.recordReplayableEffect()
                if let journal = context.recordingEffectJournal {
                    // Built only while a memo records, so the live path
                    // allocates no second closure.
                    journal.append(
                        EffectJournal.Entry(
                            kind: FocusSectionRegistrar.kind,
                            channelToken: context.environment.keyChannelToken
                        ) { replay in
                            FocusSectionRegistrar.register(sectionID: sectionID, context: replay)
                        })
                }
            }
        }

        // Create a child context with the active section ID set,
        // so that focusable children (buttons, menus) register in this section.
        var sectionContext = context
        sectionContext.environment.activeFocusSectionID = sectionID

        // If this section is active, hand the subtree the breathing indicator.
        // The first border view in it will consume this and render ●.
        // Never active during measurement.
        //
        // Through the shared focus clock, so a section's ● breathes at the same
        // rate as every control inside it and honours
        // `.selectionIndicatorStyle(_:)` — and, on a 256-colour terminal, walks
        // the shades the cube can actually show. As a CYCLE rather than a live
        // phase, so the border can leave a run behind instead of the page
        // re-rendering on every tick.
        //
        // Published rather than assigned, so a value memo below hears the
        // answer change: the branch above declines to store only while the
        // section is ACTIVE, and a subtree stored while it was inactive would
        // otherwise be served unchanged once it became active.
        context.publishSectionIndicator(
            isActive: focusManager?.isActiveSection(sectionID) ?? false, into: &sectionContext)

        return TUIkit.renderToBuffer(content, context: sectionContext)
    }
}

// MARK: - Registration

/// The one registration `.focusSection` makes, shared by the live render and by
/// a value memo replaying it — see `EffectJournal`.
enum FocusSectionRegistrar {
    /// The journal kind of a focus-section registration.
    static let kind = EffectJournal.Kind("focusSection")

    /// Registers `sectionID` with `context`'s focus manager.
    ///
    /// It looks the manager up in `context` rather than taking one, so a replay
    /// registers into the ring of the frame that serves it.
    @MainActor
    static func register(sectionID: String, context: RenderContext) {
        context.environment.focusManager?.registerSection(id: sectionID)
    }
}

// MARK: - Layoutable

extension FocusSectionModifier: Layoutable {
    /// Focus grouping is size-neutral (the active-section id and the breathing
    /// indicator colour don't change layout), so it measures as `content`.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension FocusSectionModifier: SingleContentWrapper {
    var wrappedContent: Content { content }
}

// MARK: - Removal Transitions

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension FocusSectionModifier: DrawsContentUnchanged {}
