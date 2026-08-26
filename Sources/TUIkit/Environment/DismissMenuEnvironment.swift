//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DismissMenuEnvironment.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - dismissMenu

/// An action that closes the enclosing pop-up menu — set by a ``ContextMenu`` on
/// its item subtree, read by ``Button`` so selecting an item runs its action AND
/// closes the menu (SwiftUI's menu auto-dismiss behaviour).
///
/// `@unchecked Sendable`: the closure is created and invoked only on the render
/// loop's single thread — the same latitude every action closure relies on — so
/// it can be a concurrency-safe environment default.
struct DismissMenuAction: @unchecked Sendable {
    let action: () -> Void
    func callAsFunction() { action() }
}

private struct DismissMenuKey: EnvironmentKey {
    static let defaultValue: DismissMenuAction? = nil
}

extension EnvironmentValues {
    /// Closes the enclosing pop-up menu, if any. `nil` outside a menu's item
    /// subtree, so a ``Button`` elsewhere on the page is unaffected.
    var dismissMenu: DismissMenuAction? {
        get { self[DismissMenuKey.self] }
        set { self[DismissMenuKey.self] = newValue }
    }
}

// MARK: - menuActionDismissBehavior

/// Whether choosing an item closes the menu it was chosen from — SwiftUI's
/// `MenuActionDismissBehavior`, applied with
/// ``TUIkit/View/menuActionDismissBehavior(_:)``.
///
/// A struct of static members rather than an enum, matching SwiftUI (and
/// ``ButtonRole`` beside it): the cases are a fixed vocabulary the caller
/// spells, not something anyone switches over.
public struct MenuActionDismissBehavior: Equatable, Sendable {
    private let rawValue: String

    private init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// Let the menu decide — which, for every menu TUIkit draws, means it
    /// closes. The default.
    public static let automatic = Self("automatic")

    /// Choosing an item always closes the menu.
    public static let enabled = Self("enabled")

    /// Choosing an item leaves the menu open, so more than one can be chosen
    /// without re-opening it. Escape and an outside click still close it —
    /// this governs the ITEMS, not the menu's other exits.
    ///
    /// One gesture overrules it: a menu opened by **press-and-hold** closes on
    /// the release that ends the hold, even here. That release is the end of a
    /// tracking session, not a click — the button is up and the gesture holding
    /// the menu is over, so keeping it on screen would strand it in a state the
    /// user has no way to continue. The clicks this behaviour exists for still
    /// work: click to open, then click item after item.
    ///
    /// - Note: TUI-specific in a small way. SwiftUI declares this case
    ///   `@available(macOS, unavailable)` — a Mac menu always closes behind a
    ///   choice — so on the only platform family a terminal resembles there is
    ///   no behaviour to copy. TUIkit offers it anyway (a settings menu wants
    ///   it, and iOS has had it since 16.4), which is why the press-and-hold
    ///   rule above had to be decided rather than inherited.
    public static let disabled = Self("disabled")

    /// Whether an item's action should close the menu it fired from.
    ///
    /// A computed answer rather than `!= .disabled` at the call site, so
    /// adding a spelling later is a decision made here once instead of a
    /// silent vote for dismissal everywhere — the same trap
    /// ``ScrollIndicatorVisibility/showsIndicator(overflowing:)`` exists to close.
    var dismissesMenu: Bool {
        switch self {
        case .disabled: false
        // `.automatic` defers to "the policies of the component", and a
        // menu's policy — here as on every desktop — is to close behind a
        // choice. `.enabled` says so explicitly; both dismiss.
        default: true
        }
    }
}

private struct MenuActionDismissBehaviorKey: EnvironmentKey {
    static let defaultValue = MenuActionDismissBehavior.automatic
}

extension EnvironmentValues {
    /// What a menu item does to its menu when it fires. See
    /// ``TUIkit/View/menuActionDismissBehavior(_:)``.
    ///
    /// Internal: SwiftUI exposes no `EnvironmentValues` member for this either,
    /// the modifier being the whole API.
    var menuActionDismissBehavior: MenuActionDismissBehavior {
        get { self[MenuActionDismissBehaviorKey.self] }
        set { self[MenuActionDismissBehaviorKey.self] = newValue }
    }
}

extension View {
    /// Tells menus within this view whether choosing an item dismisses them.
    ///
    /// The default closes the menu behind a choice, which is what a menu of
    /// commands wants. A menu whose items are *settings* wants the opposite —
    /// re-opening it after every flip is the whole cost of putting them there:
    ///
    /// ```swift
    /// Menu("View") {
    ///     Button(showsHidden ? "✓ Hidden files" : "  Hidden files") {
    ///         showsHidden.toggle()
    ///     }
    ///     Button(showsSizes ? "✓ Sizes" : "  Sizes") { showsSizes.toggle() }
    /// }
    /// .menuActionDismissBehavior(.disabled)
    /// ```
    ///
    /// It reaches every item in the subtree, so it can be applied to one
    /// `Button` inside an otherwise ordinary menu just as well as to the whole
    /// menu. Outside a menu it does nothing: a page's buttons have no menu to
    /// close.
    ///
    /// - Parameter behavior: Whether an item's action closes its menu.
    public func menuActionDismissBehavior(
        _ behavior: MenuActionDismissBehavior
    ) -> some View {
        environment(\.menuActionDismissBehavior, behavior)
    }
}
