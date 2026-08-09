//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollPosition.swift
//
//  The bindable half of programmatic scrolling: where a ScrollView is, and
//  where you would like it to be. `ScrollViewProxy.scrollTo` is the
//  imperative form of the same machinery — this one is state you can hold.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - ScrollPosition

/// A scroll view's position, readable and writable as state. Matches
/// SwiftUI's type of the same name.
///
/// ```swift
/// @State private var position = ScrollPosition()
///
/// ScrollView {
///     LazyVStack {
///         ForEach(rows) { RowView($0) }
///     }
/// }
/// .scrollPosition($position)
///
/// Button("Top") { position.scrollTo(edge: .top) }
/// Text("Showing: \(position.viewID(type: Row.ID.self).map(String.init(describing:)) ?? "—")")
/// ```
///
/// It works in both directions, and the two are asymmetric on purpose:
/// **writing** asks the scroll view to move (it takes effect on the next
/// frame), **reading** tells you where it ended up — which is not necessarily
/// where you asked, because the user can scroll too.
///
/// > Note: SwiftUI's `point`/`x`/`y` forms take `CGPoint`/`CGFloat`; a terminal
///   scrolls in whole rows, so ``scrollTo(y:)`` takes an `Int` and there is no
///   horizontal component — the seek machinery rides the vertical row-windowing
///   handshake (`ScrollViewProxy` has the same limit, for the same reason).
public struct ScrollPosition: Equatable {

    /// What the position is currently expressed as. One of them at a time, as
    /// in SwiftUI: naming a row and naming an offset are different questions.
    /// Not `Sendable`: an `AnyHashable` is whatever the app's id type is, and
    /// claiming otherwise would be claiming it for them. Nothing here crosses
    /// a thread — a scroll position is read and written on the main actor,
    /// like every other view state.
    enum Target: Equatable {
        case id(AnyHashable, anchor: UnitPoint?)
        case edge(Edge)
        case offset(Int)
    }

    /// The pending or last-applied target.
    var target: Target?

    /// Bumped by every `scrollTo`, so a scroll view can tell a fresh request
    /// from the same request still sitting there. Without it, asking twice for
    /// the same row after scrolling away by hand would be indistinguishable
    /// from not asking at all.
    var requestToken: Int = 0

    /// Whether the position was last changed by the person using the app
    /// rather than by code. Matches SwiftUI's property of the same name.
    public private(set) var isPositionedByUser: Bool = false

    /// Creates an unset position: whatever the scroll view does by default.
    public init() {}

    /// Creates a position that starts by scrolling to `edge`.
    public init(edge: Edge) {
        self.target = .edge(edge)
        self.requestToken = 1
    }

    /// Creates a position that starts at the row identified by `id`.
    public init<ID: Hashable>(id: ID, anchor: UnitPoint? = nil) {
        self.target = .id(AnyHashable(id), anchor: anchor)
        self.requestToken = 1
    }

    /// Creates a position with no target, typed for the id it will report.
    ///
    /// SwiftUI needs the type to decode its own storage; TUIkit does not, and
    /// takes it for source compatibility so a call site written against
    /// SwiftUI compiles unchanged.
    public init<ID: Hashable>(idType: ID.Type) {}
}

// MARK: - Reading

extension ScrollPosition {
    /// The id of the row at the scroll view's anchor, if it is of type `T`.
    ///
    /// `nil` when nothing has been reported yet (the first frame), when the
    /// content has no ids to report (a plain `VStack` rather than a `ForEach`),
    /// or when the id is not a `T`.
    public func viewID<T: Hashable>(type: T.Type) -> T? {
        guard case .id(let value, _) = target else { return nil }
        return value.base as? T
    }

    /// The edge this position was last asked to scroll to, if it was asked for
    /// one.
    public var edge: Edge? {
        guard case .edge(let edge) = target else { return nil }
        return edge
    }
}

// MARK: - Writing

extension ScrollPosition {
    /// Asks the scroll view to bring the row identified by `id` into view.
    ///
    /// - Parameters:
    ///   - id: The row's identity, as `ForEach` derives it.
    ///   - anchor: Where the row lands — `nil` (the default) moves as little
    ///     as possible, and not at all if the row is already visible.
    public mutating func scrollTo<ID: Hashable>(id: ID, anchor: UnitPoint? = nil) {
        target = .id(AnyHashable(id), anchor: anchor)
        requestToken += 1
        isPositionedByUser = false
    }

    /// Asks the scroll view to scroll to one end of its content.
    public mutating func scrollTo(edge: Edge) {
        target = .edge(edge)
        requestToken += 1
        isPositionedByUser = false
    }

    /// Asks the scroll view to scroll to a row offset.
    ///
    /// - Parameter y: The offset in whole rows from the top of the content.
    public mutating func scrollTo(y: Int) {
        target = .offset(y)
        requestToken += 1
        isPositionedByUser = false
    }

    /// Records what the scroll view actually ended up showing.
    ///
    /// Reported by the scroll view, never by the app — which is why it also
    /// sets ``isPositionedByUser``: reaching here means the position came from
    /// the render, not from a `scrollTo`.
    mutating func reportVisible(id: AnyHashable) {
        target = .id(id, anchor: nil)
        isPositionedByUser = true
    }
}

// MARK: - Modifiers

extension View {
    /// Binds a scroll view's position to state you hold. Matches SwiftUI's
    /// `scrollPosition(_:anchor:)`.
    ///
    /// - Parameters:
    ///   - position: The position to read and write.
    ///   - anchor: Which point of the viewport the reported row is sampled at
    ///     — `nil` (the default) means the top.
    public func scrollPosition(
        _ position: Binding<ScrollPosition>, anchor: UnitPoint? = nil
    ) -> some View {
        environment(\.scrollPositionBinding, ScrollPositionBinding(position, anchor: anchor))
    }

    /// Binds the id of the row at a scroll view's anchor. Matches SwiftUI's
    /// `scrollPosition(id:anchor:)`.
    ///
    /// Writing the binding scrolls to that row; the scroll view writes back
    /// the row it is actually showing.
    ///
    /// - Parameters:
    ///   - id: The row identity to read and write.
    ///   - anchor: Which point of the viewport the row is sampled at.
    public func scrollPosition<ID: Hashable>(
        id: Binding<ID?>, anchor: UnitPoint? = nil
    ) -> some View {
        // Bridged onto the same channel rather than given its own: one scroll
        // view reading two mechanisms would need a precedence rule nobody
        // asked for.
        let bridged = Binding<ScrollPosition>(
            get: {
                var position = ScrollPosition()
                if let value = id.wrappedValue {
                    position.target = .id(AnyHashable(value), anchor: anchor)
                    // A plain id binding has no token of its own: the VALUE
                    // changing is the request, which the scroll view detects by
                    // comparing against the row it last reported.
                    position.requestToken = 0
                }
                return position
            },
            set: { newValue in
                let reported = newValue.viewID(type: ID.self)
                if id.wrappedValue != reported { id.wrappedValue = reported }
            })
        return environment(\.scrollPositionBinding, ScrollPositionBinding(bridged, anchor: anchor))
    }
}

// MARK: - Environment

/// The binding plus its anchor, carried to whichever ``ScrollView`` is inside.
///
/// A reference box so the scroll view can also remember what it last reported
/// through this binding — the comparison that keeps a render-time write-back
/// from re-triggering itself every frame.
@MainActor
final class ScrollPositionBinding {
    let binding: Binding<ScrollPosition>
    let anchor: UnitPoint

    /// The last id written back, so an unchanged position writes nothing. A
    /// render pass that wrote every frame would invalidate its own subtree
    /// every frame, and the loop would never settle.
    var lastReportedID: AnyHashable?

    /// The last request token acted on, so a `scrollTo` is applied once rather
    /// than on every frame until the position changes.
    var lastAppliedToken: Int?

    init(_ binding: Binding<ScrollPosition>, anchor: UnitPoint?) {
        self.binding = binding
        self.anchor = anchor ?? .top
    }
}

private struct ScrollPositionBindingKey: EnvironmentKey {
    static let defaultValue: ScrollPositionBinding? = nil
}

extension EnvironmentValues {
    /// The enclosing ``View/scrollPosition(_:anchor:)`` binding, if any.
    var scrollPositionBinding: ScrollPositionBinding? {
        get { self[ScrollPositionBindingKey.self] }
        set { self[ScrollPositionBindingKey.self] = newValue }
    }
}
