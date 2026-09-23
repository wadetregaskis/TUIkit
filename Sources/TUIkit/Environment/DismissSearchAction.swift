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
    /// The search this ends, or `nil` where nothing is searching.
    fileprivate let dismissal: SearchDismissal?

    /// Creates the action that ends `dismissal`'s search — the inert one for
    /// `nil`, which is what a view reads outside any searchable subtree.
    init(_ dismissal: SearchDismissal? = nil) {
        self.dismissal = dismissal
    }

    /// Triggers the action. Equivalent to writing `dismissSearch()`.
    @MainActor
    public func callAsFunction() {
        dismissal?.dismiss()
    }
}

// MARK: - The search a modifier holds

/// What ending one searchable's search does, kept by that modifier and handed
/// to its content through the environment.
///
/// An object the modifier holds in `@State` rather than a closure it builds,
/// for the reason `ScrollViewReader`'s registry is one (`2964e3e5`): the
/// environment value must be comparable, or it turns every memo off beneath
/// it, and a closure cannot be compared. As a closure it was, and the whole of
/// every searchable's content was drawn from scratch on every frame. One object
/// for the modifier's life compares by identity, and the modifier refreshes it
/// with the query binding, the focus manager and whether the field is being
/// typed in each time its body runs — so an action read on an earlier frame
/// and called now does what ending the search means NOW, where a captured
/// closure would have done what it meant then.
@MainActor
final class SearchDismissal: Equatable {
    var text: Binding<String>?
    weak var focusManager: FocusManager?
    var isSearching = false

    /// Ending the search: empty the query, and give the keyboard back.
    ///
    /// The focus move is conditional because the action is callable from
    /// anywhere in the content — a Clear button in a results list is the
    /// canonical shape — and moving focus off a control the user is actually
    /// using would be a bug, not a dismissal. Focus goes to the *next*
    /// focusable, which is the content: the field is drawn above it, so this is
    /// the same step Tab would take out of the field.
    func dismiss() {
        text?.wrappedValue = ""
        if isSearching { focusManager?.focusNext() }
    }

    nonisolated static func == (lhs: SearchDismissal, rhs: SearchDismissal) -> Bool { lhs === rhs }
}

// MARK: - Environment Keys

/// Environment key for ``EnvironmentValues/isSearching``.
private struct IsSearchingKey: EnvironmentKey {
    static let defaultValue = false
}

/// Environment key for ``EnvironmentValues/dismissSearch``: the search it
/// ends, comparable by identity, rather than the action itself.
private struct SearchDismissalKey: EnvironmentKey {
    static let defaultValue: SearchDismissal? = nil
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
        get { DismissSearchAction(self[SearchDismissalKey.self]) }
        set { self[SearchDismissalKey.self] = newValue.dismissal }
    }

    /// The search ``dismissSearch`` ends, by the key path the searchable
    /// modifier writes it through: an environment write is judged comparable
    /// by the type of the value WRITTEN, so writing the action, which is not
    /// `Equatable` (nor is SwiftUI's), would still turn every memo off.
    var searchDismissal: SearchDismissal? {
        get { self[SearchDismissalKey.self] }
        set { self[SearchDismissalKey.self] = newValue }
    }
}
