# Compiler bugs TUIkit has hit

Five Swift bugs the framework works around. Each has a self-contained repro here
so the workaround can be checked against a new toolchain and deleted the moment
it stops being needed — and so they can be reported upstream without anyone
having to build TUIkit.

The first two were found in August 2026. Toolchains: **Apple Swift 6.2.4**
(`swiftlang-6.2.4.1.4`, Xcode) and the **6.5-dev snapshot of 2026-08-30**
(`swift-DEVELOPMENT-SNAPSHOT-2026-08-30-a`, which is built `+assertions`).
The third, fourth and fifth were found in September 2026, on swift.org's **Swift
6.2.4** (`swift-6.2.4-RELEASE`, which is also built `+assertions`, and is what
swiftly installs).

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

---

## 3. `PackPreconcurrencyConformance` — `@preconcurrency` on a type with a parameter pack

```
tcs=~/Library/Developer/Toolchains
cd PackPreconcurrencyConformance && ./variants.sh "$tcs/swift-6.2.4-RELEASE.xctoolchain" \
    /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain \
    "$tcs/swift-6.3.3-RELEASE.xctoolchain" \
    "$tcs/swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-09-10-a.xctoolchain"
```

```
                                                6.2.4 +a      Xcode 6.2.4   6.3.3         6.4.2-dev +a
Crash.swift: actor, pack, @preconcurrency       ABORTS        ok            ok            ok
struct, @MainActor witness                      ABORTS        ok            ok            ok
@MainActor struct storing a pack, Equatable     ABORTS        ok            ok            ok
stdlib protocol, property requirement           ABORTS        ok            ok            ok
pack on an enclosing type                       ABORTS        ok            ok            ok
no pack: actor Holder<Element>                  ok            ok            ok            ok
no pack: struct, @MainActor witness             ok            ok            ok            ok
requirement async                               ok            ok            ok            ok
witness nonisolated                             ok            ok            ok            ok
isolated conformance, @MainActor Equatable      ok            ok            ok            ok
```

`+a` marks a compiler built with assertions. Each variant is compiled with
`-emit-silgen -Xfrontend -sil-verify-all`, so a column would say `BAD SIL` if the
verifier rejected what SILGen emitted. None does.

`Crash.swift` is two declarations, and the compiler stops while it emits the
protocol witness thunk for `run()`:

```swift
protocol Runner {
    func run()
}

actor Holder<each Element>: @preconcurrency Runner {
    func run() {}
}
```

```
Assertion failed: (isPreconcurrency), function emitProtocolWitness,
file SILGenPoly.cpp, line 7521.
```

Declaring the conformance is enough. Three things are needed:

1. **A type parameter pack on the conforming type**, or on a type that encloses
   it. Nothing has to be stored in it. An ordinary generic parameter instead is
   fine.
2. **A `@preconcurrency` conformance.** The isolated spelling (SE-0470),
   `@MainActor Equatable`, is fine.
3. **An actor-isolated witness for a synchronous requirement:** a method of an
   actor, or one isolated to a global actor such as `@MainActor`. An `async`
   requirement, or a `nonisolated` witness, is fine.

The protocol is nonisolated, and it can be the standard library's
(`CustomStringConvertible`, whose requirement is a property).

**Corrected on 2026-09-14.** This section used to say that the protocol had to
be main-actor isolated and that the pack had to be stored, with a matrix from the
old `variants.sh`. Neither is needed. The old variant that dropped the protocol's
isolation also dropped `@preconcurrency` and left `==` nonisolated, so it took
away the second and third things too.

### Affected versions

Observed on macOS (arm64) on 2026-09-14, with `Crash.swift` and the variants
above:

| Toolchain | Build config | `Crash.swift` |
|---|---|---|
| swift.org 6.2.4 (`swift-6.2.4-RELEASE`) | +assertions | aborts |
| Xcode 26.3's 6.2.4 (`swiftlang-6.2.4.1.4`) | no assertions | compiles |
| swift.org 6.3.3 (`swift-6.3.3-RELEASE`) | no assertions | compiles |
| swift.org 6.4 snapshot of 2026-09-10 (`6.4.2-dev`) | +assertions | compiles |

Only a build with assertions can abort here, so the clean compiles on Xcode's
6.2.4 and on 6.3.3 do not show the bug is absent from them. The 6.4 snapshot is
the only assertions build that compiles it. A separate runtime check found no
sign of wrong code on the three compilers that do not abort: a pack type's
witness thunk gets the same executor check as an ordinary generic type's, and
traps off its actor in Swift 6 mode the same way.

**Upstream.** No issue for this abort was found. The likely fix is
<https://github.com/swiftlang/swift/pull/83004> ("AST: Change
RequirementEnvironment::getRequirementToWitnessThunkSubs() to use contextual
types", merged to `main` in July 2025). It makes `SILGenModule::emitProtocolWitness`
read `isPreconcurrency` from the root conformance, which a pack type's
specialized conformance would otherwise hide. It is in `release/6.3` and
`swift-6.3.3-RELEASE`, not in `release/6.2` or `swift-6.2.4-RELEASE`, and no
cherry-pick to 6.2 was found. That it is the fix is not confirmed: nobody has
built it on its own.

**Where TUIkit hit it:** `TupleView: @preconcurrency Equatable`, spelled like
every other view's conformance. `TupleView<each V>` has the pack, and its `==`
is main-actor isolated because `View` is. `swift build` with swift.org's 6.2.4
aborted in `TUIkitView`, natively on macOS as well as in the Linux static-SDK
and WebAssembly builds that first showed it. **Workaround:** `extension
TupleView: @MainActor Equatable`, the isolated conformance in the table's last
row. See `Sources/TUIkitView/Core/TupleViews.swift`. No other view has a pack,
so the rest keep `@preconcurrency`. The workaround is needed for as long as
swift.org's 6.2 builds are supported.

---

## 4. `GenericOpaqueResultConversion` — converting a function with an opaque result, in a generic context

```
tcs=~/Library/Developer/Toolchains
cd GenericOpaqueResultConversion && ./variants.sh "$tcs/swift-6.2.4-RELEASE.xctoolchain" \
    /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain \
    "$tcs/swift-6.3.3-RELEASE.xctoolchain" \
    "$tcs/swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-09-10-a.xctoolchain"
```

```
                                                6.2.4 +a      Xcode 6.2.4   6.3.3         6.4.2-dev +a
Crash.swift: zero as () -> Any                  ABORTS        ok            ok            ok
zero returns Int, not some Any                  ok            ok            ok            ok
enclosing function not generic                  ok            ok            ok            ok
underlying type uses Element                    ok            ok            ok            ok
no conversion: a direct call                    ok            ok            ok            ok
conversion by annotation                        ABORTS        ok            ok            ok
wrapped in a closure instead                    ok            ok            ok            ok
methods of a generic struct                     ABORTS        ok            ok            ok
a destructuring closure instead                 ABORTS        ok            ok            ok
one closure parameter, not destructured         ok            ok            ok            ok
destructuring, zero generic at top level        ABORTS        ok            ok            ok
destructuring, zero outside generic context     ok            ok            ok            ok
the old repro: generic type, destructuring      ABORTS        ok            ok            ok
```

`+a` marks a compiler built with assertions. Each variant is compiled with
`-emit-silgen -Xfrontend -sil-verify-all`, so a column would say `BAD SIL` if the
verifier rejected what SILGen emitted. None does.

`Crash.swift` is one generic function, and the compiler stops while it builds
the reabstraction thunk for the conversion:

```swift
func convert<Element>(_: Element) {
    func zero() -> some Any { 0 }
    _ = zero as () -> Any
}
```

```
Assertion failed: (!type->hasTypeParameter() && "no generic environment
provided for type with type parameters"), function mapTypeIntoContext,
file GenericEnvironment.cpp, line 337.
```

Three things are needed:

1. **A function conversion that needs a reabstraction thunk:** `zero as () ->
   Any`, or `let _: () -> Any = zero`. A direct call, or `{ zero() } as () ->
   Any`, which wraps the call in a closure instead, is fine.
2. **A generic context:** a generic function, or a method of a generic type.
   The same code in a function that is not generic is fine.
3. **An opaque result type that belongs to that context**, declared in it or on
   a function that is itself generic, **whose underlying type does not use the
   generic parameters.** `zero` returning `Int`, or `some Any` over `[Element]`,
   is fine, and so is a `zero` declared outside the generic context.

The thunk's formal type then depends on the generic signature, while its lowered
type does not.

A closure that destructures its tuple parameter, `{ _, _ in zero() }`, is one
way to get the conversion. The type checker wraps the two-parameter closure in
an implicit conversion to a function of one tuple parameter. A closure with one
parameter needs no conversion.

**Corrected on 2026-09-14.** This section used to say that a destructuring
closure and a generic *type* are needed, and that a generic free function is
fine. Neither a closure nor a type is needed, and a generic free function aborts
too. The old free-function variant had also moved the opaque-result helper out
of the generic context, which took away the third thing: the table's "zero
outside generic context" row.

### Affected versions

Observed on macOS (arm64) on 2026-09-14, with `Crash.swift` and the variants
above:

| Toolchain | Build config | `Crash.swift` |
|---|---|---|
| swift.org 6.2.4 (`swift-6.2.4-RELEASE`) | +assertions | aborts |
| Xcode 26.3's 6.2.4 (`swiftlang-6.2.4.1.4`) | no assertions | compiles |
| swift.org 6.3.3 (`swift-6.3.3-RELEASE`) | no assertions | compiles |
| swift.org 6.4 snapshot of 2026-09-10 (`6.4.2-dev`) | +assertions | compiles |

Only a build with assertions can abort here, so the clean compiles on Xcode's
6.2.4 and on 6.3.3 do not show the bug is absent from them. 6.3.3's source has
the fix (below), and the 6.4 snapshot, which also has it, is the only
assertions build that compiles `Crash.swift`. A separate runtime check found no
sign of wrong code on the three compilers that do not abort: a program using
both shapes printed the expected output at `-Onone` and `-O`.

**Upstream.** This is <https://github.com/swiftlang/swift/issues/86118>, closed
as completed. It was reported against a 6.3 development snapshot, with a generic
SwiftUI view whose `ForEach` over `enumerated()` destructured its closure's
parameter. <https://github.com/swiftlang/swift/pull/86131> fixed it on `main`,
and <https://github.com/swiftlang/swift/pull/86159> took the fix to
`release/6.3`, both in December 2025. They change one condition in
`buildSILFunctionThunkType`. `swift-6.3.3-RELEASE` has the fix. `release/6.2`
and `swift-6.2.4-RELEASE` do not, and no cherry-pick to 6.2 was found. #86131's
own regression test aborts swift.org's 6.2.4.

**Where TUIkit hit it:** the crumb trail in `NavigationStack`'s bar,
`ForEach(Array(crumbs.enumerated()), id: \.offset) { _, crumb in crumbView(…) }`,
in a method of `_NavigationStackCore<Root>`, where `crumbView` returns
`some View`. The destructuring closure is the conversion, `Root` makes the
context generic, and `crumbView`'s result is the opaque type. It was the next
thing swift.org's 6.2.4 stopped on once section 3 was worked around.
**Workaround:** `{ pair in crumbView(pair.element, …) }`, one closure parameter
and so no conversion. See `Sources/TUIkit/Views/NavigationStack.swift`. The
workaround is needed for as long as swift.org's 6.2 builds are supported.

---

## 5. `OptionalAnyHashableConversion` — `#expect` comparing an `Int64?` with a product of literals

```
cd OptionalAnyHashableConversion && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./variants.sh
```

```
#expect(Int64? == 9 * 116_666_667)          ASSERTS
a literal, not a product                    ok
a sum, not a product                        ASSERTS
the product typed, Int64(9) * ...           ok
value not optional                          ok
Int?, not Int64?                            ok
compared outside #expect                    ok
```

`Tests/ReproTests/Crash.swift` is one test with one expectation, and the
compiler stops in SILGen while it emits a reabstraction thunk for the
comparison `#expect` expands to:

```
TYPE MISMATCH IN ARGUMENT 0 OF APPLY AT <<debugloc at "<compiler-generated>":0:0>>
  argument value:   %16 = alloc_stack $Int64
  argument type: $*Int64
  parameter type: $*Optional<Int64>
While emitting reabstraction thunk in SIL function
"@$ss11AnyHashableVABIgr_SbIgngd_s5Int64VSgxRi_zRi0_zlyABIsgr_SbIegngd_TR".
```

Three ingredients, all necessary:

1. **An `Int64?` on the left** of `==`. The same comparison with an `Int64`, or
   with an `Int?`, is fine.
2. **An arithmetic expression of integer literals on the right**: a product or
   a sum. A single literal, or the same product with one operand typed
   (`Int64(9) * 116_666_667`), is fine.
3. **Inside `#expect`.** The same comparison assigned to a `let` first, and the
   `let` expected, is fine.

**Assertions-enabled compilers, and not fixed yet.** swift.org's 6.2.4 and the
6.4.x snapshot of 2026-09-10 (both built `+assertions`) abort on the same two
variants. Xcode's 6.2.4 and swift.org's 6.3.3 print `ok` for all seven. So the
nightly lanes stop on this spelling too.

**Where TUIkit hit it:** tests of the instants a spinner's run next steps at,
written as `#expect(scheduler.nextFiring(after: now) == 9 * 116_666_667)` (nine
7-tick frames). **Workaround:** the expected instant as one literal,
`1_050_000_003`, with the arithmetic in the message. See
`Tests/TUIkitTests/DeclinedRunClockTests.swift`, `ListChildRunTests.swift` and
`IndicatorAnimationSpeedTests.swift`.
