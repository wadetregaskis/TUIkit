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

        // Register the section with the focus manager (idempotent, skip during measurement).
        if !context.isMeasuring {
            focusManager?.registerSection(id: sectionID)
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
        sectionContext.environment.focusIndicator = AnimatedColor.activeSection(
            !context.isMeasuring && (focusManager?.isActiveSection(sectionID) ?? false),
            in: context.environment)

        return TUIkit.renderToBuffer(content, context: sectionContext)
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
