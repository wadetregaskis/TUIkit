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

// MARK: - Default Scroll Anchor

private struct DefaultScrollAnchorKey: EnvironmentKey {
    static let defaultValue: UnitPoint? = nil
}

extension EnvironmentValues {
    /// The anchor a ``ScrollView`` uses for its initial content position —
    /// and, for `.bottom`, its follow behaviour. See
    /// ``TUIkit/View/defaultScrollAnchor(_:)``.
    public var defaultScrollAnchor: UnitPoint? {
        get { self[DefaultScrollAnchorKey.self] }
        set { self[DefaultScrollAnchorKey.self] = newValue }
    }
}

extension View {
    /// Associates an anchor with scroll views within this view, controlling
    /// where their content is initially positioned. Matches SwiftUI's
    /// modifier of the same name.
    ///
    /// `.bottom` (a `y` of 0.75 or more) additionally enables **follow
    /// mode**, the terminal's log-viewer idiom: while the view is at the
    /// bottom, growing content keeps it glued to the tail; scrolling up
    /// releases the glue (appends no longer move the view); scrolling back
    /// to the bottom — End, or any scroll that lands there — re-engages it.
    ///
    /// Vertical only: the terminal scroll model has no horizontal row
    /// concept, so `x` is currently ignored.
    ///
    /// - Parameter anchor: The unit point to anchor content to, or `nil`
    ///   for the default (top).
    public func defaultScrollAnchor(_ anchor: UnitPoint?) -> some View {
        environment(\.defaultScrollAnchor, anchor)
    }
}
