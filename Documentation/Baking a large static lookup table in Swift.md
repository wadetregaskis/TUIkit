# Baking a large static lookup table in Swift

How to embed a large, immutable lookup table (thousands of entries) into a Swift
binary so that **all the work happens at compile time** — no runtime parsing, no
`String` churn — while keeping the source readable and the build fast.

The concrete case is TUIkit's SF Symbol table: **8466** symbol names mapped to
their Plane-16 Private-Use codepoints, backing `SFSymbol.glyph(named:)` and
`Label(_:systemImage:)` (see `Sources/TUIkit/SFSymbols/` and the generator in
`Tools/GenerateSFSymbols/`). The names are pure ASCII (`[a-z0-9.]`); the
codepoints all lie in `U+100000…U+1037D1`, so `codepoint − 0x100000` fits a
`UInt16`. The lookup is a binary search by name. Everything below generalizes to
any sorted name/value table with those shapes.

The headline result: **a `StaticString` name blob + parallel integer offset
arrays** compiles in ~1.6 s, looks up in ~125 ns, costs ~0 on first access, holds
no `String`, and stays greppable. It beats every alternative on almost every axis
at once. The rest of this document is the evidence, because several of the
findings are counter-intuitive and worth not re-learning the hard way.

---

## How this was determined

Five candidate representations were generated from the same source data, each
compiled with `swiftc -O` and run through an identical harness on macOS (Apple
Swift 6.2.4, arm64). For each candidate we measured:

- **compile time** — `time swiftc -O`, median of two runs;
- **lookup throughput** — 5,000,000 lookups over all names shuffled by a seeded
  `xorshift64` Fisher-Yates plus ~10 % interleaved misses, folded into a checksum
  (to defeat dead-code elimination), timed with `ContinuousClock`, median of
  three runs → ns per lookup;
- **first-access cost** — one mid-table lookup performed *before* any other, to
  capture one-time lazy static construction;
- **binary size** — `stat` of the compiled binary (same harness across all
  candidates, so differences are the table's footprint);
- **correctness** — every one of the 8466 names must resolve to its exact
  codepoint (oracle: the source table, loaded at runtime), and a set of
  non-existent queries must return `nil`.

The winner was then **adversarially re-verified** by an independent
re-implementation (its own generator and binary search, from the source data):
all 8466 names, 400,000 fuzz mutations (flip/insert/delete/uppercase/non-ASCII),
prefix collisions, boundary and near-miss queries, and — critically — a proof
that raw-byte order equals Swift `String` order for this data (the names were
sorted three independent ways: `String.sorted(by: <)`, raw-UTF-8-byte order, and
the source order; all three are identical). Zero defects.

---

## Results

| Representation | `-O` compile | lookup | first access | binary | greppable | notes |
|---|---:|---:|---:|---:|:---:|---|
| `[(String, Character)]` array literal | **~114 s** | — | — | — | — | optimiser choke; never finished usefully |
| `[String]` + `[UInt16]` | 6.9 s | 157 ns | 85.7 µs | 445 KB | ✓ | the obvious "parallel arrays" baseline |
| `[StaticString]` + `[UInt16]` | 1.9 s | 150 ns | 31.9 µs | 543 KB | ✓ | closure-per-comparison; *largest* binary |
| **`StaticString` blob + `[UInt32]` + `[UInt16]`** | **1.6 s** | **125 ns** | **0.7 µs** | 329 KB | ✓ | **chosen** |
| `[UInt8]` blob + `[UInt32]` + `[UInt16]` | 13.4 s | 191 ns | 44.6 µs | 312 KB | ✗ | 192 k-element byte literal |
| `StaticString` blob + `InlineArray` numerics | (2.6 s @ macOS 26) | — | — | 363 KB | ✓ | **disqualified**: macOS 26 only |

Isolation probes (same toolchain): a bare `[UInt16]` literal of 8466 elements
compiles in **0.51 s**; a `[UInt32]` of 8467 in **0.52 s**. A `"a" + "b" + …`
string-concatenation chain of the full data sends the type-checker quadratic
(**> 2 min**), which is why the blob is one literal, not a concatenation.

---

## What the numbers mean

**The compile-time cost is the `[String]` literal, not the element count.** The
naive fear is that any 8000-element literal is slow. It isn't: the `[UInt16]` and
`[UInt32]` literals compile in ~0.5 s. The entire ~15 s people attribute to
"parallel arrays" is the `[String]` half alone — Swift emits per-element String
storage/metadata for every literal. Replace `[String]` with static bytes and the
whole file drops to ~1.6 s.

**A tuple-of-references literal is catastrophic.** `[(String, Character)]` — the
"obvious" shape — takes **~114 s** under `-O`. This is the *optimiser*, not the
type-checker; it does not show up in a `-typecheck` timing. Do not ship a large
literal array of structs/tuples containing references.

**A single `StaticString` literal is both fast to compile and genuinely
static.** It is one token (~0.4 s to compile even at 8466 lines) and it lives as
raw bytes in the binary — there is no backing `Array` or `String` to construct
lazily. That is why its first-access cost is **0.7 µs** versus **85.7 µs** for
`[String]` and **31.9 µs** for `[StaticString]`: those two must materialize their
backing arrays on first touch; the blob does not. First-access cost tracks
laziness, not size.

**`[UInt8]` is a poor substitute for `StaticString`.** A ~192 k-element `[UInt8]`
byte-blob literal compiles in **13.4 s** — a plain integer array of that length
*is* slow, unlike the ~8 k integer offset arrays. It is also not greppable. A
`StaticString` carrying the identical bytes is ~8× cheaper to compile and
readable.

**`InlineArray` (Swift 6.2) is not yet usable at a real deployment floor.** It is
attractive (fixed-size, inline, no `Array` heap buffer) and its array-literal
initialization compiles cleanly — but it is gated to **macOS 26**. With TUIkit's
floor of macOS 15 + Linux/Swift 6.2 it fails to link (needs the macOS 26 runtime
metadata symbol), so it was disqualified despite good compile numbers. Revisit
when the floor moves.

---

## The chosen representation

Three native, compile-time literals — no runtime parsing, no `String` in storage:

```swift
// Every name, sorted ascending, newline-separated, NO trailing newline.
// A StaticString is static bytes in the binary — never a heap String — and it
// stays greppable line by line.
static let nameBlob: StaticString = """
0.circle
0.circle.ar
…
zzz
"""

// n+1 byte offsets into nameBlob. Name i is nameBlob[starts[i] ..< starts[i+1]-1]
// (the -1 drops the separating newline; the sentinel starts[n] = blobLength+1
// makes the last name resolve the same way, with no special case).
static let nameStarts: [UInt32] = [ 0, 9, 21, … ]

// codepoint - 0x100000 (fits UInt16). Reconstruct with 0x100000 + offset.
static let codepointOffsets: [UInt16] = [ 56, … ]
```

The lookup is a lower-bound binary search that, for each probe, compares the
query's UTF-8 bytes against `nameBlob[starts[m] ..< starts[m+1]-1]` **as unsigned
bytes**. Because the names are pure ASCII, unsigned byte order is identical to
Swift `String` ordering — so the search is correct while touching no `String`.
For a native-string query (contiguous UTF-8 storage, which every Swift `String`
has) it allocates nothing; a bridged `NSString` falls back to one `Array(utf8)`
copy. The full name → `String` materialization happens only when enumerating the
whole table (`SFSymbol.all`, for a browser), never on the hot lookup path.

Two invariants the generator asserts at emit time, because the whole scheme rests
on them:

- **names are ASCII** — otherwise unsigned-byte order ≠ `String` order and the
  binary search is silently wrong;
- **`codepoint − 0x100000` fits `UInt16`** — guards against a future symbol
  outside the plane-16 window.

Note the codepoint caveat that cost real time during the benchmark: the source
table's hex field is the **full** scalar (e.g. `star.fill` = `100038`… i.e.
`U+1002C3`), not an offset — bake `cp − 0x100000`, do not add `0x100000` to an
already-full value.

---

## Takeaways for any large static Swift table

1. **Do not use a literal array of tuples/structs of references** (`[(String, …)]`)
   — ~114 s under `-O` at this scale.
2. **The `[String]` literal is the cost.** Integer (`[UInt8]`-excepted) array
   literals of the same length are cheap (~0.5 s). Store names as bytes, values
   as integers.
3. **Prefer one `StaticString` blob + parallel POD offset arrays**, and *index*
   into the blob — never parse/split it at runtime. This is fast to compile,
   truly static (near-zero first access), holds no `String`, and stays greppable.
4. **Avoid a huge `[UInt8]` blob literal** (192 k elements → 13.4 s) — use a
   `StaticString` for the bytes instead.
5. **`InlineArray` is macOS-26-only** on Swift 6.2 — not for a macOS 15 / Linux
   floor yet.
6. **Assert the representation's invariants in the generator** (here: ASCII
   names, `UInt16`-range codepoints) so a bad regeneration fails loudly rather
   than shipping a subtly wrong table.

Reference implementation: `Sources/TUIkit/SFSymbols/SFSymbol.swift` (lookup) and
`SFSymbolTable.generated.swift` (the baked literals), produced by
`Tools/GenerateSFSymbols/`.
