//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ControlLayoutPaddingTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// Two controls whose stored properties left padding — bytes the per-pass
/// memos' raw-byte key read undefined — declared now so their common shapes
/// have none, and are smaller for it. A generic field can still leave a gap
/// for other type arguments, which the value hash itself must skip.
@MainActor
@Suite("Toggle and ProgressView leave no bytes undefined in their common shapes")
struct ControlLayoutPaddingTests {
    @Test("A Toggle titled with a string: no padding, 208 → 194 bytes")
    func toggle() {
        typealias Titled = Toggle<Text>
        #expect(interiorPadding(of: Titled.self).isEmpty, "\(interiorPadding(of: Titled.self))")
        #expect(MemoryLayout<Titled>.size == 194)
    }

}
