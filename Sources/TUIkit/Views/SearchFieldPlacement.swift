//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SearchFieldPlacement.swift
//
//  Created by LAYERED.work
//  License: MIT

/// The placement of a search field in a view hierarchy. Mirrors SwiftUI's
/// `SearchFieldPlacement`.
///
/// A terminal has no navigation toolbar or sidebar chrome to host a search
/// field, so every placement collapses to "the top of the searchable subtree".
/// The cases exist for source compatibility; the value is otherwise inert.
public struct SearchFieldPlacement: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case automatic
        case toolbar
        case sidebar
        case navigationBarDrawer
    }

    let kind: Kind

    public static let automatic = Self(kind: .automatic)
    public static let toolbar = Self(kind: .toolbar)
    public static let sidebar = Self(kind: .sidebar)
    public static let navigationBarDrawer = Self(kind: .navigationBarDrawer)
}
