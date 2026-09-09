//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DismissSearchAction.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Dismiss Search Action

/// An action that ends the current search, mirroring SwiftUI's
/// `DismissSearchAction`.
///
/// Read it with `@Environment(\.dismissSearch)` from anywhere inside a
/// ``View/searchable(text:placement:prompt:)-(_,_,LocalizedStringKey)`` subtree, and call it like a
/// function. It clears the query and hands the keyboard back to the content —
/// the two halves of "stop searching".
///
/// ```swift
/// struct Results: View {
///     @Environment(\.isSearching) private var isSearching
///     @Environment(\.dismissSearch) private var dismissSearch
///
///     var body: some View {
///         if isSearching {
///             Button("Clear") { dismissSearch() }
///         }
///     }
/// }
/// ```
///
/// - Note: SwiftUI's version also takes the search field *away*, because there
///   the field is presented into a navigation bar. A terminal has no bar to
///   present into, so the field is simply part of the layout and stays where it
///   is; what dismissing can still mean here — and does — is that the query is
///   emptied and the field no longer holds focus.
///
/// Outside a searchable subtree the value read from the environment does
/// nothing, as in SwiftUI: a view that offers a Clear button need not know
/// whether anything is searching.
public struct DismissSearchAction: Sendable {
    /// What ending the search does here, or `nil` where nothing is searching.
    ///
    /// A stored closure for the same reason ``DismissAction`` uses one: the
    /// search field owns the query binding and its own focus, and hands down
    /// the one act that undoes both.
    private let action: (@MainActor @Sendable () -> Void)?

    /// Creates the inert action — what a view reads outside any searchable
    /// subtree.
    init() {
        self.action = nil
    }

    /// Creates an action that runs `action`, for
    /// ``View/searchable(text:placement:prompt:)-(_,_,LocalizedStringKey)`` to publish to its content.
    init(_ action: @escaping @MainActor @Sendable () -> Void) {
        self.action = action
    }

    /// Triggers the action. Equivalent to writing `dismissSearch()`.
    @MainActor
    public func callAsFunction() {
        action?()
    }
}

// MARK: - Environment Keys

/// Environment key for ``EnvironmentValues/isSearching``.
private struct IsSearchingKey: EnvironmentKey {
    static let defaultValue = false
}

/// Environment key for ``EnvironmentValues/dismissSearch``.
private struct DismissSearchActionKey: EnvironmentKey {
    static let defaultValue = DismissSearchAction()
}

extension EnvironmentValues {
    /// Whether the user is currently searching — SwiftUI's `\.isSearching`.
    ///
    /// True while the search field of an enclosing
    /// ``View/searchable(text:placement:prompt:)-(_,_,LocalizedStringKey)`` holds keyboard focus. As in
    /// SwiftUI it is readable only from that modifier's *content*: it answers
    /// "is the person typing at me right now", which is what lets results
    /// distinguish an empty query from a search nobody has started.
    ///
    /// ```swift
    /// @Environment(\.isSearching) private var isSearching
    ///
    /// if isSearching, results.isEmpty {
    ///     ContentUnavailableView.search(text: query)
    /// }
    /// ```
    ///
    /// Note what it is *not*: an empty-query test. The query is the app's own
    /// binding, and reading that is how you ask whether anything was typed.
    public internal(set) var isSearching: Bool {
        get { self[IsSearchingKey.self] }
        set { self[IsSearchingKey.self] = newValue }
    }

    /// An action that ends the current search — SwiftUI's `\.dismissSearch`.
    ///
    /// See ``DismissSearchAction``. Read it with
    /// `@Environment(\.dismissSearch)` and call it like a function; outside a
    /// searchable subtree it does nothing.
    public internal(set) var dismissSearch: DismissSearchAction {
        get { self[DismissSearchActionKey.self] }
        set { self[DismissSearchActionKey.self] = newValue }
    }
}
