# API parity: TUIkit vs SwiftUI

`api_parity.py` extracts the public API of **SwiftUI** and of **TUIkit** with the
same tool and the same flags, normalises both the same way, and reports every
difference that is not deliberate. It is the low-level half of parity — the
symbol vocabulary. It says nothing about behaviour; see [Behaviour](#behaviour)
below for what does.

```sh
Tools/APIParity/api_parity.py            # extract, compare, report
Tools/APIParity/api_parity.py --check    # exit 1 on new gaps or a stale map (CI)
Tools/APIParity/api_parity.py --accept   # record today's gaps as the baseline
Tools/APIParity/api_parity.py --stale    # audit the curated map only
Tools/APIParity/api_parity.py --json out.json --work-dir /tmp/parity
```

Needs macOS with Xcode — SwiftUI's symbol graph comes out of the SDK. Takes a
couple of minutes and about 600 MB of scratch space; pass `--work-dir` to keep
the graphs for poking at, otherwise they are deleted.

## Why not `nm`

Mangled symbols lose argument labels and default values, and mix in inlinable
internals. `swift symbolgraph-extract` emits the compiler's own view of the
public surface, with full declarations. Both sides go through it identically, so
any bias in what counts as public applies equally.

Four things about that extraction are not obvious, and each one silently ruins a
naive diff:

1. **SwiftUI is two frameworks.** `View`, `Text`, `Binding` and most modifiers
   live in **SwiftUICore**, not SwiftUI. Grep `SwiftUI.swiftinterface` for
   `func lineLimit` and you get nothing. Extract only SwiftUI and most of the
   framework looks absent from itself.
2. **Most symbols are duplicates.** A symbol graph replicates every
   protocol-extension member onto every conforming type — `Shape.fill`
   reappearing as `ButtonBorderShape.fill`, and so on across ~800 types. On the
   SDK this was written against that was **79,162 of SwiftUI's 83,254 entries**.
   They are one declaration each and are dropped.
3. **Deprecated API has to go, from both sides.** Otherwise TUIkit is charged
   with gaps for surface SwiftUI is itself retiring, and a symbol either side
   still has is reported as missing from *both*. `foregroundColor` was the
   example this note was written around — SwiftUI deprecated it in favour of
   `foregroundStyle` — and it no longer illustrates it, because TUIkit has since
   dropped it for `foregroundStyle` too. The rule outlived the example.
4. **A symbol graph is only reproducible against its toolchain.** The report and
   the baseline are stamped with the compiler version for that reason.

## What counts as a difference

Symbols are keyed `Owner.name` — `View.padding(_:)`, `EnvironmentValues.locale`,
or a bare name for a top-level type. **Argument labels are part of the key**, so
`alert(_:isPresented:actions:)` and `alert(title:isPresented:)` are different
symbols. That is the rule, not an artefact: labels ARE the API, and SwiftUI
source will not compile against a different spelling. Types may legitimately
differ — a terminal counts cells where SwiftUI counts points, so `Int` for
`CGFloat` is expected and is not reported — but a label may differ only where
the behaviour genuinely differs too.

Overloads that differ only in generic constraints collapse onto one key; a
full signature check belongs in a compile corpus, not here.

### Extra OPTIONAL arguments are not a difference

The target is *source* compatibility, not identical declarations (see the two
rules at the top of `Documentation/SwiftUI-compatibility.md`), so a TUIkit
function may append parameters of its own after SwiftUI's — `.alert` carries
`borderStyle:`/`borderColor:`/`titleColor:` here. Comparing labels alone reads
those as absences, and the report claiming TUIkit has no `.alert` is simply
false; a report that cries wolf is one nobody reads.

So a SwiftUI key is counted as **compatible** when its labels are an
order-preserving SUBSEQUENCE of some TUIkit overload's and every label the call
skips over carries a default — read out of the declaration fragments, which is
where a symbol graph renders ` = nil`. Subsequence rather than prefix because
that is Swift's actual rule: a defaulted parameter can be omitted from
*anywhere*, so `f(a: 1, c: 2)` binds to `f(a:b:c:)`, while the arguments that
remain may not be reordered (SE-0060). Requiring a prefix was sound but
incomplete, and missed `border(_:width:)` and `ScrollView(_:content:)` for
exactly that reason — in both, the added parameter sits in the middle.

Nothing looser qualifies: a reordering, or an extra parameter that is
*required*, genuinely fails to compile and stays a gap.

Two limits are worth stating, because they are the ways this could mislead.

1. It proves the call **compiles**, not that it **means** the same thing.
   `fixedSize()` reaches `fixedSize(horizontal:vertical:)` whatever those
   defaults are, and is only correct because TUIkit defaults both to `true` as
   SwiftUI does — flip one and the match becomes a silent behaviour difference.
2. It proves *some* overload accepts those labels, never that exactly one does.
   Two equally-good candidates would make the call ambiguous and therefore
   uncompilable, and the reported "`<-`" is a satisfying overload rather than
   the one resolution picks.

Both are why every compatible symbol is printed in full rather than folded into
a count, and why each also appears in the compile corpus below — where the
compiler, not the model of it, has the last word.

### Label deviations are reported separately

A symbol that TUIkit has under the same name and arity but a different spelling
is worse than one it lacks: the capability is *there*, so nothing looks wrong
until real SwiftUI source fails to compile. Those are pulled out into their own
section rather than buried among absences, and `baseline.json` tracks them
separately so `--check` fails on a **new** one.

Arity must match for the comparison to mean anything — otherwise every missing
overload (`Button.init(_:image:action:)`, which needs an asset catalogue) would
read as a misspelling. Even with that filter the list contains coincidences:
`Tab.init(_:image:content:)` against `Tab.init(_:value:content:)` is two
different initialisers, not one misspelt. Read it as a shortlist to judge, not
a defect list.

Every absent symbol is then either **explained** or a **gap**:

- `parity-map.json` explains it — a deliberate rename, or something a character
  grid cannot express.
- `baseline.json` lists it — known, accepted, not yet classified.
- Otherwise it is reported, and `--check` fails.

An explanation is inherited by everything inside it: explaining
`AccessibilityRotor` also explains `AccessibilityRotor.Body`. Without that, the
map would need an entry for every member of every type nobody is implementing,
and a new one each time Apple adds a property.

## The curated map

`parity-map.json` is the human half, and the only part that can be wrong in a
way the tool cannot see. Three sections:

| Section | Means | Requires |
|---|---|---|
| `renamed` | the capability exists under another name | `tuikit`: that name. The tool checks it still exists |
| `notImplemented` | deliberately absent | `why`: what a **character grid** cannot express |
| `families` | glob patterns sharing one reason | `match`, `why` |

A `why` that just says the API sounds graphical is not good enough. A terminal
has colour, focus, selection, scrolling, menus, gradients and images; what it
does not have is sub-cell geometry, GPU compositing, pointer hover on most
hosts, and an assistive-technology stack. Say which.

**The map is audited back.** `--stale` reports an entry whose SwiftUI symbol no
longer exists, a rename whose TUIkit replacement has gone, and — most usefully —
a `notImplemented` entry for something TUIkit now implements. A map that is
never wrong is a map nobody is reading.

## The baseline

`baseline.json` is the accepted gap list, so `--check` fails on *drift* rather
than on the standing difference between a terminal framework and SwiftUI. When
you close a gap, the tool tells you the baseline is stale and `--accept`
re-records it. When you add API that SwiftUI does not have, nothing happens —
this measures what SwiftUI has and TUIkit lacks, not the reverse. TUIkit's own
vocabulary is not a defect.

Seeded 2026-08-15 from an audit of all 650 differences at the time, each
adversarially re-checked. Roughly four in five "missing" findings turned out to
be a rename or something inexpressible, which is the ratio to expect.

## Behaviour

This tool proves two frameworks use the same words. It cannot prove they mean
the same thing — `padding` existing on both says nothing about whether either
inserts the same space. Three things would, in increasing order of cost:

1. **A compile corpus — now seeded.** `CompileCorpus.swift` is SwiftUI source
   that must compile against TUIkit; `compile_corpus.sh` type-checks it and
   nothing else (a clean exit IS the assertion). It catches what the symbol
   diff cannot, in both directions: a symbol reported MISSING that in fact
   compiles because of added optional arguments, and one reported PRESENT that
   does not, because only the labels matched. Mutation-checked — deleting the
   default on `fixedSize(horizontal:)` makes it fail. It is not yet wired into
   CI, and it is a corpus of the calls that could plausibly break rather than
   an inventory of every symbol.
2. **Differential rendering.** Compile the *same* snippet against both, render
   SwiftUI headlessly (`NSHostingView` + `cacheDisplay`, which
   `Documentation/SwiftUI-compatibility.md` already cites for label metrics) and
   TUIkit into a `FrameBuffer`, then compare *structural* facts rather than
   pixels: relative order, which things share a left edge, where text wraps,
   what is clipped. Pixels will never match; "these three labels line up" should.
3. **Behavioural scenarios.** The interaction rules — what Space does versus
   Return, where focus goes on Tab, what Escape closes — have no SwiftUI oracle
   that runs headlessly. Those stay in the test suite and the PTY probes under
   `Tools/Smoke/`, written against the documented intent.

Layer 1 has begun, and the reason to grow it stands: it is deterministic, it
needs no SwiftUI runtime, and it fails loudly on exactly the drift the symbol
diff is blind to. Layer 2 remains the next real build.
