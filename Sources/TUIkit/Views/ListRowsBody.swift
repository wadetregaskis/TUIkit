//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListRowsBody.swift
//
//  A `List` or a `Section` looking through a view of the app's own to the
//  rows its `body` holds — the one wrapper `ListRowsPassThrough` cannot
//  describe, because its rows exist only once its body is evaluated.
//
//  Created by Wade Tregaskis
//  License: MIT

/// The evaluated `body` of a view of the app's own, and the context its rows
/// are extracted under — see ``listRowsBody(of:context:)``.
struct ListRowsBody {
    /// The body, evaluated as a render evaluates it.
    let content: any View

    /// One identity step inside the view's own: the step the render walk takes
    /// into a body, so every row lands where drawing the view would have put
    /// it.
    let context: RenderContext
}

/// The body of `view`, when `view` is a view of the app's own whose `body` is
/// list rows — a `ForEach`, an `OutlineGroup` or a `Section`, as they are or
/// inside any number of `Group`s, `if`/`else`s, lone `if`s and further views
/// of the app's own — and `nil` for anything else, which a `List` and a
/// `Section` draw as one row, as they always have.
///
/// `List { Rows() }`, where `Rows.body` is the loop, is SwiftUI's own way to
/// factor a list's rows out (measured in an `NSHostingView` on macOS 15.8:
/// three elements are three rows, each selected by its element, each with a
/// Delete action that removes the element it draws — flat, in a `Section`,
/// with `@State` on `Rows`, one such view inside another, and with an
/// `if`/`else` body). Asked of `Rows` itself, every question the list asks of
/// its content — ``ListRowsPassThrough`` lists them — stopped there, and the
/// whole loop was drawn as ONE row, answering to no `String` selection and
/// taking no Delete, drop or pick-up.
///
/// The body is evaluated exactly as a render evaluates it
/// (`evaluateCompositeBody(of:context:)`): `@Environment` resolved, `@State`
/// bound at `context.identity` — the view's own identity, where drawing it as
/// one row bound it too — and the evaluation observed, so a change to an
/// `@Observable` it read invalidates the view, and with it every row below.
/// The rows then land one identity step in, as the render walk's would, so
/// no row's `@State` or render-cache entry moves.
///
/// Decided from the view's TYPE (``viewTypeHoldsListRowsInBody(_:)``), before
/// anything is evaluated, so a view whose body cannot be rows — a stack, a
/// `Text`, `AnyView` — is never evaluated here, and is drawn as one row by the
/// same path as before. And evaluated once per extraction, not per row: the
/// loop it reaches is the list's content, so a 50,000-element one keeps the
/// windowed path.
///
/// Asked of a `List`'s or a `Section`'s WHOLE content, after the wrappers
/// ``ListRowsPassThrough`` names are off. Beside other rows — `List { Rows();
/// Text("end") }`, or two such views that are each a `Section` — the view
/// arrives through the child walk that reads mixed content, which does not
/// ask, so it is still one row there; SwiftUI draws its rows (measured), and
/// that is a gap of its own.
///
/// An `if` with no `else` around such a view (`if showAll { Rows() }`) is
/// looked through too, when it holds one: an `Optional` renders what it wraps
/// at its own identity, so it takes no step. When it holds nothing it is left
/// alone, to draw nothing — or a departing view's last frames.
@MainActor
func listRowsBody<V: View>(of view: V, context: RenderContext) -> ListRowsBody? {
    // Container first: `as?` takes an `Optional`'s own conformance before it
    // looks inside, so this catches `.some` and `.none` alike.
    if let optional = view as? any ListRowsOptional {
        return optional.listRowsBodyOfWrapped(context: context)
    }
    guard viewTypeHoldsListRowsInBody(V.self) else { return nil }
    return ListRowsBody(
        content: evaluateCompositeBody(of: view, context: context),
        context: context.withChildIdentity(type: V.Body.self))
}

/// Whether a view of type `V` is one the list looks INTO: a view of the app's
/// own — drawn through its `body`, neither `Renderable` nor one of the kinds
/// of content the list reads directly — whose body, as a type, can be list
/// rows.
///
/// Types only, so nothing is built or evaluated to answer. "Can be" because
/// an `if`/`else` counts when either arm could be rows: its live arm is found
/// when the body is evaluated, and an arm that is not rows then draws as one
/// row, as it did before.
///
/// A body that is several views, or a modifier on a loop (`ForEach(…)
/// .padding()`), is not looked through, though SwiftUI would draw those as
/// rows too: the list reads them by flattening them into its child walk, whose
/// rows no `ForEach` owns, and a view of the app's own around them keeps
/// drawing as one row until that walk can see into one.
///
/// A view whose body contains itself, the way a recursive tree view's does,
/// is answered once and then `false` on the way back round, so the walk ends.
@MainActor
func viewTypeHoldsListRowsInBody<V: View>(_ type: V.Type) -> Bool {
    var visited: Set<ObjectIdentifier> = []
    return typeHoldsListRowsInBody(V.self, visited: &visited)
}

/// ``viewTypeHoldsListRowsInBody(_:)``, carrying the views already asked.
@MainActor
private func typeHoldsListRowsInBody<V: View>(
    _ type: V.Type, visited: inout Set<ObjectIdentifier>
) -> Bool {
    guard V.Body.self != Never.self,
        !(V.self is any Renderable.Type),
        !typeIsListRows(V.self),
        !(V.self is any ChildViewProvider.Type),
        !(V.self is any ListRowsPassThrough.Type),
        visited.insert(ObjectIdentifier(V.self)).inserted
    else { return false }
    return typeCanBeListRows(V.Body.self, visited: &visited)
}

/// Whether content of type `V` is list rows the list reads directly, or can
/// be once the wrappers it looks through are off.
@MainActor
private func typeCanBeListRows<V: View>(_ type: V.Type, visited: inout Set<ObjectIdentifier>) -> Bool {
    if typeIsListRows(V.self) { return true }
    if let passThrough = V.self as? any ListRowsPassThrough.Type {
        return passThrough.listRowsContentTypes.contains { typeCanBeListRows($0, visited: &visited) }
    }
    if let optional = V.self as? any ListRowsOptional.Type {
        return typeCanBeListRows(optional.listRowsWrappedType, visited: &visited)
    }
    return typeHoldsListRowsInBody(V.self, visited: &visited)
}

/// A `ForEach`, an `OutlineGroup` or a `Section`: rows the list reads as they
/// are, each with its own ids and, for a loop, its own actions.
@MainActor
private func typeIsListRows<V: View>(_ type: V.Type) -> Bool {
    V.self is any ListRowExtractor.Type || V.self is any SectionRowExtractor.Type
}

/// An `if` with no `else`, seen from a `List`: ``listRowsBody(of:context:)``
/// and the type walk behind it look inside one.
///
/// The rest of the list needs nothing like this, because `as?` looks through
/// an `Optional`'s `some` by itself — but a view of the app's own inside one
/// is not a `ForEach` for `as?` to find, and a TYPE cannot be unwrapped that
/// way at all.
@MainActor
protocol ListRowsOptional {
    /// The type an `.some` holds.
    static var listRowsWrappedType: any View.Type { get }

    /// ``listRowsBody(of:context:)`` of what `.some` holds, at the same
    /// context — an `Optional` renders its content at its own identity — and
    /// `nil` for `.none`.
    func listRowsBodyOfWrapped(context: RenderContext) -> ListRowsBody?
}

extension Optional: ListRowsOptional where Wrapped: View {
    static var listRowsWrappedType: any View.Type { Wrapped.self }

    func listRowsBodyOfWrapped(context: RenderContext) -> ListRowsBody? {
        guard case .some(let wrapped) = self else { return nil }
        return listRowsBody(of: wrapped, context: context)
    }
}
