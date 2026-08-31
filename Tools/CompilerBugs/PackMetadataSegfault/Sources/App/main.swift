import Foundation
import GlueMod
import ProtoMod
import TypeMod

func note(_ text: String) {
    FileHandle.standardError.write((text + "\n").data(using: .utf8)!)
}

// ONE CASE PER FUNCTION, and it matters: the metadata for every type a function
// mentions is instantiated on ENTRY, so a single function holding all of these
// would crash whichever case you asked it for.

/// The crash. A pack of [a third-module conformance, an opaque type].
@inline(never) func crashes() { _ = Pack(Thing(), opaque()) }

/// The second element is NAMED rather than opaque.
@inline(never) func namedSecondElement() { _ = Pack(Thing(), Leaf()) }

/// The conforming type is owned by the module that conforms it.
@inline(never) func conformedInItsOwnModule() { _ = Pack(GlueLeaf(), opaque()) }

/// …or by the protocol's module. (This is the shape the workaround uses.)
@inline(never) func conformedInTheProtocolsModule() { _ = Pack(Native(), opaque()) }

/// The aggregate does not STORE the pack.
@inline(never) func aggregateStoresNothing() { _ = EmptyPack(Thing(), opaque()) }

/// Not a pack at all: an ordinary two-parameter generic.
struct Two<A: P, B: P> {
    let a: A
    let b: B
}
@inline(never) func notAPack() { _ = Two(a: Thing(), b: opaque()) }

let cases: [(name: String, run: () -> Void)] = [
    ("crashes", crashes),
    ("named-second-element", namedSecondElement),
    ("conformed-in-its-own-module", conformedInItsOwnModule),
    ("conformed-in-the-protocols-module", conformedInTheProtocolsModule),
    ("aggregate-stores-nothing", aggregateStoresNothing),
    ("not-a-pack", notAPack),
]

let wanted = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "crashes"
guard let match = cases.first(where: { $0.name == wanted }) else {
    note("unknown case: " + wanted)
    note("cases: " + cases.map(\.name).joined(separator: " "))
    exit(2)
}
note(match.name + ": building the pack")
match.run()
note(match.name + ": ok")
