//  🖥️ TUIKit — Terminal UI Kit for Swift
//  NavigationCoordinator.swift
//
//  The rendezvous between a NavigationStack, the links inside it, and the
//  .navigationDestination modifiers that say what each pushed value shows.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - View destination token

/// The value a ``NavigationLink`` pushes when it was given a *view* to show
/// rather than a value to look up (`NavigationLink("Detail") { DetailView() }`).
///
/// The link has no data of its own to put on the path, so it pushes this token
/// and registers the view under the same id. The id is the link's own render
/// identity path, which is stable frame to frame and distinct per link — the
/// same property every default `focusID` in the framework relies on.
struct NavigationViewToken: Hashable {
    let id: String
}

// MARK: - NavigationCoordinator

/// Per-``NavigationStack`` state that has to outlive a single frame: the
/// destination registry, and the accessors for whichever path storage the
/// stack was created with.
///
/// Held by the stack in `@State` so it is one object for the stack's lifetime —
/// a `NavigationLink` rendered in frame 1 captures it, and the button action it
/// installs is still pushing onto the same path in frame 500.
///
/// `@MainActor`, unlike ``ScrollToRegistry`` which it otherwise resembles: this
/// one *builds views* (a destination is a `AnyView`-returning closure), and
/// every `View` initializer is main-actor isolated. Both of its callers — the
/// render loop and event dispatch — are already on the main actor.
@MainActor
final class NavigationCoordinator {

    /// Destination builders, keyed by the dynamic type of the value pushed.
    /// Registered by `.navigationDestination(for:)` as it renders, and never
    /// cleared: a builder must still be found on the frames where the modifier
    /// itself did not re-render.
    private var builders: [ObjectIdentifier: (AnyHashable) -> AnyView] = [:]

    /// Views pushed directly by `NavigationLink(destination:)`, keyed by the
    /// link's identity path. Refreshed every frame the link renders, which is
    /// every frame — the stack renders its root even while a screen is pushed.
    private var viewDestinations: [String: AnyView] = [:]

    /// Reads the current path. Re-installed by the stack each render pass, so
    /// it always reflects the binding the stack was given this frame.
    var read: () -> [AnyHashable] = { [] }

    /// Writes the path back. See ``read``.
    var write: ([AnyHashable]) -> Void = { _ in }

    init() {}
}

// MARK: - Path

extension NavigationCoordinator {

    /// How many screens are pushed above the root.
    var depth: Int { read().count }

    /// The value at the top of the path, or `nil` when showing the root.
    var top: AnyHashable? { read().last }

    /// Pushes a value, showing whatever destination matches its type.
    ///
    /// A typed path binding (`NavigationStack(path: $recipes)`) can only carry
    /// values of its own element type; pushing anything else onto one is
    /// dropped by the write-back, exactly as the binding's type says it must
    /// be. Use ``NavigationPath`` when the screens are driven by more than one
    /// type of value.
    func push(_ value: AnyHashable) {
        var elements = read()
        elements.append(value)
        write(elements)
    }

    /// Pops `count` screens, stopping at the root.
    func pop(_ count: Int = 1) {
        var elements = read()
        guard !elements.isEmpty else { return }
        elements.removeLast(min(count, elements.count))
        write(elements)
    }
}

// MARK: - Destinations

extension NavigationCoordinator {

    /// Registers the view to show for pushed values of type `D`.
    func register<D: Hashable>(_ type: D.Type, builder: @escaping (D) -> AnyView) {
        builders[ObjectIdentifier(type)] = { erased in
            guard let value = erased.base as? D else { return AnyView(EmptyView()) }
            return builder(value)
        }
    }

    /// Registers the view a `NavigationLink(destination:)` pushes.
    func register(viewDestination: AnyView, forToken id: String) {
        viewDestinations[id] = viewDestination
    }

    /// The view for a pushed value, or `nil` when nothing has claimed its type.
    ///
    /// A `nil` here is the navigation equivalent of a broken link: the value is
    /// on the path but no `.navigationDestination(for:)` for its type has ever
    /// rendered. The stack shows an empty screen with a working back button
    /// rather than dropping the value, so the app stays navigable.
    func destination(for value: AnyHashable) -> AnyView? {
        if let token = value.base as? NavigationViewToken {
            return viewDestinations[token.id]
        }
        return builders[ObjectIdentifier(type(of: value.base))].map { $0(value) }
    }
}

// MARK: - Environment

private struct NavigationCoordinatorKey: EnvironmentKey {
    static let defaultValue: NavigationCoordinator? = nil
}

extension EnvironmentValues {
    /// The enclosing ``NavigationStack``'s coordinator: the path the links
    /// inside push onto, and the registry `.navigationDestination(for:)` fills
    /// in. `nil` outside any stack, which is what makes a `NavigationLink`
    /// there inert rather than a crash.
    var navigationCoordinator: NavigationCoordinator? {
        get { self[NavigationCoordinatorKey.self] }
        set { self[NavigationCoordinatorKey.self] = newValue }
    }
}
