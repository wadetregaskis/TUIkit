# SF Symbols table generator

Regenerates [`Sources/TUIkit/SFSymbols/SFSymbolTable.generated.swift`](../../Sources/TUIkit/SFSymbols/SFSymbolTable.generated.swift)
— the baked SF Symbol *name → Unicode codepoint* table that backs
[`SFSymbol`](../../Sources/TUIkit/SFSymbols/SFSymbol.swift) and
`Label(_:systemImage:)`.

This is **developer tooling**, not part of the package build. End users never
run it; they consume the committed generated file. It is macOS-only and needs
the **SF Symbols app** installed (mirroring `Tools/Profiling`, which needs
Instruments).

## Run

From the repository root:

```sh
Tools/GenerateSFSymbols/generate.sh
```

Pass an explicit app path to override auto-detection (it tries
`SF Symbols Beta.app` then `SF Symbols.app`):

```sh
Tools/GenerateSFSymbols/generate.sh "/Applications/SF Symbols.app"
```

The script compiles and runs `GenerateSFSymbols.swift`, which writes the
generated Swift table into `Sources/` and prints a one-line summary
(symbol count + blob size). Commit the regenerated file.

## How it works

Apple ships the authoritative name → codepoint mapping inside the SF Symbols
app, in an **AES-encrypted** custom OpenType table named `symp` inside
`SFSymbolsFallback.otf`. The app decrypts it at runtime with a private Swift
routine:

```
CoreGlyphsLib.Crypton.decryptObfuscatedFontTable(tableTag: UInt32, from: CTFont) -> Data?
```

Rather than re-implement Apple's cipher, the generator **calls that routine
directly**: it binds the mangled symbol via `@_silgen_name`, `dlopen`s the
app's `CoreGlyphsLib`/`SFSymbolsShared` frameworks, builds a `CTFont` from the
app's own fallback font, and asks it to decrypt the `symp` table. The result is
a CSV whose `Name` and `PUAs` columns give the mapping. The data we bake is
therefore exactly what the app itself uses — deterministic, no guesswork, no
visual glyph matching.

The mapping is plain functional data (a symbol name paired with the Unicode
codepoint that renders it) and carries no creative expression.

## Output format

The generated file bakes three native, compile-time literals — no runtime
parsing, and no `String` in the stored table:

- **`nameBlob: StaticString`** — every name, sorted ascending, newline-separated
  (no trailing newline). A `StaticString` is just static bytes in the binary
  (never a heap `String`), and it stays greppable line by line.
- **`nameStarts: [UInt32]`** — `n+1` byte offsets. Name `i` is
  `nameBlob[nameStarts[i] ..< nameStarts[i+1] - 1]` (the `-1` drops the
  separating newline; the sentinel `nameStarts[n]` = blob length + 1 makes the
  last name resolve the same way).
- **`codepointOffsets: [UInt16]`** — each `codepoint - 0x100000` (reconstruct
  with `0x100000 + offset`).

`SFSymbol` binary-searches `nameBlob` *directly* through `nameStarts`, comparing
raw UTF-8 bytes — which equals Swift `String` ordering because the names are
pure ASCII — so a lookup touches no `String` and (for a native-string query)
allocates nothing. The file is gated behind `#if canImport(AppKit)`, so non-Apple
builds carry none of it.

### Why this shape

The representation was chosen by benchmarking (compile time, lookup ns/op,
first-access cost, binary size, correctness) — see the commit that introduced
it. The findings:

- A literal `[(String, Character)]` array — the obvious form — takes **~114 s**
  under `-O` (the optimiser chokes on 8466 tuples); even parallel `[String]` /
  `[UInt16]` arrays are **~15 s**, dominated entirely by the `[String]` literal.
- The `StaticString`-blob form compiles in **~1.6 s**, has the **fastest lookup**
  (~125 ns/op) and **near-zero first-access** cost (~0.7 µs — nothing is lazily
  constructed; the blob and the two integer arrays are pure compile-time
  constants), and the **smallest** binary of the greppable options.
- `InlineArray` (Swift 6.2) for the numeric columns was rejected: it is gated to
  **macOS 26**, so it won't run on the macOS 15 + Linux deployment floor.

The generator asserts at emit time that every name is ASCII (the invariant the
byte-order binary search relies on) and that every codepoint fits the `UInt16`
PUA window.

## Fragility

This depends on the SF Symbols app's internal table format and the decryptor's
mangled symbol name. If a future SF Symbols release changes either, the
generator will fail loudly (nil decrypt, or missing `Name`/`PUAs` columns) — the
*baked* table keeps working until you regenerate. Re-derive the format/symbol
and update `GenerateSFSymbols.swift`, then re-run.
