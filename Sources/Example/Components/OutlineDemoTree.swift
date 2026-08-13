//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OutlineDemoTree.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// A file-tree shape for the ``OutlineGroup`` demos: `nil` children is a leaf,
/// an empty array is a folder that happens to be empty (and still discloses).
///
/// Shared by the Containers page (the bare outline) and the Lists page (the
/// same tree as a `List`'s own rows), so the two demos are visibly the same
/// data seen two ways.
struct OutlineDemoNode: Identifiable {
    let id: String
    var children: [Self]?
}

/// A miniature of this package's own layout.
///
/// The names are paths and code identifiers, so they are deliberately not
/// localized — the same call the Containers page makes for "Card" and "Panel".
let outlineDemoTree = [
    OutlineDemoNode(
        id: "Sources",
        children: [
            OutlineDemoNode(
                id: "TUIkitCore",
                children: [
                    OutlineDemoNode(id: "Rendering", children: nil),
                    OutlineDemoNode(id: "Extensions", children: nil),
                ]),
            OutlineDemoNode(
                id: "TUIkit",
                children: [OutlineDemoNode(id: "Views", children: nil)]),
        ]),
    OutlineDemoNode(id: "Tests", children: []),
    OutlineDemoNode(id: "README.md", children: nil),
]
