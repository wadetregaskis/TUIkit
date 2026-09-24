//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationDestinationModifier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - navigationDestination(for:destination:)

extension View {
    /// Associates a destination view with a type of data, for a
    /// ``NavigationStack`` to present when a value of that type is pushed.
    /// Matches SwiftUI's signature exactly.
    ///
    /// ```swift
    /// NavigationStack {
    ///     List(recipes) { recipe in
    ///         NavigationLink(recipe.name, value: recipe)
    ///     }
    ///     .navigationDestination(for: Recipe.self) { recipe in
    ///         RecipeView(recipe: recipe)
    ///     }
    /// }
    /// ```
    ///
    /// Apply this inside the stack — on the root view or anything within it.
    /// The stack finds it as the modifier renders, so a type whose destination
    /// modifier has never been on screen has nothing to show; declaring them on
    /// the root, as above, is what SwiftUI's own documentation recommends and
    /// what keeps every type reachable.
    ///
    /// - Parameters:
    ///   - data: The type of value to present a destination for.
    ///   - destination: A view builder that makes the screen for one value.
    public func navigationDestination<D: Hashable, C: View>(
        for data: D.Type,
        @ViewBuilder destination: @escaping (D) -> C
    ) -> some View {
        NavigationDestinationModifier(content: self, data: data, destination: destination)
    }
}

// MARK: - Modifier

/// Registers `destination` with the enclosing stack's coordinator, and renders
/// its content unchanged.
struct NavigationDestinationModifier<Content: View, D: Hashable, C: View>: View {
    let content: Content
    let data: D.Type
    let destination: (D) -> C

    var body: Never {
        fatalError("NavigationDestinationModifier renders via Renderable")
    }
}

extension NavigationDestinationModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Register on render passes only — a measure pass would install the
        // same builder a second time within one frame for no gain. The
        // registration deliberately does NOT declare a render side effect: it
        // persists in the coordinator across frames, so a memoized subtree that
        // stops re-registering keeps working. What re-registration buys is
        // freshness — the closure captures whatever the surrounding view held
        // this frame — and the stack renders its root every frame precisely so
        // that stays true while a screen is pushed.
        if !context.isMeasuring, let coordinator = context.environment.navigationCoordinator {
            let build = destination
            coordinator.register(data) { AnyView(build($0)) }
        }
        return TUIkit.renderToBuffer(content, context: context)
    }
}

extension NavigationDestinationModifier: Layoutable {
    /// Measures as its content: the registration is the whole of this
    /// modifier's effect, and it contributes no geometry.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension NavigationDestinationModifier: SingleContentWrapper {
    var wrappedContent: Content { content }
}

// MARK: - Removal Transitions

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension NavigationDestinationModifier: DrawsContentUnchanged {}
