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

The generated file is a plain, readable table — one Swift multiline string
literal with one `name HEXCODEPOINT` line per symbol, sorted by name:

```
square.and.arrow.up 100D82
square.and.arrow.up.fill 100D83
star.fill 1002C3
…
```

`SFSymbol` parses it once on first use into a sorted `[(name, Character)]` array
and binary-searches that. The whole file is gated behind `#if canImport(AppKit)`,
so non-Apple builds carry none of it.

A literal Swift array (`[(String, Character)]`) would be the obvious
representation, but the optimiser can't handle one this large: 8000+ tuples take
~2 minutes under `-O` (even split into parallel `[String]` / `[UInt32]` arrays,
~15 s). A single string literal compiles in under half a second and the one-time
parse is sub-millisecond — so the source stays readable *and* the build stays
fast.

## Fragility

This depends on the SF Symbols app's internal table format and the decryptor's
mangled symbol name. If a future SF Symbols release changes either, the
generator will fail loudly (nil decrypt, or missing `Name`/`PUAs` columns) — the
*baked* table keeps working until you regenerate. Re-derive the format/symbol
and update `GenerateSFSymbols.swift`, then re-run.
