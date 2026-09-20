//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PresentationTraits.swift
//
//  Things a sheet's CONTENT says about how it should be presented, read by the
//  thing presenting it: how tall to be (``PresentationDetent``), and whether
//  the reader is allowed to dismiss it by hand (here).
//
//  All of them travel the same way — a wrapper view the presenter finds by a
//  static conformance check, not a preference. A preference is only readable
//  after the subtree renders, and every one of these has to be known BEFORE
//  it: the detent is the height being rendered into, and the Escape item is
//  registered on the status bar before the content exists.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Looking through the wrappers

/// A trait wrapper that can be seen past, so a second trait applied beneath it
/// is still found.
///
/// Without this each trait would have to be the presented content's outermost
/// view, and applying two would silently drop whichever ended up inner —
/// `.presentationDetents([.medium]).interactiveDismissDisabled()` and the same
/// pair the other way round would behave differently, for no reason a reader
/// could see.
@MainActor
protocol PresentationTraitWrapper {
    /// The view directly beneath this wrapper.
    var presentationTraitContent: any View { get }
}

/// The outermost `T` in a chain of presentation-trait wrappers, if there is one.
///
/// Each step strictly descends one wrapper, so the walk terminates on any tree.
@MainActor
func presentationTrait<T>(_ type: T.Type, of view: any View) -> T? {
    var current = view
    while true {
        if let match = current as? T { return match }
        guard let wrapper = current as? any PresentationTraitWrapper else { return nil }
        current = wrapper.presentationTraitContent
    }
}

// The `@ViewBuilder`'s own bookkeeping is looked through as well. `if` and
// `if`/`else` in a sheet's builder are ordinary things to write, and neither
// puts a view in the tree that the author can see — so a trait "applied to the
// content" would be invisible for a reason nobody could deduce from their own
// source. That is the whole list: these two, and the trait wrappers themselves.
// Anything the author actually wrote (an `AnyView`, a `Group`, a view of their
// own) still has to be inside the trait, which is the documented rule.

extension ConditionalView: PresentationTraitWrapper {
    var presentationTraitContent: any View {
        switch self {
        case .trueContent(let view): view
        case .falseContent(let view): view
        }
    }
}

extension Optional: PresentationTraitWrapper where Wrapped: View {
    var presentationTraitContent: any View { self ?? EmptyView() }
}

// MARK: - interactiveDismissDisabled()

/// Content that has asked not to be dismissed by hand.
@MainActor
protocol InteractiveDismissDisabling {
    /// Whether Escape and an outside click should stop closing the presentation.
    var interactiveDismissIsDisabled: Bool { get }
}

/// The wrapper ``View/interactiveDismissDisabled(_:)`` produces. Renders and
/// measures as its content; carrying the flag is its whole job.
struct _InteractiveDismissView<Content: View>: View, InteractiveDismissDisabling {
    let content: Content
    let interactiveDismissIsDisabled: Bool

    var body: Never {
        fatalError("_InteractiveDismissView renders via Renderable")
    }
}

extension _InteractiveDismissView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkit.renderToBuffer(content, context: context)
    }
}

extension _InteractiveDismissView: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

extension _InteractiveDismissView: PresentationTraitWrapper {
    var presentationTraitContent: any View { content }
}

extension View {
    /// Conditionally prevents a presentation from being dismissed by hand.
    ///
    /// Mirrors SwiftUI's `interactiveDismissDisabled(_:)`. Apply it to the
    /// presented **content**:
    ///
    /// ```swift
    /// .sheet(isPresented: $editing) {
    ///     Editor()
    ///         .interactiveDismissDisabled(hasUnsavedChanges)
    /// }
    /// ```
    ///
    /// SwiftUI's gesture is a downward swipe; a terminal's are **Escape** and a
    /// click outside, so those are what this suppresses. Everything else still
    /// closes the presentation: a `Done` button flipping the binding,
    /// `@Environment(\.dismiss)`, or the app setting it to `false` — which is
    /// the point of the modifier, not a gap in it. It is how a sheet insists on
    /// an answer rather than letting the reader wander off.
    ///
    /// A dismissal-disabled popover still swallows the click that lands outside
    /// it. Letting that click through to the page would be the opposite of what
    /// was asked for: the presentation stays up and something behind it acts.
    ///
    /// Alerts and confirmation dialogs are unaffected. Escape there does not
    /// dismiss anything — it CHOOSES the `.cancel`-role button, which is an
    /// answer, and an answer is not something this modifier takes away.
    ///
    /// - Parameter isDisabled: Whether to prevent interactive dismissal.
    ///   Default `true`.
    public func interactiveDismissDisabled(_ isDisabled: Bool = true) -> some View {
        _InteractiveDismissView(content: self, interactiveDismissIsDisabled: isDisabled)
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension _InteractiveDismissView: SingleContentWrapper {
    var wrappedContent: Content { content }
}
