//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContainerLayoutPaddingTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitView

/// A value nine bytes long, so whatever follows it is misaligned.
private struct OddContent: View {
    var count = 0
    var flag = false
    var body: some View { EmptyView() }
}

/// The stack cores and the environment modifiers wrap almost everything, and
/// each had padding around its generic content — bytes the per-pass memos'
/// value hash read undefined then (it skips them now, and hashes a type with
/// none as plain words). On Linux CI a lazy stack under a scroll view
/// missed the measure memo from run to run through exactly these: seven bytes
/// after a stack core's one-byte overflow flag, and seven after a
/// `TransformEnvironmentModifier`'s content. The content goes after the
/// word-sized fields now, and a byte-aligned field after the content.
@MainActor
@Suite("The stack cores and environment modifiers leave no bytes undefined around their content")
struct ContainerLayoutPaddingTests {
    typealias Rows = ForEach<Range<Int>, Int, Text>

    @Test("The vertical and horizontal stack cores")
    func stackCores() {
        for type: Any.Type in [
            _VStackCore<Rows>.self, _HStackCore<Rows>.self, _VStackCore<OddContent>.self, _HStackCore<OddContent>.self,
        ] {
            #expect(interiorPadding(of: type).isEmpty, "\(type): \(interiorPadding(of: type))")
        }
    }

    @Test("The environment modifiers, over content of any size and a byte-aligned value")
    func environmentModifiers() {
        for type: Any.Type in [
            TransformEnvironmentModifier<OddContent, ScrollIndicatorVisibility>.self,
            TransformEnvironmentModifier<Text, Bool>.self,
            EnvironmentModifier<OddContent, Bool>.self, EnvironmentModifier<Text, Color>.self,
        ] {
            #expect(interiorPadding(of: type).isEmpty, "\(type): \(interiorPadding(of: type))")
        }
    }
}
