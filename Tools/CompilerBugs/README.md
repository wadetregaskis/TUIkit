# Compiler bugs TUIkit has hit

Two Swift bugs the framework works around. Each has a self-contained repro here
so the workaround can be checked against a new toolchain and deleted the moment
it stops being needed — and so they can be reported upstream without anyone
having to build TUIkit.

Both were found in August 2026. Toolchains: **Apple Swift 6.2.4**
(`swiftlang-6.2.4.1.4`, Xcode) and the **6.5-dev snapshot of 2026-08-30**
(`swift-DEVELOPMENT-SNAPSHOT-2026-08-30-a`, which is built `+assertions`).

---

## 1. `PackMetadataSegfault` — a pack segfaults on a third-module conformance

```
cd PackMetadataSegfault && ./run.sh
```

```
crashes                             SIGSEGV
named-second-element                ok
conformed-in-its-own-module         ok
conformed-in-the-protocols-module   ok
aggregate-stores-nothing            ok
not-a-pack                          ok
```

Building `Pack(Thing(), opaque())` segfaults — `EXC_BAD_ACCESS` at
`0xfffffffffffffff8`, in compiler-generated code, before the first statement of
the enclosing function runs. It is metadata instantiation for the pack, not
anything the program does with it.

Three ingredients, all necessary:

1. **A struct that STORES a parameter pack.** `Pack<each V: P>` with
   `let children: (repeat each V)`. It does not need to conform to anything;
   an otherwise identical `EmptyPack` that stores nothing is fine, and an
   ordinary two-parameter generic is fine.
2. **One element whose conformance is declared in a module that owns neither
   the type nor the protocol.** `Thing` is TypeMod's, `P` is ProtoMod's, and
   `extension Thing: P` is GlueMod's. Conform it in either owning module
   instead and it goes away.
3. **Another element that is an opaque type** (`some P`). A named type in the
   same position is fine, and the opaque type's underlying type does not need
   to be generic.

**Debug only.** `./run.sh release` passes everything.

The protocol needs no requirements at all — `protocol P {}` is enough — so this
is not about associated types, `Never` conformances, actor isolation, result
builders or anything else the SwiftUI-shaped original suggested.

**Where TUIkit hit it:** `Color: View`. `Color` is `TUIkitStyling`'s, `View` is
`TUIkitView`'s, and the conformance was written in the umbrella module —
ingredient 2. `TupleView` is ingredient 1, and every `@ViewBuilder` block
containing `Color.red` beside something like `Text("hi").frame(width: 4)` (whose
return type is opaque) is ingredient 3. **Workaround:** the conformance now
lives in `TUIkitView`, which is why that module depends on `TUIkitStyling` — see
`Sources/TUIkitView/Core/ColorAsView.swift`.

---

## 2. `LoadableByAddressAssertion` — a tuple in an `Optional` stored property

```
cd LoadableByAddressAssertion && ./variants.sh /path/to/swift-DEVELOPMENT-SNAPSHOT.xctoolchain
```

```
3-word field, 5-word closure arg        ASSERTS
2-word field (tuple not large)          ok
4-word closure arg (arg not large)      ok
unlabelled tuple                        ASSERTS
not Optional                            ok
no closure in the tuple                 ok
a struct instead of a tuple             ok
```

`Crash.swift` is twelve lines and stops the compiler:

```
Assertion failed: (srcType == tgtType && "Source and target type do not match"),
function rewriteFunction, file LoadableByAddress.cpp, line 2445.
```

The **declaration alone** is enough — nothing has to assign to the property. It
is the synthesized setter the pass chokes on.

Both halves have to be "large loadable" (over four words), and each for its own
reason:

- the **tuple** must be large, so the pass rewrites it — three words of struct
  plus a two-word thick function is five;
- the **closure's parameter** must be large, so the *function type* is itself
  rewritten to take it indirectly — five words does it, four does not.

Then `rewriteFunction` compares the rewritten type against the original and
they disagree. Labels make no difference. Dropping the `Optional`, the closure,
or the tuple (a struct with the same two fields) all avoid it.

**Assertions-enabled compilers only.** The shipped 6.2.4 compiles all seven
variants without complaint; the dev snapshot asserts on two. So the bug is
invisible on release toolchains, and stops the nightly lanes dead.

**Where TUIkit hit it:** `MouseEventDispatcher.pendingHoverExit` was
`(region: HitTestRegion, handler: (MouseEvent) -> Bool)?` — `HitTestRegion` is
well over three words and `MouseEvent` is eight, so both thresholds were met.
**Workaround:** a named struct instead of the tuple, which the matrix above
shows is exactly the shape that does not assert.
