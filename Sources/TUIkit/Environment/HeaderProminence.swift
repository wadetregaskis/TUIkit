//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HeaderProminence.swift
//
//  How much a `Section` header should stand out.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling
import TUIkitView

/// How prominent a section header is — mirrors SwiftUI's `Prominence`.
public enum Prominence: Sendable, Hashable {
    /// The ordinary treatment.
    case standard
    /// More emphatic than standard.
    case increased
}

/// Environment key for ``View/headerProminence(_:)``.
private struct HeaderProminenceKey: EnvironmentKey {
    static let defaultValue: Prominence = .standard
}

extension EnvironmentValues {
    /// The prominence section headers in this subtree render with.
    ///
    /// Read by `Text` when it is drawing a ``ChromeRole/sectionHeader``.
    public var headerProminence: Prominence {
        get { self[HeaderProminenceKey.self] }
        set { self[HeaderProminenceKey.self] = newValue }
    }
}

extension Prominence {
    /// The header's baseline attributes at this prominence.
    ///
    /// A terminal cannot make a header BIGGER, which is what SwiftUI's
    /// `.increased` mostly does. What it has instead is intensity, and the
    /// standard header already spends bold — so the difference is the **dim**:
    /// a standard header is bold-but-dim (present, clearly subordinate to the
    /// rows it labels), an increased one is bold at full strength.
    ///
    /// Deliberately not adding a second attribute (underline, say) on top:
    /// TUIkit's headers are separated by position and case already, and a
    /// header that changed *shape* between prominences would re-measure.
    func headerAttributes(over base: StyleAttributes) -> StyleAttributes {
        guard self == .increased else { return base }
        var raised = base
        raised.dim = false
        return raised
    }
}

extension View {
    /// Sets how prominent section headers are in this view.
    ///
    /// Mirrors SwiftUI's `headerProminence(_:)`. Apply it to a `Section`, or to
    /// anything containing several:
    ///
    /// ```swift
    /// List {
    ///     Section("Today") { … }
    ///         .headerProminence(.increased)
    ///     Section("Earlier") { … }
    /// }
    /// ```
    ///
    /// SwiftUI's `.increased` mostly makes the header bigger; a terminal cell
    /// grid has one size, so what it raises here is INTENSITY — a standard
    /// header is bold and dim, an increased one is bold at full strength. It
    /// changes no glyph and no width, so raising a header cannot reflow the
    /// list around it.
    ///
    /// - Parameter prominence: The prominence to apply.
    public func headerProminence(_ prominence: Prominence) -> some View {
        environment(\.headerProminence, prominence)
    }
}
