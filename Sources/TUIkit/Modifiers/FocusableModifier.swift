//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusableModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

/// The interactions a focusable view supports. Mirrors SwiftUI's
/// `FocusInteractions`.
public struct FocusInteractions: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// The view can be activated — in a terminal, clicked to focus it.
    public static let activate = Self(rawValue: 1 << 0)

    /// The view supports editing interactions. (No terminal-distinct behaviour
    /// beyond being a focus stop; carried for SwiftUI parity.)
    public static let edit = Self(rawValue: 1 << 1)

    /// The default set of interactions.
    public static let automatic: FocusInteractions = [.activate, .edit]
}

extension View {
    /// Marks this view as able to receive focus.
    ///
    /// A focusable view becomes a Tab stop and can be bound with `@FocusState`
    /// via `.focused(_:)` / `.focused(_:equals:)` — which is what makes those
    /// modifiers work on an otherwise non-interactive view like `Text`.
    ///
    /// `false` is the other half of the parameter and not merely the absence of
    /// the first: it takes the content OUT of the ring, so a control that
    /// registers a stop of its own — a `Button`, a `TextField` — stops being a
    /// Tab stop and stops answering Return. See the `.focusable` entry in
    /// `Documentation/SwiftUI-compatibility.md` for the two ways that differs
    /// from SwiftUI, both of which follow from a terminal modifier addressing a
    /// SUBTREE where SwiftUI addresses one node: it reaches every control
    /// inside, and it is ADDITIVE — an inner `.focusable(true)` does not re-open
    /// a subtree an ancestor closed, exactly as `.disabled(false)` cannot
    /// re-enable one.
    ///
    /// - Parameter isFocusable: Whether the view can receive focus.
    public func focusable(_ isFocusable: Bool = true) -> some View {
        FocusableModifier(content: self, isFocusable: isFocusable, interactions: .automatic)
    }

    /// Marks this view as able to receive focus, with the given interactions.
    ///
    /// `false` suppresses the content's own focus stops as it does on
    /// ``View/focusable(_:)``; `interactions` then names nothing, there being no
    /// stop to interact with.
    ///
    /// - Parameters:
    ///   - isFocusable: Whether the view can receive focus.
    ///   - interactions: The interactions the view supports. `.activate` adds
    ///     click-to-focus.
    public func focusable(_ isFocusable: Bool = true, interactions: FocusInteractions) -> some View {
        FocusableModifier(content: self, isFocusable: isFocusable, interactions: interactions)
    }
}

/// `StateStorage` property indices for ``FocusableModifier`` (a static index on
/// the generic type isn't allowed, so it lives at file scope).
private enum FocusableStateIndex {
    // Negative: infrastructure slots share the wrapped content's identity,
    // and 0... belongs to a composite content view's own @State. See
    // `StateStorage.StateKey`'s reserved-range table.
    static let focusID = -10
}

/// Registers its content as a focus stop (see ``View/focusable(_:)``). It is
/// size-neutral: focusability never changes layout, so it measures as `content`.
struct FocusableModifier<Content: View>: View {
    let content: Content
    let isFocusable: Bool
    let interactions: FocusInteractions

    var body: Never {
        fatalError("FocusableModifier renders via Renderable")
    }
}

// MARK: - Renderable

extension FocusableModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Register the focus stop BEFORE rendering content, so this view precedes
        // any focusable children in the ring (as a control registers before its
        // label). Returns the id only when a stop was actually registered.
        let focusID = registerFocusStop(context: context)

        var contentContext = context

        // `.focusable(false)` is not "add no stop of my own" — SwiftUI's
        // parameter is documented as "`false` otherwise", the view not taking
        // part in focus at all — so the content's OWN registrations have to stop
        // too, or a `Button` told it is not focusable goes on taking Tab and
        // Return. `isFocusSuppressed` is that, and centrally: every control
        // reaches the ring through `FocusRegistrar.register`, which consults it,
        // and a replay out of a value memo consults the serving frame's copy.
        //
        // One-way, and deliberately so. This is the same flag `.hidden()` sets,
        // and a `.focusable()` inside a hidden subtree must STAY out of the ring
        // — there is no picture for Tab to land on — so the `true` case must not
        // write `false` here. An inner `.focusable(true)` therefore does not
        // re-open a subtree an ancestor closed, which is how `.disabled(_:)`
        // composes two files over, and is recorded as a deviation in
        // `Documentation/SwiftUI-compatibility.md`.
        if !isFocusable { contentContext.environment.isFocusSuppressed = true }

        // Tell the content whether it holds the focus, the way SwiftUI's
        // `.focusable()` does. Without this the modifier makes a view reachable
        // by Tab and gives it no way to SAY so: `\.isFocused` stayed false
        // however the ring moved, and an app's own control could be focused
        // while drawing exactly as it does when it is not. `.contextMenu` had
        // been publishing it for its own content all along; this is the same
        // thing, from the modifier that actually owns the focus stop.
        // Published, not assigned: a bare assignment is invisible to a memo
        // inside the content, which then served the unfocused frame after Tab
        // arrived (see `FocusRegistration.publishIsFocused`).
        let isFocused = focusID.map { FocusRegistration.isFocused(context: context, focusID: $0) }
        FocusRegistration.publishIsFocused(isFocused, context: context, into: &contentContext)

        var buffer = TUIkit.renderToBuffer(content, context: contentContext)

        // `.activate` → click anywhere in the content to focus it. Not while an
        // ancestor suppresses focus: `registerFocusStop` still hands back an id
        // there (it must — the id's `StateStorage` slot has to stay marked
        // active, and the ring's own guard lives one call further in), but
        // nothing filed it, so the click would land on `FocusManager.focus(id:)`
        // with an id no section holds — a pending intent, re-rendering for a
        // couple of passes to look for a control that is not coming.
        if let focusID, interactions.contains(.activate),
            !context.environment.isFocusSuppressed,
            let mouseDispatcher = context.environment.mouseEventDispatcher
        {
            let focusManager = context.environment.focusManager
            let handlerID = mouseDispatcher.register(in: context) { event in
                switch event.phase {
                case .pressed where event.button == .left:
                    // Claim the press so the release routes back here.
                    return true
                case .released where event.button == .left:
                    focusManager?.focus(id: focusID)
                    return true
                default:
                    return false
                }
            }
            buffer.hitTestRegions.append(
                HitTestRegion(
                    offsetX: 0,
                    offsetY: 0,
                    width: buffer.width,
                    height: buffer.height,
                    handlerID: handlerID,
                    focusID: focusID))
        }

        return buffer
    }

    /// Registers a bare focus stop unless the view is disabled, not focusable, or
    /// this is a measurement pass. Returns the persisted focusID, or `nil` if no
    /// stop was registered.
    private func registerFocusStop(context: RenderContext) -> String? {
        // Disabled views MUST NOT register — they neither steal focus nor
        // participate in the ring.
        guard isFocusable,
            context.environment.isEnabled,
            !context.isMeasuring,
            context.environment.focusManager != nil
        else { return nil }

        let id = FocusRegistration.persistFocusID(
            context: context,
            explicitFocusID: nil,
            defaultPrefix: "focusable",
            propertyIndex: FocusableStateIndex.focusID)

        // `triggerKeys: []` → a focus stop that consumes no keys, so the content
        // keeps whatever key behaviour it already has (Enter/Space fall through).
        FocusRegistration.register(
            context: context,
            handler: ActionHandler(focusID: id, action: {}, triggerKeys: []),
            focusID: id)
        return id
    }
}

// MARK: - Layoutable

extension FocusableModifier: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        // One environment application deeper, as the render walk hands its
        // content — bumped by hand, never through `publishIsFocused`, which
        // must not note from a measure (see there).
        var contentContext = context
        contentContext.environmentApplicationDepth += 1
        return measureChild(content, proposal: proposal, context: contentContext)
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension FocusableModifier: SingleContentWrapper {
    var wrappedContent: Content { content }
}

// MARK: - Removal Transitions

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension FocusableModifier: DrawsContentUnchanged {}
