//  🖥️ TUIKit — Terminal UI Kit for Swift
//  NavigationPath.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - NavigationPath

/// A type-erased list of data representing the content of a navigation stack.
/// Matches SwiftUI's type of the same name.
///
/// Use a `NavigationPath` when the screens a ``NavigationStack`` can push are
/// driven by values of *different* types — a `Recipe` here, an `Ingredient`
/// there. A homogeneous stack can bind a plain array instead:
/// `NavigationStack(path: $recipes)`.
///
/// ```swift
/// @State private var path = NavigationPath()
///
/// var body: some View {
///     NavigationStack(path: $path) {
///         List {
///             NavigationLink("Bread", value: Recipe.bread)
///         }
///         .navigationDestination(for: Recipe.self) { RecipeView(recipe: $0) }
///         .navigationDestination(for: Ingredient.self) { IngredientView($0) }
///     }
/// }
///
/// // Somewhere else — return to the root from any depth:
/// path.removeLast(path.count)
/// ```
///
/// > Note: SwiftUI's `CodableRepresentation` (which serialises a path by
///   recording each element's type name) is not implemented — restoring one
///   needs a runtime type-name lookup TUIkit does not have on every platform
///   it targets. Persist your own array of values instead and rebuild the path
///   with ``init(_:)``.
public struct NavigationPath: Equatable {

    /// The pushed values, root-most first. `AnyHashable` is exactly the
    /// erasure SwiftUI describes: the elements need only be `Hashable`, and
    /// `AnyHashable` keeps both the value and its dynamic type — which is what
    /// lets ``NavigationStack`` find the matching `.navigationDestination`.
    var elements: [AnyHashable]

    /// Creates an empty navigation path.
    public init() {
        self.elements = []
    }

    /// Creates a navigation path from the given hashable values.
    public init<S: Sequence>(_ elements: S) where S.Element: Hashable {
        self.elements = elements.map { AnyHashable($0) }
    }

    /// Creates a navigation path from already-erased values.
    init(erased elements: [AnyHashable]) {
        self.elements = elements
    }

    /// The number of values in the path.
    public var count: Int { elements.count }

    /// Whether the path is empty — the stack is showing its root view.
    public var isEmpty: Bool { elements.isEmpty }

    /// Appends a value to the end of the path, pushing a screen.
    public mutating func append<V: Hashable>(_ value: V) {
        elements.append(AnyHashable(value))
    }

    /// Removes the last `k` values, popping that many screens.
    ///
    /// - Parameter k: How many values to remove. Defaults to 1. Removing more
    ///   than the path holds is a programmer error, as in SwiftUI.
    public mutating func removeLast(_ k: Int = 1) {
        elements.removeLast(k)
    }
}
