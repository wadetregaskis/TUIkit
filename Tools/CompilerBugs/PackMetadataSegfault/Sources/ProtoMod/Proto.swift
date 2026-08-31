/// A marker protocol. It needs no requirements at all.
public protocol P {}

/// The aggregate: it STORES a parameter pack. (SwiftUI's `TupleView` and
/// TUIkit's are this shape.) It does not need to conform to `P` itself.
public struct Pack<each V: P> {
    public let children: (repeat each V)
    public init(_ values: repeat each V) { self.children = (repeat each values) }
}

/// The same, but storing nothing — for the "does the pack have to be stored?"
/// case.
public struct EmptyPack<each V: P> {
    public init(_ values: repeat each V) {}
}

public struct Leaf: P {
    public init() {}
}

/// A type owned by this module and conformed by this module.
public struct Native: P {
    public init() {}
}

/// Returns an OPAQUE type. Its underlying type is not generic, and does not
/// need to be.
public func opaque() -> some P { Leaf() }
