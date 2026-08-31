import ProtoMod
import TypeMod

/// THE CONFORMANCE UNDER TEST. `Thing` is TypeMod's and `P` is ProtoMod's, so
/// this module owns neither of them.
extension Thing: P {}

/// A type owned here and conformed here — the ordinary case, for contrast.
public struct GlueLeaf: P {
    public init() {}
}
