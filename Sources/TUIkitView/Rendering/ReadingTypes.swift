//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReadingTypes.swift
//
//  Which view types' bodies read an `@Observable`.
//
//  A body evaluated to DRAW a view is always observed: `withObservationTracking`
//  around it costs a thread-local swap when the body reads nothing, and arms a
//  registration only when it reads something. A body evaluated to MEASURE a
//  view was never observed, which kept that swap off the measure path — and
//  left every result kept from a measure unwatched: a hugging `List`'s width, a
//  `ViewThatFits`'s choice under an `.equatable()`, a size in the cross-frame
//  table. Such a result was right only while some DRAW of the same reader had
//  armed a registration that happened to cover the same reads.
//
//  So the cache learns, per type, which bodies read: the first time a body of
//  a type arms a registration while drawn, the type is known to read, and from
//  then on its measured bodies are observed too. A type that reads nothing
//  costs the measure path a load and a test of one word; a type that reads
//  pays for observation exactly where it reads.
//
//  Created by Wade Tregaskis
//  License: MIT

/// The view types whose bodies have armed an observation registration under
/// one render cache.
///
/// Per TYPE, not per identity: a new row of a known type is observed from its
/// first measure, and the set is bounded by the types an app declares rather
/// than by the rows it has drawn.
///
/// Main actor only, like the render walk that asks and teaches it: it is
/// taught from a scope's `onChange` autoclosure, which `withObservationTracking`
/// evaluates on the walk's own thread as the scope closes.
package final class ReadingTypes {
    /// One bit per type known, at a hash of its metadata pointer: a type not
    /// known is told so by one load and one test, almost always, and only a
    /// set bit is confirmed in `types`. Zero until a type is learned.
    private var filter: UInt64 = 0
    private var types = Set<ObjectIdentifier>()

    package init() {}

    /// How many types are known to read.
    package var count: Int { types.count }

    /// Whether no type is known to read.
    package var isEmpty: Bool { types.isEmpty }

    /// Whether a body of `type` has armed a registration under this cache.
    @inline(__always)
    package func contains(_ type: Any.Type) -> Bool {
        let id = ObjectIdentifier(type)
        guard filter & Self.bit(id) != 0 else { return false }
        return types.contains(id)
    }

    /// Records that a body of `type` armed a registration. `true` when it was
    /// not known before.
    package func learn(_ type: Any.Type) -> Bool {
        let id = ObjectIdentifier(type)
        guard types.insert(id).inserted else { return false }
        filter |= Self.bit(id)
        return true
    }

    /// The filter's bit for a type: metadata pointers are 16-byte aligned, so
    /// the low bits are dropped and two windows of the rest mixed.
    @inline(__always)
    private static func bit(_ id: ObjectIdentifier) -> UInt64 {
        let address = UInt(bitPattern: id)
        return 1 << UInt64(truncatingIfNeeded: ((address >> 4) ^ (address >> 10)) & 63)
    }
}
