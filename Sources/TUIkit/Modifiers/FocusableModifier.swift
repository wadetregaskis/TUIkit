//  🖥️ TUIKit — Terminal UI Kit for Swift
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
    /// - Parameter isFocusable: Whether the view can receive focus.
    public func focusable(_ isFocusable: Bool = true) -> some View {
        FocusableModifier(content: self, isFocusable: isFocusable, interactions: .automatic)
    }

    /// Marks this view as able to receive focus, with the given interactions.
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
    static let focusID = 0
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

        var buffer = TUIkit.renderToBuffer(content, context: context)

        // `.activate` → click anywhere in the content to focus it.
        if let focusID, interactions.contains(.activate),
            let mouseDispatcher = context.environment.mouseEventDispatcher
        {
            let focusManager = context.environment.focusManager
            let handlerID = mouseDispatcher.register { event in
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
            handler: ActionHandler(focusID: id, action: {}, triggerKeys: []))
        return id
    }
}

// MARK: - Layoutable

extension FocusableModifier: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}
