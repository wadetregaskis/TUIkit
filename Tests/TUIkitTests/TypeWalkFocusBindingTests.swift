//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TypeWalkFocusBindingTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitView

/// `FocusState.Binding` lives above the module the type walk is in, so its
/// conformance to the walk's source-reader marker is pinned here: a row
/// holding one compares equal to a row bound to another focus field.
@Suite("The type walk refuses a focus binding")
struct TypeWalkFocusBindingTests {
    private struct FocusedRow { var title: String; var focus: FocusState<Int?>.Binding }

    @Test("A row holding a FocusState.Binding is refused")
    func focusBindingRefused() {
        var walk = TypeWalk()
        #expect(walk.verdict(for: FocusState<Int?>.Binding.self).refusal != nil)
        #expect(walk.verdict(for: FocusedRow.self).refusal == .readsItsSource(path: "FocusedRow.focus"))
    }
}
