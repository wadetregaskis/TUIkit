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

The generated file embeds one base64 string. Decoded, the blob is:

```
[UInt32 LE: nameSectionLength]
[name section: front-coded names, sorted ascending]
    per entry: [UInt8 sharedPrefixLen][suffix bytes][0x00]
[codepoint section: nameCount × UInt16 LE, each = codepoint − 0x100000]
```

Front-coding stores only the bytes each sorted name *differs* from its
predecessor by, which collapses the deep shared prefixes
(`square.and.arrow.up`, `.up.fill`, `.up.circle`, …). `SFSymbol` decodes it
lazily on first use. The whole file is gated behind `#if canImport(AppKit)`, so
non-Apple builds carry none of it.

## Fragility

This depends on the SF Symbols app's internal table format and the decryptor's
mangled symbol name. If a future SF Symbols release changes either, the
generator will fail loudly (nil decrypt, or missing `Name`/`PUAs` columns) — the
*baked* table keeps working until you regenerate. Re-derive the format/symbol
and update `GenerateSFSymbols.swift`, then re-run.
