# Compiler bugs TUIkit has hit

Seven Swift bugs the framework works around. Each has a self-contained repro here
so the workaround can be checked against a new toolchain and deleted the moment
it stops being needed — and so they can be reported upstream without anyone
having to build TUIkit.

The first two were found in August 2026. Toolchains: **Apple Swift 6.2.4**
(`swiftlang-6.2.4.1.4`, Xcode) and the **6.5-dev snapshot of 2026-08-30**
(`swift-DEVELOPMENT-SNAPSHOT-2026-08-30-a`, which is built `+assertions`).
The third, fourth and fifth were found in September 2026, on swift.org's **Swift
6.2.4** (`swift-6.2.4-RELEASE`, which is also built `+assertions`, and is what
swiftly installs). The sixth was found in September 2026 too, by the lane that
builds the tests with **Swift 6.4** (`swift-6.4-RELEASE`). It is the only one
here that swift.org's 6.2.4 — the local default, and so the compiler every other
entry was found with — does not show at all. The seventh was found in September
2026 and is the only one that is not a crash or wrong code: it is a false
diagnostic, and every toolchain here reports it.

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
tcs=~/Library/Developer/Toolchains
cd LoadableByAddressAssertion && ./variants.sh "$tcs/swift-6.2.4-RELEASE.xctoolchain" \
    /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain \
    "$tcs/swift-6.3.3-RELEASE.xctoolchain" \
    "$tcs/swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-09-10-a.xctoolchain"
```

```
                                                6.2.4 +a      Xcode 6.2.4   6.3.3         6.4.2-dev +a
Crash.swift: 3-word field, 5-word closure arg   ABORTS        BAD SIL       BAD SIL       ABORTS
2-word field (tuple not large)                  ok            ok            ok            ok
4-word closure arg (arg not large)              ok            ok            ok            ok
unlabelled tuple                                ABORTS        BAD SIL       BAD SIL       ABORTS
not Optional                                    ok            ok            ok            ok
no closure in the tuple                         ok            ok            ok            ok
a struct instead of a tuple                     ok            ok            ok            ok
```

`+a` marks a compiler built with assertions. The assertion is in a SIL pass
that runs on the way to IRGen, so each variant is compiled to an object with
`-c -Onone -Xfrontend -sil-verify-all`, and `BAD SIL` means the verifier
rejected the SIL.

`Crash.swift` is three declarations, and a compiler built with assertions stops
in the LoadableByAddress pass. swift.org's 6.2.4 prints (the 6.4 snapshot the
same, at line 2456):

```
Assertion failed: (srcType == tgtType && "Source and target type do not match"),
function rewriteFunction, file LoadableByAddress.cpp, line 2199.
```

The **declaration alone** is enough — nothing has to assign to the property. It
is the synthesized setter the pass chokes on: the verifier names the setter for
`pending` as the function it rejects.

Both halves have to be "large loadable" (over four words), and each for its own
reason:

- the **tuple** must be large, so the pass rewrites it — three words of struct
  plus a two-word thick function is five;
- the **closure's parameter** must be large, so the *function type* is itself
  rewritten to take it indirectly — five words does it, four does not.

Then `rewriteFunction` compares the rewritten type against the original and
they disagree. Labels make no difference. Dropping the `Optional`, the closure,
or the tuple (a struct with the same two fields) all avoid it.

**No toolchain tested produces valid SIL for it.** Observed on macOS (arm64)
on 2026-09-15: the two builds with assertions, swift.org's 6.2.4
(`swift-6.2.4-RELEASE`) and the 6.4 snapshot of 2026-09-10, abort on the two
rows that say so. It stops a swift.org release toolchain as well as the nightly
lanes. The two builds without assertions, Xcode 26.3's 6.2.4
and swift.org's 6.3.3, do not abort, but the verifier rejects the SIL of those
same two rows ("SIL verification failed: entry point argument types do not
match function type") and accepts the other five. Without
`-Xfrontend -sil-verify-all` they compile all seven, so a clean compile on them
is not a clean bill. A program that stores, reads, mutates and clears such a
property printed the right values with both, at `-Onone` and `-O`, so no wrong
code was seen, but that one program is all that was checked.

**Where TUIkit hit it:** `MouseEventDispatcher.pendingHoverExit` was
`(region: HitTestRegion, handler: (MouseEvent) -> Bool)?` — `HitTestRegion` is
well over three words and `MouseEvent` is eight, so both thresholds were met.
**Workaround:** a named struct instead of the tuple, the table's last row, which
no toolchain aborts on and the verifier accepts.

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
read `isPreconcurrency` through `getRootConformance()`. Why that matters for a
pack type is a guess nobody has checked: the conformance looked up there may be
a specialized one, which the old cast to `NormalProtocolConformance` fails on,
leaving the flag `false`. It is in `release/6.3` and
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

## 5. `OptionalAnyHashableConversion` — a function conversion that erases an `Optional` to `AnyHashable`

```
tcs=~/Library/Developer/Toolchains
cd OptionalAnyHashableConversion && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    ./variants.sh "$tcs/swift-6.2.4-RELEASE.xctoolchain" \
    /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain \
    "$tcs/swift-6.3.3-RELEASE.xctoolchain" \
    "$tcs/swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-09-10-a.xctoolchain"
```

```
                                            6.2.4 +a      Xcode 6.2.4   6.3.3         6.4.2-dev +a
Crash.swift: to (Int?) -> Void              ABORTS        BAD SIL       BAD SIL       ABORTS
a function: to (Int?) -> Void               ABORTS        BAD SIL       BAD SIL       ABORTS
a function: to (Value?) -> Void, generic    ABORTS        BAD SIL       BAD SIL       ABORTS
result: () -> Int? to () -> AnyHashable     ABORTS        BAD SIL       BAD SIL       ABORTS
#expect's expansion, in plain Swift         ABORTS        BAD SIL       BAD SIL       ABORTS
the same, one literal                       ok            ok            ok            ok
to (Int) -> Void, not Optional              ok            ok            ok            ok
from Any, not AnyHashable                   ok            ok            ok            ok
from AnyHashable?, not AnyHashable          ok            ok            ok            ok
a value, not a function                     ok            ok            ok            ok
a closure that erases it itself             ok            ok            ok            ok
#expect(Int64? == 9 * 116_666_667)          ABORTS        BAD SIL       BAD SIL       ABORTS
#expect(Int64? == 1 + 1_050_000_002)        ABORTS        BAD SIL       BAD SIL       ABORTS
#expect(Int64? == 1_050_000_003)            ok            ok            ok            ok
#expect(Int64? == Int64(9) * 116_666_667)   ok            ok            ok            ok
#expect of a let holding the comparison     ok            ok            ok            ok
run: nil, erased directly                   ABORTS        nil           nil           ABORTS
run: 5, erased directly                     ABORTS        5             5             ABORTS
run: nil through (Int?) -> String           ABORTS        trap (133)    trap (133)    ABORTS
run: 5 through (Int?) -> String             ABORTS        Optional(5)   Optional(5)   ABORTS
```

`+a` marks a compiler built with assertions. Each variant is compiled with
`-emit-silgen -Xfrontend -sil-verify-all`, and `BAD SIL` means the verifier
rejected what SILGen emitted. The `run` rows build one small program at `-Onone`
(it is in `variants.sh`) and run it, so they read `ABORTS` wherever that program
does not compile. The `#expect` rows use the toolchain's own swift-testing, or
Xcode's, which is why `DEVELOPER_DIR` points at Xcode.

`Crash.swift` is one line, with no imports:

```swift
_ = { (_: AnyHashable) in } as (Int?) -> Void
```

A compiler built with assertions stops while it emits the reabstraction thunk:

```
TYPE MISMATCH IN ARGUMENT 0 OF APPLY AT <<debugloc at "<compiler-generated>":0:0>>
  argument type: $*Int
  parameter type: $*Optional<Int>
While emitting reabstraction thunk in SIL function "@$ss11AnyHashableVIegn_SiSgIegy_TR".
```

**A compiler without assertions compiles it to wrong code.** The thunk unwraps
the `Optional` as if it were implicitly unwrapped, so `nil` traps ("Unexpectedly
found nil while implicitly unwrapping an Optional value"). A value that is there
is stored as an `Int`, and the thunk passes that address to
`_convertToAnyHashable<Optional<Int>>`, which reads an `Optional<Int>`: one byte
more than was written. The `run` rows show both: `nil` traps, and `5` arrives as
`Optional(5)`, where erasing the same `Int?` directly gives `5`. The non-nil
result depends on a byte nobody wrote, so it may differ elsewhere. With
`-Xfrontend -sil-verify-all` those compilers reject the SIL instead
("operand of 'apply' doesn't match function input type").

Three things are needed:

1. **A function conversion.** Erasing a value, `let erased: AnyHashable =
   Int?.none`, is fine. A closure that erases the value itself,
   `{ body(AnyHashable($0)) }`, is fine, and is the workaround.
2. **An `Optional` on one side**, in a parameter (`(AnyHashable) -> Void` to
   `(Int?) -> Void`) or in a result (`() -> Int?` to `() -> AnyHashable`). Any
   wrapped type does it, a generic one too. A non-optional `Int` is fine.
3. **Exactly `AnyHashable` on the other side.** `Any`, or `AnyHashable?`, is fine.

From reading the compiler's source (not verified): `Transform::transform` in
`lib/SILGen/SILGenPoly.cpp` force-unwraps an optional input whenever the output
is neither optional nor an existential, a rule meant for implicitly unwrapped
optionals in `@objc` overrides. `AnyHashable` is a struct, so the `Optional` is
unwrapped, and the later `AnyHashable` branch then erases the unwrapped value
with the formal type still `Optional<Int>`.

**How `#expect` gets there.** `#expect(value() == 9 * 116_666_667)`, with
`value()` an `Int64?`, expands to
`__checkBinaryOperation(value(), { $0 == $1() }, 9 * 116_666_667, …)`. With
untyped literal arithmetic on the right, the type checker picks `AnyHashable`'s
`==` for that closure, and converts it to `(Int64?, () -> AnyHashable) -> Bool`,
which is this conversion. A sum does the same. A single literal, a typed operand
(`Int64(9) * 116_666_667`), or the comparison evaluated into a `let` first leaves
`AnyHashable` out. The table's "#expect's expansion, in plain Swift" row is the
expansion without swift-testing.

**Corrected on 2026-09-14.** This section used to present the bug as `#expect`
comparing an `Int64?` with a product of literals, gave those as its three
ingredients, and listed Xcode's 6.2.4 and swift.org's 6.3.3 as `ok`. `#expect`
is only one way to form the conversion, and the two `ok` compilers compile it
to wrong code. The repro was a SwiftPM package with one test. It is now one
file for `swiftc`, and the `#expect` forms are rows of the table.

### Affected versions

Observed on macOS (arm64) on 2026-09-14, with `Crash.swift` and the variants
above:

| Toolchain | Build config | `Crash.swift` |
|---|---|---|
| swift.org 6.2.4 (`swift-6.2.4-RELEASE`) | +assertions | aborts |
| Xcode 26.3's 6.2.4 (`swiftlang-6.2.4.1.4`) | no assertions | compiles to **wrong code**; rejected with `-sil-verify-all` |
| swift.org 6.3.3 (`swift-6.3.3-RELEASE`) | no assertions | compiles to **wrong code**; rejected with `-sil-verify-all` |
| swift.org 6.4 snapshot of 2026-09-10 (`6.4.2-dev`) | +assertions | aborts |

No toolchain tested handles the conversion correctly, so it is not fixed as of
that snapshot.

**Upstream.** No issue or pull request for it was found as of 2026-09-14.
<https://github.com/swiftlang/swift/pull/5507> (2016) added `AnyHashable`
erasure to function conversions, and
<https://github.com/swiftlang/swift/issues/45208> (SR-2603) is an older crash
with the same `==`-picks-`AnyHashable` shape but no `Optional`.

**TUIkit's exposure: none in the code swift.org's 6.2.4 compiles.** The wrong
code is exactly the argument-type mismatch that the assertion checks, so a
compiler built with assertions aborts where one without them would emit it.
swift.org's 6.2.4 (+assertions) builds the package, its tests and its
benchmarks from clean with no warnings (`TUIKIT_BENCHMARKS=1 swift build
--build-tests`, 2026-09-14), so none of that code forms this conversion. Keeping
that compiler as the local default `swift` therefore also detects this
miscompile. It covers only what a macOS build compiles, not `#if` branches for
other platforms, but `git grep` finds `AnyHashable` in no file that has an `#if`
at all.

**Where TUIkit hit it:** tests of the instants a spinner's run next steps at,
written for f857c2c1 as `#expect(scheduler.nextFiring(after: now) == 9 *
116_666_667)`, where `nextFiring` returns an `Int64?`. swift.org's 6.2.4
aborted. Xcode's 6.2.4 would have compiled it without complaint. A plain-Swift
copy of that expansion, built without assertions, traps on `nil`, and returned
`false` for an equal value in three of four builds (6.3.3 at `-Onone` and `-O`,
Xcode's 6.2.4 at `-O`). **Workaround:** the expected instant as one literal.
Since 41a2bcc1 those tests (`DeclinedRunClockTests.swift`,
`ListChildRunTests.swift`, `IndicatorAnimationSpeedTests.swift`) spell an
instant as one literal or as a call to `AnimationClock.nanoseconds(atTick:)`,
and neither forms the conversion. In an `#expect` on an optional, give
arithmetic on the right a type, or write one literal.

---

## 6. `MacroClosureDiscriminatorCollision` — two closures lowered to one function

```
tcs=~/Library/Developer/Toolchains
cd MacroClosureDiscriminatorCollision && \
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./variants.sh \
    "$tcs/swift-6.2.4-RELEASE.xctoolchain" \
    /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain \
    "$tcs/swift-6.3.3-RELEASE.xctoolchain" \
    "$tcs/swift-6.4.0-RELEASE.xctoolchain"
```

```
                                              6.2.4 +a      Xcode 6.2.4   6.3.3         6.4
Crash.swift: macro closure, then filter       ok            WRONG         WRONG         MISMATCH
one source closure BEFORE the macro           ok            ok            ok            ok
two source closures before the macro          ok            ok            ok            ok
partner allSatisfy, not filter (no error)     ok            WRONG         WRONG         WRONG
no enclosing closure                          ok            ok            ok            ok
the macro call moved out of this scope        ok            ok            ok            ok
#require instead of #expect                   ok            WRONG         WRONG         MISMATCH
a struct element, not a tuple                 ok            WRONG         WRONG         MISMATCH
an unlabelled tuple element                   ok            WRONG         WRONG         MISMATCH
a source closure of a different type          ok            ok            ok            ok
WORKAROUND: no closure inside the macro       ok            ok            ok            ok
```

`+a` marks a compiler built with assertions, though assertions have nothing to do
with this one. `MISMATCH` is the `function type mismatch` error; `WRONG` means it
built and then ran one closure in place of another; `ok` means both closures ran
their own bodies.

**The oracle here is the run, not the compile.** On 6.2 and 6.3 this bug emits no
diagnostic at all — it drops one closure's body and calls the other — so a clean
compile is not a clean bill, and every variant asserts a result for both closures
so that a swap in either direction fails it. Each variant is built through
SwiftPM, not by calling `swiftc` directly, so every toolchain uses its OWN
swift-testing and macro plugin; that is load-bearing, because pointing one
toolchain's compiler at another's swift-testing reports collisions the real build
does not have.

Two closure literals of the same type, in the same enclosing closure, are lowered
to a SINGLE SIL function when the first is inside a macro expansion buffer and
the second follows it in ordinary source. They get the same local discriminator,
hence the same mangled name, so SILGen's `getOrCreateFunction` returns the
function it already made and the second closure's body is never emitted:

```swift
withCurrent {
    let drawn = cells()
    #expect(drawn.allSatisfy { $0.character != "z" }, "the closure in the macro")
    let flagged = drawn.filter { $0.state.flag }   // really runs the predicate above
    #expect(flagged.map(\.character) == ["b", "c"], "\(flagged.map(\.character))")
}
```

Four things are needed, each isolated by a row above:

1. **An enclosing closure.** The same statements at the top level of the test
   function are fine.
2. **A closure inside a macro expansion buffer.** The identical call written as an
   ordinary function taking the same closure is fine, so it is the BUFFER, not
   swift-testing's API. `#require` does it as well as `#expect`.
3. **The macro's closure FIRST.** A source closure before the macro is fine.
4. **The same closure type on both sides.** A `map` returning `Character` beside an
   `allSatisfy` returning `Bool` is fine.

Neither the tuple nor its labels matter: a struct element and an unlabelled tuple
both reproduce it.

**`filter` is not required, and that is the dangerous part.** Only `filter` makes
6.4 complain, because the standard library's `filter` is now typed-throws while
`allSatisfy` still rethrows, so the two demanded types visibly disagree
(`@error any Error` against `@error_indirect … Never` — the error quotes both).
With `allSatisfy` as the partner the same collision happens on 6.4 too, silently.
A clean 6.4 build therefore does not prove a file is free of this.

### Affected versions

Observed on macOS (arm64) on 2026-09-16, with `Crash.swift` and the variants
above:

| Toolchain | Build config | `Crash.swift` |
|---|---|---|
| swift.org 6.2.4 (`swift-6.2.4-RELEASE`) | +assertions | passes |
| Xcode 26.3's 6.2.4 (`swiftlang-6.2.4.1.4`) | no assertions | **wrong code** |
| swift.org 6.3.3 (`swift-6.3.3-RELEASE`) | no assertions | **wrong code** |
| swift.org 6.4 (`swift-6.4-RELEASE`) | no assertions | compile error |

The two 6.2.4 rows are the same compiler version and disagree, so the compiler
version alone does not place a toolchain in this table. They ship different
swift-testing builds — `Testing Library Version: 6.2.4 (5ee435b15ad40ec)` against
Xcode's `1501` — and the expansion is what the discriminator is counted over.
swift.org's 6.2.4 is the local default (`swiftly`), which is why the suite was
green here while 6.3.3 was red.

**Upstream.** No issue was found for it when this was diagnosed. The reduction is
small and needs only `import Testing`, so it is worth reporting.

**Where TUIkit hit it:** four sites in two test files —
`ReversedTextSelectionTests.swift` (three) and `LiveTerminalPaletteRenderTests.swift`
(one) — each a `#expect` whose closure was followed by a `filter` over cells of
`(character: Character, state: SGRState)` inside a `TerminalColors.withCurrent`
closure. Swift 6.4 could not build the test target at all. Swift 6.3.3 built it
and ran the wrong predicates: the full suite recorded **27 issues (21 known, 6
real)** where 6.2.4 recorded only its 21 known ones, so each `filter` really ran
the preceding `#expect`'s closure. **Workaround:** the table's last row — every
closure in those scopes is hoisted into a `let` above its `#expect`, leaving no
closure inside a macro expansion there, which is safe on all four toolchains
regardless of how many closures the scope holds. Reordering the statements also
happens to work, but it depends on the closure counts in the scope and so is not
a rule anyone can apply by eye. After the fix, 6.4 builds the test target clean
and 6.3.3's full suite is back to 21 known issues.


---

## 7. `ArrayEquatableCastWarning` — a cast that is called redundant and is not

```
cd ArrayEquatableCastWarning && ./variants.sh
```

Wherever `Foundation` is imported, a conditional cast of an **array** (or a
dictionary) to a protocol existential its element does not conform to is
reported as one that always succeeds:

```swift
import Foundation

struct Plain { let x: Int }

func isComparable(_ rows: [Plain]) -> Bool {
    (rows as? any Equatable) != nil
    // warning: conditional cast from '[Plain]' to 'any Equatable' always succeeds
}
```

`Plain` has no conformances at all, so there is nothing conditional left to
reason about: `[Plain]` cannot be `Equatable` under any substitution. And it is
not — the cast fails at runtime, which is what the `as?` is for.

| | 6.2.4 +a | Xcode 6.2.4 | 6.3.3 | 6.4 |
|---|---|---|---|---|
| `Warning.swift`: `[Plain]` and `[Row]` to `Equatable` | WARNS | WARNS | WARNS | WARNS |
| the same, with no import | quiet | quiet | quiet | quiet |
| `[Row]` to `Hashable`, Foundation | WARNS | WARNS | WARNS | WARNS |
| `Plain` itself, not an array, Foundation | quiet | quiet | quiet | quiet |
| a `Dictionary`, Foundation | WARNS | WARNS | WARNS | WARNS |
| `Set<Row>` to `Equatable`, Foundation | WARNS | WARNS | WARNS | WARNS |
| `Set<Row>` to `Equatable`, no import | WARNS | WARNS | WARNS | WARNS |
| `[Row]` to `CustomStringConvertible`, no import | WARNS | WARNS | WARNS | WARNS |
| the collection as ONE generic, Foundation | quiet | quiet | quiet | quiet |
| run: `[Plain] as? any Equatable` | fails | fails | fails | fails |
| run: `[Equatable] as? any Equatable` | succeeds | succeeds | succeeds | succeeds |
| run: empty `[Plain] as? any Equatable` | fails | fails | fails | fails |

The last three rows are the answer the diagnostic denies, and the first two rows
are the trigger: **the import**. Two rows in the middle are the CORRECT warning,
kept so the table says which claims are sound — `Set<Element>` requires
`Element: Hashable` and so is unconditionally `Equatable`, and `Array` conforms
to `CustomStringConvertible` unconditionally; both warn with no import at all.
`Plain` on its own stays quiet with Foundation imported, so it is not "anything
in a Foundation file" — it is the bridgeable COLLECTION types, whose
`_ObjectiveCBridgeable` path reaches `NSArray`/`NSDictionary` and so `NSObject`,
which does conform. The runtime cast does not bridge, so it does not follow.

What it costs is a false report that a check is redundant, in the one place it is
load-bearing. Deleting the `?` does not compile, so a reader who believes the
compiler reaches for `as!` instead — and gets a trap.

### Affected versions

Observed on macOS (arm64) on 2026-09-21. Every toolchain to hand reports it,
including 6.4, so there is nothing to wait for.

**Upstream.** No issue was found for it. The reduction is four lines and needs
only `import Foundation`.

**Where TUIkit hit it:** `_TableCore.rowsSignature(of:)`
(`Sources/TUIkit/Views/Table.swift`), which asks whether a table's rows can be
compared so that a `.fit` column's width can be kept across frames. Written
against the concrete `[Value]` — or against `[Row]` in a generic helper — it
drew the warning, and the zero-warnings rule made it a build failure in
practice. **Workaround:** take the collection as ONE opaque generic parameter
(`rowsSignature<Rows>(of rows: Rows)`), which is also how
`ForEach.listRowsSignature` is spelled and why that one never warned. The
behaviour is unchanged either way, and `TableFitColumnMemoTests` renders a table
of un-comparable rows and counts the scans to prove the cast really does fail.
