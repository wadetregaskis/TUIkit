//  🖥️ TUIKit — Terminal UI Kit for Swift
//  UnitPoint.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - UnitPoint

/// A normalized point in a view's coordinate space, matching SwiftUI's
/// `UnitPoint`: `(0, 0)` is the top-leading corner, `(1, 1)` the
/// bottom-trailing one.
///
/// Used by ``TUIkit/View/defaultScrollAnchor(_:)`` to express where a scroll
/// view initially positions — and keeps — its content: `.bottom` is the
/// log-viewer follow mode.
public struct UnitPoint: Hashable, Sendable {
    /// The normalized horizontal position (0 = leading, 1 = trailing).
    public var x: Double

    /// The normalized vertical position (0 = top, 1 = bottom).
    public var y: Double

    /// Creates a unit point.
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Self(x: 0, y: 0)
    public static let center = Self(x: 0.5, y: 0.5)
    public static let leading = Self(x: 0, y: 0.5)
    public static let trailing = Self(x: 1, y: 0.5)
    public static let top = Self(x: 0.5, y: 0)
    public static let bottom = Self(x: 0.5, y: 1)
    public static let topLeading = Self(x: 0, y: 0)
    public static let topTrailing = Self(x: 1, y: 0)
    public static let bottomLeading = Self(x: 0, y: 1)
    public static let bottomTrailing = Self(x: 1, y: 1)
}

// MARK: - From an Alignment

extension Alignment {
    /// This alignment as the anchor point ``LayoutSubview/place(in:anchor:proposal:)``
    /// wants.
    ///
    /// The two spell the same idea — "put it against that edge" — in the two
    /// vocabularies the layout system uses: `Alignment` names edges, placement
    /// takes fractions. Custom alignment guides collapse to the nearest of the
    /// three standard positions, because an anchor is a fraction of the
    /// subview's own size and a guide is an offset within it: there is no
    /// fraction that means "wherever this view said its first baseline was".
    var unitPoint: UnitPoint {
        let x: Double =
            switch horizontal {
            case .leading: 0
            case .trailing: 1
            default: 0.5
            }
        let y: Double =
            switch vertical {
            case .top: 0
            case .bottom: 1
            default: 0.5
            }
        return UnitPoint(x: x, y: y)
    }
}

// MARK: - Default Scroll Anchor

/// Which of a scroll view's anchoring questions an anchor answers — SwiftUI's
/// `ScrollAnchorRole`, taken by ``TUIkit/View/defaultScrollAnchor(_:for:)``.
///
/// "Anchor" names more than one thing, and the unlabelled
/// ``TUIkit/View/defaultScrollAnchor(_:)`` answers two of them at once:
/// **where the view opens**, and **what it holds onto as its content changes**.
/// The role picks one.
///
/// > Note: SwiftUI's third role, `alignment` — where content sits when it is
/// > *smaller* than the viewport — is **not offered yet**, and deliberately not
/// > as an inert case: a spelling that compiles and does nothing is worse than
/// > one that does not compile. It is deferred rather than refused, because a
/// > cell grid can perfectly well align short content; what it needs is a
/// > content-placement offset in the render path plus every consumer that maps
/// > a screen row back to a data row — hit testing, click-to-select, drop
/// > slots, focus reveal — taught about that offset. That is a scroll-anchoring
/// > feature in its own right, not a spelling.
public struct ScrollAnchorRole: Hashable, Sendable {
    private let rawValue: String

    private init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// Where the view is scrolled to on the frame it first renders.
    ///
    /// `.bottom` here is "open at the tail, then leave me alone" — a log you
    /// want to join at the end but then read backwards through without it
    /// snatching the view away on every append.
    public static let initialOffset = Self("initialOffset")

    /// What the view holds onto when its CONTENT changes size under it.
    ///
    /// `.bottom` here is follow-the-log: while the view sits at the tail,
    /// arriving rows keep it there.
    public static let sizeChanges = Self("sizeChanges")
}

private struct DefaultScrollAnchorKey: EnvironmentKey {
    static let defaultValue: UnitPoint? = nil
}

private struct InitialScrollAnchorKey: EnvironmentKey {
    static let defaultValue: UnitPoint?? = nil
}

extension EnvironmentValues {
    /// The anchor a scrollable holds as its content changes size — the
    /// ``ScrollAnchorRole/sizeChanges`` role. See
    /// ``TUIkit/View/defaultScrollAnchor(_:)``.
    public var defaultScrollAnchor: UnitPoint? {
        get { self[DefaultScrollAnchorKey.self] }
        set { self[DefaultScrollAnchorKey.self] = newValue }
    }

    /// The anchor a scrollable opens at — the
    /// ``ScrollAnchorRole/initialOffset`` role — **if one was stated**.
    ///
    /// Doubly optional, for the same reason `Text`'s stated font is: `nil` is a
    /// legal value of this key ("open unanchored"), so "nobody said" needs to
    /// be a distinguishable third state. It buys two things. An unstated
    /// opening role defers to the standing anchor, which is what keeps a direct
    /// write of the public ``defaultScrollAnchor`` — the spelling that predates
    /// the roles — meaning exactly what it always did. And it lets the role
    /// modifiers COMPOSE in either order, because
    /// ``TUIkit/View/defaultScrollAnchor(_:for:)`` transforms this key rather
    /// than assigning it: a `.sizeChanges` call states "no opening anchor" only
    /// where none was stated already, so an `.initialOffset` call anywhere else
    /// in the chain survives it.
    ///
    /// Internal: SwiftUI exposes no `EnvironmentValues` member for either role,
    /// and ``defaultScrollAnchor`` is public only because it predates the split
    /// and the scrollables read it from outside this file.
    var initialScrollAnchor: UnitPoint?? {
        get { self[InitialScrollAnchorKey.self] }
        set { self[InitialScrollAnchorKey.self] = newValue }
    }

    /// Both declared anchor modes, resolved — what a scrollable captures each
    /// render. One value because the two are only ever meaningful together:
    /// `opening` is `nil` when no opening role was stated, and reading it
    /// without `standing` to defer to would lose that.
    var declaredAnchorModes: (standing: ScrollAnchorMode, opening: ScrollAnchorMode?) {
        (
            ScrollAnchorMode.resolved(defaultScrollAnchor: defaultScrollAnchor),
            initialScrollAnchor.map(ScrollAnchorMode.resolved(defaultScrollAnchor:))
        )
    }
}

extension View {
    /// Associates an anchor with scroll views within this view, controlling
    /// where their content is initially positioned **and** what they hold onto
    /// as the content changes. Matches SwiftUI's modifier of the same name,
    /// which likewise sets both roles at once — see
    /// ``defaultScrollAnchor(_:for:)`` to set one.
    ///
    /// `.bottom` (a `y` of 0.75 or more) is the terminal's log-viewer idiom:
    /// the view opens at the tail, and while it is *at* the bottom, growing
    /// content keeps it glued there; scrolling up releases the glue (appends no
    /// longer move the view); scrolling back to the bottom — End, or any scroll
    /// that lands there — re-engages it. Engagement is **positional** — being
    /// at the tail *is* the follow — so there is no stored flag to fall out of
    /// step, and the opening placement is that rule's own first frame rather
    /// than a second mechanism.
    ///
    /// Two deviations from SwiftUI, both a consequence of scrolling in whole
    /// rows rather than points:
    /// - The anchor **quantises to three edges**: `y ≥ 0.75` is the bottom,
    ///   `y ≤ 0.25` the top, and anything mid-content anchors *nothing* (the
    ///   position simply stays where it is in line coordinates). SwiftUI's
    ///   `.center` keeps the centre fixed; here it means "no anchor".
    /// - `x` is ignored. Horizontal scrolling exists, but the anchor modes are
    ///   defined over rows.
    ///
    /// - Parameter anchor: The unit point to anchor content to, or `nil`
    ///   for the default (no anchor — the top).
    public func defaultScrollAnchor(_ anchor: UnitPoint?) -> some View {
        // Both roles, stated — SwiftUI's unlabelled form does the same, and
        // stating the opening one is what lets a plain call nearer the view
        // override a role-specific one further out.
        environment(\.defaultScrollAnchor, anchor)
            .environment(\.initialScrollAnchor, .some(anchor))
    }

    /// Associates an anchor with scroll views within this view for **one** of
    /// the questions an anchor answers. Matches SwiftUI's modifier of the same
    /// name.
    ///
    /// The unlabelled ``defaultScrollAnchor(_:)`` sets both roles together,
    /// which is what a log viewer wants: open at the tail *and* follow it. The
    /// roles come apart when you want one without the other:
    ///
    /// ```swift
    /// // Join the log at the end, then read backwards undisturbed.
    /// List(entries) { … }.defaultScrollAnchor(.bottom, for: .initialOffset)
    ///
    /// // Start at the beginning, but follow the tail once you reach it.
    /// List(entries) { … }.defaultScrollAnchor(.bottom, for: .sizeChanges)
    /// ```
    ///
    /// Writing one role leaves the other unanchored. Writing both separately is
    /// the same as writing the unlabelled form.
    ///
    /// The same two deviations apply as for ``defaultScrollAnchor(_:)`` — the
    /// three-edge quantisation, and `x` being ignored.
    ///
    /// - Parameters:
    ///   - anchor: The unit point to anchor content to, or `nil` for none.
    ///   - role: Which question this anchor answers.
    public func defaultScrollAnchor(
        _ anchor: UnitPoint?, for role: ScrollAnchorRole
    ) -> some View {
        // `.sizeChanges` has to say something about the OPENING role too, and
        // this is why it transforms rather than assigns. An unstated opening
        // role defers to the standing one, so a bare `.bottom, for: .sizeChanges`
        // would still open at the tail — the deferral is exactly what this call
        // opts out of. But it must not stamp on an `.initialOffset` stated
        // elsewhere in the chain, and the environment resolves inside-out, so
        // "state none only if none was stated" is the one rule that composes in
        // either order.
        transformEnvironment(\.initialScrollAnchor) { stated in
            switch role {
            case .initialOffset: stated = .some(anchor)
            default: stated = stated ?? .some(nil)
            }
        }
        .transformEnvironment(\.defaultScrollAnchor) { standing in
            if role == .sizeChanges { standing = anchor }
        }
    }
}
