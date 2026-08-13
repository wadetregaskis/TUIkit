//  🖥️ TUIKit — Terminal UI Kit for Swift
//  IdentityKeyTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing

@testable import TUIkitCore

@Suite("identityKey")
struct IdentityKeyTests {

    /// The fast paths must be invisible: the key an element gets is exactly the
    /// key `String(describing:)` produced before, or rows silently change
    /// identity and lose their `@State`, focus and scroll targeting.
    @Test("matches String(describing:) for the types it fast-paths")
    func matchesDescribingForFastPathedTypes() {
        #expect(identityKey(42) == String(describing: 42))
        #expect(identityKey(-7) == String(describing: -7))
        #expect(identityKey(0) == String(describing: 0))
        #expect(identityKey(Int.min) == String(describing: Int.min))
        #expect(identityKey("row") == String(describing: "row"))
        #expect(identityKey("") == String(describing: ""))
        #expect(identityKey("has spaces & (parens)") == String(describing: "has spaces & (parens)"))

        let uuid = UUID(uuidString: "3F2504E0-4F89-41D3-9A0C-0305E82C3301")!
        #expect(identityKey(uuid) == String(describing: uuid))
    }

    /// A dynamic cast looks *through* `Optional` and `AnyHashable`, so a bare
    /// `id as? Int` would re-key every row with an optional id — `"5"` where it
    /// used to be `"Optional(5)"`. The metatype comparison in front of each
    /// cast is what prevents that, and this is the test that would catch its
    /// removal.
    @Test("optionals and AnyHashable are not unwrapped by the fast path")
    func wrappedIdsKeepTheirDescription() {
        let optional: Int? = 5
        #expect(identityKey(optional) == String(describing: optional))
        #expect(identityKey(optional) == "Optional(5)")

        let none: Int? = nil
        #expect(identityKey(none) == String(describing: none))

        let optionalString: String? = "row"
        #expect(identityKey(optionalString) == String(describing: optionalString))
        #expect(identityKey(optionalString) == "Optional(\"row\")")

        let erased = AnyHashable(5)
        #expect(identityKey(erased) == String(describing: erased))
    }

    @Test("types with no fast path fall through unchanged")
    func otherTypesFallThrough() {
        enum Kind: String { case alpha, beta }
        struct Composite: Hashable {
            let section: Int
            let row: Int
        }

        #expect(identityKey(Kind.alpha) == String(describing: Kind.alpha))
        #expect(identityKey(Composite(section: 1, row: 2))
            == String(describing: Composite(section: 1, row: 2)))
        #expect(identityKey(UInt8(200)) == String(describing: UInt8(200)))
        #expect(identityKey(3.5) == String(describing: 3.5))
        #expect(identityKey(true) == String(describing: true))
        #expect(identityKey(Character("x")) == String(describing: Character("x")))
    }

    /// Distinct elements must land on distinct keys — the property `ForEach`
    /// row identity depends on.
    @Test("distinct ids give distinct keys")
    func distinctIdsAreDistinct() {
        let keys = (0..<500).map { identityKey($0) }
        #expect(Set(keys).count == keys.count)
    }
}
