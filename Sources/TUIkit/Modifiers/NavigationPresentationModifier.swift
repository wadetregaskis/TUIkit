//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationPresentationModifier.swift
//
//  The BINDING-driven navigation destinations: push a screen because a flag
//  went true, pop it when the flag clears — and clear the flag when the user
//  pops it themselves.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - navigationDestination(isPresented:) / (item:)

extension View {
    /// Pushes `destination` onto the enclosing ``NavigationStack`` while
    /// `isPresented` is true.
    ///
    /// The counterpart of ``navigationDestination(for:destination:)`` for a
    /// screen with no value behind it — a settings page, an editor — where what
    /// says "show it" is a flag rather than a pushed value.
    ///
    /// The binding is two-way, which is the substance of it: clearing the flag
    /// pops the screen, and popping the screen (Back, or Escape) clears the
    /// flag. Either side can drive it and neither has to know which one did.
    ///
    /// ```swift
    /// NavigationStack {
    ///     Button("Settings") { showingSettings = true }
    ///         .navigationDestination(isPresented: $showingSettings) {
    ///             SettingsScreen()
    ///         }
    /// }
    /// ```
    ///
    /// Apply it inside the stack, on a view that stays on screen — the root, or
    /// something in it. The stack's root keeps rendering while a screen is
    /// pushed (off-screen, isolated from focus), which is what keeps this
    /// modifier live to notice a pop; a modifier written on a screen that is
    /// itself covered has stopped rendering and cannot.
    ///
    /// - Parameters:
    ///   - isPresented: Whether the destination is on the stack.
    ///   - destination: The screen to push.
    /// - Returns: A view that pushes a screen while the binding is true.
    public func navigationDestination<Destination: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationPresentationModifier(
            content: self, isPresented: isPresented, destination: { destination() })
    }

    /// Pushes a screen built from `item` while it is non-`nil`.
    ///
    /// The same mechanism as ``navigationDestination(isPresented:destination:)``
    /// with the flag and the value collapsed into one Optional — which is what
    /// you want when the screen is ABOUT something, because it makes "shown"
    /// and "has something to show" the same fact rather than two that can
    /// disagree. Popping the screen sets the item to `nil`.
    ///
    /// - Parameters:
    ///   - item: The value the pushed screen describes. `nil` shows nothing.
    ///   - destination: The screen to push, built from the item.
    /// - Returns: A view that pushes a screen while the binding holds a value.
    public func navigationDestination<D: Hashable, C: View>(
        item: Binding<D?>,
        @ViewBuilder destination: @escaping (D) -> C
    ) -> some View {
        NavigationPresentationModifier(
            content: self,
            // Reads as "is there something"; a write of `false` clears it. A
            // write of `true` cannot invent a value and is ignored, which is
            // only ever the modifier echoing back a state it already reached.
            isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } }),
            destination: { item.wrappedValue.map(destination) })
    }
}

// MARK: - Modifier

/// StateStorage property indices for ``NavigationPresentationModifier``.
private enum StateIndex {
    /// Whether THIS modifier is what put its token on the path.
    static let didPush = 0
}

/// Keeps one token on the enclosing stack's path in step with a Boolean.
///
/// Registered like a `NavigationLink(destination:)`'s screen — under a
/// ``NavigationViewToken`` keyed by this modifier's identity path, which is
/// stable across frames and unique to it — so the stack can show a screen that
/// has no value behind it.
struct NavigationPresentationModifier<Content: View, Destination: View>: View {
    let content: Content
    let isPresented: Binding<Bool>
    /// The screen to show, or `nil` when there is nothing to show one about.
    let destination: () -> Destination?

    var body: Never {
        fatalError("NavigationPresentationModifier renders via Renderable")
    }
}

extension NavigationPresentationModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Render passes only: reconciling on a measure would push a screen for
        // a frame that is only asking how big things are, and the two-pass
        // layout asks several times per frame.
        if !context.isMeasuring, let coordinator = context.environment.navigationCoordinator,
            let stateStorage = context.stateStorage
        {
            reconcile(coordinator: coordinator, stateStorage: stateStorage, context: context)
        }
        return TUIkit.renderToBuffer(content, context: context)
    }

    /// Brings the path and the binding into agreement, in whichever direction
    /// they last disagreed.
    ///
    /// The four states are not symmetric, and the asymmetry is the whole
    /// design. "Flag true, token absent" is ambiguous — it is both *the app
    /// just asked for this screen* and *the user just popped it* — so the
    /// modifier remembers whether IT was the one that pushed. Without that
    /// memory a Back press pushes the screen straight back on, forever.
    @MainActor
    private func reconcile(
        coordinator: NavigationCoordinator, stateStorage: StateStorage, context: RenderContext
    ) {
        // The did-push memory is a MANUAL box, so nothing hydrates this
        // identity and `endRenderPass` would prune it at the end of every frame
        // — leaving the reconciler to rediscover "the flag is true and the
        // screen is not up" as a reason to push, forever. Same gotcha
        // `OnChangeModifier` and `RefreshableModifier` answer the same way.
        stateStorage.markActive(context.identity)
        let token = AnyHashable(NavigationViewToken(id: context.identity.path))
        let path = coordinator.read()
        let onPath = path.contains(token)
        let didPush: StateBox<Bool> = stateStorage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.didPush),
            default: false)

        guard isPresented.wrappedValue else {
            // The app cleared the flag: take the screen off, and anything the
            // screen itself pushed above it — popping to the token alone would
            // leave the user on a screen reached THROUGH one that is gone.
            if onPath, let index = path.firstIndex(of: token) {
                coordinator.pop(path.count - index)
            }
            didPush.value = false
            return
        }

        guard onPath else {
            if didPush.value {
                // We pushed it and it is gone, so the user popped it. Report
                // that rather than pushing it again.
                didPush.value = false
                isPresented.wrappedValue = false
            } else {
                register(coordinator: coordinator, token: token)
                coordinator.push(token)
                didPush.value = true
            }
            return
        }

        // Still up: re-register, so the screen is rebuilt from whatever the
        // surrounding view holds THIS frame. `navigationDestination(for:)` does
        // the same, and for the same reason.
        register(coordinator: coordinator, token: token)
    }

    /// Hands the coordinator the screen this token stands for.
    @MainActor
    private func register(coordinator: NavigationCoordinator, token: AnyHashable) {
        guard let id = (token.base as? NavigationViewToken)?.id, let screen = destination()
        else { return }
        coordinator.register(viewDestination: AnyView(screen), forToken: id)
    }
}

extension NavigationPresentationModifier: Layoutable {
    /// Measures as its content: the push is the whole of this modifier's
    /// effect, and it contributes no geometry.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}
