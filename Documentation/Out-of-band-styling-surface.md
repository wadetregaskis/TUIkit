# Out-of-band styling surface

**Status:** proposed (design panel recommendation, 2026-07-20). This is a
decision document: it specifies the model to build, the operations it must
support, and — crucially — the **measurement gate** that decides whether it
ships at all. No framework code has changed. The recommendation is
*provisional on the spike clearing the thresholds in §7*.

**One-paragraph summary.** Move styling metadata out of the buffer's line
strings. Keep one **plain-text** `String` per row (no ANSI), and carry style
in a parallel, **by-value, cell-addressed** sidecar — `[[StyleRun]]`, one
`[StyleRun]` per line, each run a small POD covering a half-open range of
terminal *columns*. ANSI is **generated once at flush** for changed rows and
**parsed never** during layout. `overlays` and `hitTestRegions` are carried
byte-for-byte. This is the AttributedString-style separation the owner asked
for, at ~1.2–1.5× the current string memory and ~50–70× lighter than a cell
grid, and it deletes the `ansiAware*` / `forEachVisibleANSIRun` /
`insertOverlay`-SGR-restore family. It is **consolidation, not a bug fix** —
the wide-char correctness a cell grid would buy us has already been paid down
per-site (see §1).

---

## 1. Problem and goals

### 1.1 The inline-metadata debt

`FrameBuffer` (`Sources/TUIkitCore/Rendering/FrameBuffer.swift`, 819 lines) is
the value type every view renders into and every layout container stacks,
overlays, and clips each frame. Its single styled surface is:

```swift
public var lines: [String] {   // "may contain ANSI escape codes"
    didSet { recomputeWidth() }
}
```

Style lives **inline**, interleaved into the text as SGR escape sequences.
Every operation that reasons about columns — width, clip, pad, splice,
composite — must therefore parse ANSI back out of the string, count visible
cells around the escapes, and (for composite/background) reconstruct and
re-emit SGR state. That machinery is `Sources/TUIkitCore/Extensions/String+TerminalWidth.swift`
(1,128 lines): `strippedLength`, `forEachVisibleANSIRun`, `ansiSegments`,
`ansiAwarePrefix(WithWidth)`, `ansiAwareSuffix`, `ansiAwareSlice`,
`ansiStateBefore`, `ansiSGRContextAndCleanSuffix`, `leadingANSISequences`.

Two structural costs follow:

1. **ANSI is parsed N times per frame.** It is emitted early (at the leaf, by
   `ANSIRenderer`) and then re-scanned by every measure/clip/slice/overlay up
   the tree — O(depth) parses per line per frame, the O(depth²) re-measure
   shape that `linesAreUniformWidth` / `lineWidths` were bolted on to fight.
2. **Style is fused to width.** Any restyle rewrites the string, which trips
   `didSet → recomputeWidth()` and drops the per-line width caches to `nil`
   even though the visible geometry did not change.

The measured call-site fan-out (Sources only, code lines, excluding the
definition file):

| Symbol | Call sites | Role |
|---|---|---|
| `strippedLength` | 83 | visible width of a (possibly styled) line |
| `terminalWidth` | 77 | per-`Character` cell width + the cursor-advance family |
| `padToVisibleWidth` | 15 | the central pad primitive |
| `ansiAwarePrefix` | 10 | right-edge clip |
| `ansiAwareSuffix` / `ansiAwareSlice` | 3 / 1 | scroll windowing, overlay suffix |
| `ansiStateBefore` | 1 | overlay SGR restore |
| `ansiSGRContextAndCleanSuffix` | 1 | `FrameDiffWriter.repaintRightEdge` |

`strippedLength` is the top *inclusive* cost in render profiling (~20–23% in
the `nested`/`textwall` trees), and it is slow **only** on styled lines — the
ESC-scanning state machine `forEachVisibleANSIRun`. On plain lines it takes
the byte/ASCII fast path (`visibleRunWidth`).

### 1.2 The wide-char bug class — already paid down

Terminal layout math done in `String.count`/`prefix`/padding rather than
*cells* breaks on wide graphemes (CJK, emoji): a straddling wide glyph gets
half-counted at a clip or composite boundary. **This class is largely already
handled per-site in our tree.** `Character.terminalWidth` is a complete,
cross-platform width table; the splice sites (`insertOverlay`, `clamped`,
`ansiAwareSlice`) already drop-and-pad a straddling wide glyph; and the
per-terminal cursor-advance models (`terminalAppCursorAdvance`,
`iTerm2CursorAdvance`, `ghosttyCursorAdvance`, `warpCursorAdvance`,
`tmuxCursorAdvance` in `String+TerminalWidth.swift`, plus
`withTerminalAppCursorCompensation` / `withSkinToneFallback` in
`String+CursorCompensation.swift`, 477 lines) are DSR-measured and recorded in
`Documentation/Terminal-compatibility.md`.

This reorders the whole evaluation: **the headline feature of a cell grid —
model-level cells-not-characters correctness — is a benefit we have already
banked by other means.** For us the value of a new surface model is
*consolidation* and *getting inline metadata out-of-band*, **not** correctness.
A model whose principal selling point is wide-char correctness (upstream's
cell grid; Approach D) is paying memory we dislike for a benefit we do not
need.

### 1.3 The memory constraint

The owner dislikes **both** inline string metadata **and** the cell grid's
memory overhead. A full-screen `[[TerminalCell]]` costs ~1 MB (see §5) — ~60×
the current string floor — because it is O(W·H) regardless of how much of the
screen is actually styled, and TUI chrome is overwhelmingly unstyled. The new
model must keep memory in the "few× the current strings" band, i.e. O(style
transitions), not O(cells).

### 1.4 Goals

- **G1 — out-of-band.** Row text is pure graphemes; every SGR attribute lives
  in a parallel structure. (The owner's explicit ask.)
- **G2 — near-string memory.** ≤ a small multiple of today's `[String]`;
  nowhere near a cell grid, and never exceeding it even pathologically.
- **G3 — consolidate the width/ANSI surface.** Delete the ANSI-state-machine
  half of `String+TerminalWidth.swift` and the `insertOverlay` SGR-restore /
  `applyPersistentBackground` re-apply hacks.
- **G4 — profile-aligned CPU.** The plain-line fast path must reach every
  `strippedLength`; ANSI parses must fall off the layout path.
- **G5 — preserve `overlays` + `hitTestRegions` semantics exactly.** The
  mouse/overlay system threads them through every combining op; that must not
  change.
- **G6 — measure before committing.** Runtime cost is gated on the spike in
  §7, not asserted on paper.

### 1.5 Non-goals

- **Not** eliminating the cells-not-characters class model-level. The grapheme
  width walk (`Character.terminalWidth`) and per-site straddle drop-and-pad
  **stay**; only the ANSI×width *interleaving* is removed. If killing
  cells-not-characters outright were the goal, only a cell grid does that — and
  we have decided its memory is not worth a benefit we already hold.
- **Not** style interning / a shared style table in v1 (see §8, Approach B).
  By-value runs keep buffers self-contained; interning is a later,
  TUIContext-scoped optimization *only if* profiling shows run-value copies.
- **Not** changing the per-terminal cursor-advance models. They relocate from
  operating on an already-emitted ANSI string to running inside the flush
  encode; the *tables* are unchanged.
- **Not** a permanent `lines: [String]` compat shim. Pre-1.0 house rules
  forbid it; the shim is the migration *mechanism* and is deleted once
  producers/consumers are structured (see §6, and the go/no-go gate there).

---

## 2. The chosen model

Plain-text lines + a by-value, cell-addressed style-run sidecar. This is the
point where the panel's **Approach A** and **Approach C2** converge — same POD,
same cell coordinates, same "ANSI generated once at flush, parsed never"
contract, same rejection of interning. They are one design.

### 2.1 Data types

```swift
/// A normalized terminal color, tag-packed into 4 bytes — no Optional, so the
/// two colors of a CellStyle cost 8 bytes with no enum-tag padding.
/// 2-bit tag {default, ansi16, indexed256, rgb} + 30-bit payload.
/// `.default` (all-zero) is the "unset" sentinel.
public struct PackedColor: Sendable, Equatable, Hashable {
    public var rawValue: UInt32
    public static let `default` = PackedColor(rawValue: 0)
}

/// The visual state applied to a run of cells. ~12 bytes, trivially POD,
/// Sendable/Equatable/Hashable, copies with no heap traffic. Content-equivalent
/// to upstream's `TerminalStyle` minus text-only knobs (truncationMode,
/// lineLimit) which are layout inputs, not cell attributes.
public struct CellStyle: Sendable, Equatable, Hashable {
    public struct Attributes: OptionSet, Sendable, Hashable {
        public let rawValue: UInt8       // 8 SGR flags in one byte
        public static let bold: Attributes          // 1 << 0
        public static let dim: Attributes           // 1 << 1
        public static let italic: Attributes        // 1 << 2
        public static let underline: Attributes     // 1 << 3
        public static let blink: Attributes         // 1 << 4
        public static let inverse: Attributes       // 1 << 5
        public static let strikethrough: Attributes // 1 << 6
        public static let hidden: Attributes        // 1 << 7
    }
    public var attributes: Attributes = []
    public var foreground: PackedColor = .default
    public var background: PackedColor = .default

    public var isDefault: Bool {
        attributes.isEmpty && foreground == .default && background == .default
    }
}

/// One contiguous run of equally-styled terminal columns. 20 bytes, no heap.
/// COORDINATES ARE CELLS, not character indices.
public struct StyleRun: Sendable, Equatable {
    public var start: Int32   // first cell column (0-based)
    public var length: Int32  // width in CELLS (> 0)
    public var style: CellStyle
}
```

`FrameBuffer` re-backed:

```swift
public struct FrameBuffer: Sendable, Equatable {
    /// Visible graphemes only — NO ANSI escapes. ALL width/slice/pad/hit-test
    /// math runs on this. (During migration this is stored under a private
    /// name and `lines` is the computed ANSI shim; see §6. Post-migration it
    /// is simply the public `lines`, now plain.)
    var text: [String]

    /// Per-line style runs, parallel to `text` (count == text.count).
    /// `[]` == a fully-default line (the common case). NORMALIZED (see §2.3).
    var styleRuns: [[StyleRun]]

    public private(set) var width: Int
    public private(set) var linesAreUniformWidth: Bool
    public private(set) var lineWidths: [Int]?

    public var overlays: [OverlayLayer] = []          // UNCHANGED
    public var hitTestRegions: [HitTestRegion] = []   // UNCHANGED
}
```

### 2.2 Why cells, not character indices

The decisive coordinate choice is **cells**. `start`/`length` count terminal
columns, so all style-interval math — shift, clip, splice, background fill —
is plain integer interval arithmetic that is **cells-not-characters correct by
construction** and never touches the grapheme content. A width-2 grapheme at
column `c` occupies columns `c` and `c+1`; a run styling it has `length` ≥ 2
and there is **no separate continuation marker** in the sidecar — the
continuation is recovered from the *text's* grapheme walk when it matters (at a
splice, or at encode). The text is still stored as graphemes and still needs a
width walk to map column ↔ char-index at a splice; but the *style* metadata is
fully cell-addressed and never re-derives width from escapes.

### 2.3 The normalization invariant

Each line's `[StyleRun]` is kept **normalized**: sorted by `start`,
non-overlapping, adjacent-equal-style runs merged, zero-length runs dropped,
and gaps between runs meaning "default style". Normalization is mandatory and
cheap. It (a) keeps run counts minimal — memory and encode speed — and (b)
makes `==` canonical, so the render/measure memo still works: two buffers are
equal iff same `text` + same normalized `styleRuns` + same `overlays` +
`hitTestRegions`. This is **self-contained** — no external table to consult, so
value/COW semantics hold and cross-frame memo stability is preserved.

`Equatable` extends today's contract (`lines == overlays == hitTestRegions ==`)
to `text == styleRuns == overlays == hitTestRegions`. `width` /
`linesAreUniformWidth` / `lineWidths` remain excluded as pure-function-of-text
perf hints. **Note:** color-only changes now correctly break equality — as they
already do today, because color lives in the string.

### 2.4 Why by-value, no interning

A frame builds hundreds–thousands of transient COW buffers (~123 buffer
constructions/frame in the profiled trees). By-value runs mean copying a buffer
is two POD-array retains with **no shared state**: no frame-scoped intern
table, no ID remapping on combine, no lifetime coupling between a buffer and a
class it depends on. Interning (Approach B) is the only way to beat by-value on
memory, but it reintroduces a shared table that would be a singleton unless
scoped onto `TUIContext` (as `RenderCache` was), and it breaks self-contained
buffers. At ~1.3–1.5× inline-string memory, by-value is cheap enough that
interning is deferred to a measured, later optimization (§8).

### 2.5 ANSI generated once, parsed never

`text[row]` stays plain. ANSI is materialized **only** at flush, in a new
encode pass that walks `styleRuns[row]` and emits an SGR at each run boundary
(the same shape as upstream's `TerminalStyle.ansiSequence` /
`ansiEncoded`). `FrameDiffWriter` diffs structurally on `(text, styleRuns)` and
encodes only changed rows, preserving today's unchanged-row skip. Nothing
downstream parses ANSI; the whole `ansiSegments` / `forEachVisibleANSIRun`
scanner leaves the layout path.

---

## 3. How every operation works under it

For each op: the new mechanism, then the ANSI-string surgery it replaces.

### 3.1 Width (`strippedLength` / `width` / `measure`)

**New:** `width(ofLine:)` is the existing grapheme walk (`visibleRunWidth` /
per-`Character` `terminalWidth`), but because every line is now plain it
*always* takes the byte/ASCII fast path — the ESC state machine
(`forEachVisibleANSIRun`) never runs. Width is **decoupled from style**:
changing a run never invalidates `width`/`lineWidths` (today a restyle rewrites
the string and `didSet → recomputeWidth()` drops the caches).

**Deletes:** the styled branch of `strippedLength`; every downstream
`strippedLength` call (83 sites) drops to the fast path. `linesAreUniformWidth`
and `lineWidths` ride along exactly as today, populated by producers (`Text`
from word-wrap).

### 3.2 Clip (`clamped(toWidth:height:)`)

**New:** *text* — grapheme-walk counting cells to the cut, slice, drop-and-pad
a straddling wide glyph (same rule as today, with **no** ANSI parsing
interleaved). *runs* — clamp each run to `[0, resultWidth)`: drop runs past the
cut, shorten a straddling run's `length`. O(runs) integer math, binary-search
to the cut column.

**Replaces:** `clamped` today calls `strippedLength` per line and
`ansiAwarePrefix(visibleCount:)` (FrameBuffer.swift:587), which runs
`ansiSegments` — a per-scalar ESC classifier — on every over-wide line.

### 3.3 Composite / insert-overlay (`composited(with:at:)` / `insertOverlay`)

This is the cleanest win. Base `(B, Rb)` + overlay `(O, Ro)` at column `x`,
`overlayW = width(O)`:

1. `text = Bprefix(0..<x) + straddle-pad + O + Bsuffix(dropping x+overlayW)`
2. `runs = Rb ∩ [0, x)  ∪  (Ro shifted by +x)  ∪  Rb ∩ [x+overlayW, ∞)`; normalize.

The base run past the overlay simply **keeps its `CellStyle`**. The entire
`ansiStateBefore` + reset + "restore active SGR" dance in `insertOverlay`
(FrameBuffer.swift:767–818) — and the class of bugs where an underline or
background bled onto the suffix — **disappears**. Compositing becomes interval
arithmetic.

**Replaces:** `insertOverlay`'s `ansiAwarePrefixWithWidth` +
`ansiAwareSuffix` + `ansiStateBefore` + the `[prefix][reset][overlay][reset +
baseStyle][suffix]` byte assembly. `composited`'s `padToVisibleWidth`
(FrameBuffer.swift:526), which today re-emits unstyled spaces that *lose* the
base's ANSI state (forcing the `originalLine` restore hack), becomes a plain
space pad — style comes from the runs, not the padded bytes.

### 3.4 Background fill (`applyPersistentBackground` / `BackgroundModifier`)

**New:** pad `text` to width with plain spaces; for each run set
`background = bg` where it is `.default`; fill the gaps *between* runs and the
trailing pad with `CellStyle(background: bg)` runs; normalize. Explicit
interval coverage.

**Replaces:** `ANSIRenderer.applyPersistentBackground` (ANSIRenderer.swift:125)
— `string.replacing(reset, with: reset + bgCode)`, the "re-apply the background
after every interior reset and hope it persists" hack, called from
`BackgroundModifier.swift:51`, `String+ANSI.swift:20`, and `BorderRenderer`.
The "background bleed above filled blocks" bug class goes with it.

### 3.5 Width query / horizontal append (`appendHorizontally`)

**New:** per row, pad left `text` to `myWidth`, then append right `text`; runs =
`leftRuns ++ rightRuns.map { $0.start += myWidth + spacing }`. The shift is an
O(runs ≈ 2) map. `linesAreUniformWidth` / `lineWidths` propagate by the same
cheap width comparisons as today (FrameBuffer.swift:456, 425).

**Replaces:** nothing structurally in the string build — the plain-row build is
byte-identical to today's optimized `asciiSpaces`-based path — but the left
pad no longer needs a per-row `strippedLength` re-measure on the ragged
fallback (it reads `lineWidths`), and the right half's style rides in runs, not
bytes.

### 3.6 Vertical append (`appendVertically`)

**New:** concat `text ++ text` and `styleRuns ++ styleRuns` (no column shift —
vertical stacking never moves columns). Spacing inserts blank `""` text rows
with empty run lists. Cheaper than today: pure array concatenation, no per-row
string rebuild.

### 3.7 Hit-test — two independent pieces, neither changed

1. **`HitTestRegion` rectangles** are produced by views and shifted by
   combining ops (`shiftedHitTestRegions`); they never read text or style, so
   they thread through **untouched**. (G5 met trivially — see §4.)
2. **Fine x→char mapping** (click-to-cursor in `TextField`/`TextEditor`) is a
   plain grapheme-width walk today and stays exactly that — orthogonal to where
   style lives.

### 3.8 Encode (new, at flush — `FrameDiffWriter.buildLine`)

**New:** `text[row] + styleRuns[row] → ANSI`, walking runs and emitting SGR at
boundaries; skip nothing (plain text is emitted verbatim between run
boundaries). ANSI is generated **once per changed row**. The per-terminal
cursor-compensation (`buildLine` at FrameDiffWriter.swift:300 —
`ansiAwarePrefixForTerminalAppWithWidth` clip, then the `isTmux`/`isAppleTerminal`
compensation branch, `repaintRightEdge`) runs on the encoded string as today,
*or* folds into the encode grapheme-walk (a minor bonus). `repaintRightEdge`'s
`ansiSGRContextAndCleanSuffix` is replaced by a direct read of the run active
at the repaint column.

---

## 4. Interop with overlays and hitTestRegions

This is the bulk of the work — not because the semantics change, but because
every combining op threads them and the re-backed ops must keep doing so
identically. They are **non-negotiable** (G5).

### 4.1 What they are

- `overlays: [OverlayLayer]` — free-floating layers composited above content at
  render time (e.g. a `Picker` drop-down), each with an offset relative to the
  buffer's top-left, shifted by every combining op until it is absolute at the
  root. Each layer *carries its own `FrameBuffer`*, which under this model
  becomes a `(text, styleRuns)` pair — no change to the threading.
- `hitTestRegions: [HitTestRegion]` — mouse hit-test rectangles in buffer
  coordinates, shifted by the same amount as the lines they ride with;
  collected by `MouseEventDispatcher` at root composite time.

### 4.2 The reconciliation contract

Both are **orthogonal to row content** — they carry cell offsets, not text or
style — so they survive every op verbatim, exactly as today:

| Op | Overlay/region handling (unchanged) |
|---|---|
| `appendVertically` | `shiftedOverlays(byX:0,y:verticalShift)` / `shiftedHitTestRegions(...)`; empty-`other` still lifts its layers (FrameBuffer.swift:288–294) |
| `appendHorizontally` | shift by `(myWidth + spacing, 0)`; empty-`other` lifts by `(priorWidth, 0)` |
| `composited(with:at:)` | keep self's layers; lift overlay's shifted by `position`; empty-overlay still lifts nested layers (FrameBuffer.swift:503–511) |
| `clamped` | carried **verbatim, never clipped** — free-floating layers composite separately at the root (FrameBuffer.swift:594–596) |
| `replacingLines` | shift by the content's move (padding insets, border `(1,1)`) |

The two helpers `shiftedOverlays(byX:y:)` (FrameBuffer.swift:614) and
`shiftedHitTestRegions(byX:y:)` (FrameBuffer.swift:670) are **untouched**. The
re-backed combining ops must call them at the same points with the same shifts;
this is mechanical but must be verified line-for-line (it is the single largest
correctness risk in the migration, §9).

### 4.3 `replacingLines`

`replacingLines(_:width:uniformWidth:lineWidths:overlayShiftX:overlayShiftY:)`
(FrameBuffer.swift:635) is the "rebuild my line content from a child, carry the
shifted layers" primitive used by padding/borders/alignment. Its structured
twin must accept `styleRuns` alongside `text` (or continue to accept `lines`
via the shim during migration) and carry the shifted overlays/regions exactly
as it does now.

---

## 5. Memory and performance

### 5.1 Memory (200 × 50 = 10,000 cells)

| Model | Per-unit | Arithmetic | **Bytes/screen** | vs current | vs grid |
|---|---|---|---|---|---|
| **Current** `[String]` inline ANSI | ~230–300 B/styled line | ~260 B × 50 + headers | **~12–20 KB** | 1× | ~1/60× |
| **Cell grid** `[[TerminalCell]]` | ~96–112 B/cell (String 16+ + `TerminalStyle` ~72 + flags) | ~104 B × 10,000 + 50 row headers | **~1.0–1.1 MB** | ~60–90× | 1× |
| **Chosen (A/C2)** plain + by-value runs | text ~200 B/line + 20 B/run | (200 + 4·20 + ~48 hdr) × 50 | **~14–20 KB** | **~1.2–1.5×** | **~50–70× lighter** |
| — pathological (per-cell color) | 200 runs/line | (200·20 + 200) × 50 | ~210 KB | ~12× | still ~5× lighter |
| **B** interned plane + `.uniform` | 2 B/cell on mixed rows only | text ~12 KB + rowStyles ~0.8 KB + planes ~3 KB + shared table ~15–26 KB | **~16 KB + table** | ~parity–2× | ~20–35× |
| **D** packed cell + continuation | 6–7 B/cell + tables | 7 B × 10,000 + ~5 KB tables | **~65–75 KB** | ~3–4× | ~13–17× |

The structural point: **chosen-model cost is O(style-change density); the grid
and D cost is O(W·H) regardless of styling.** TUI chrome has very few style
transitions, so the sidecar tracks actual content. The chosen model degrades
*toward* but never past the grid even in pathological per-cell coloring; it can
never exceed it.

### 5.2 Per-frame CPU

**Wins (profile-aligned):**

- **Every `strippedLength` hits the fast path.** It is the top inclusive cost
  (~20–23%) and is slow *only* on styled lines; all lines are now plain.
  Directly attacks the hottest leaf (G4).
- **ANSI: N parses → 1 generate.** Parsed never during layout; generated once
  per changed row at flush. Deep bordered/nested layouts (the O(depth²)
  re-measure shape) benefit most.
- **Structural simplification.** Clip/composite/background become integer
  interval ops instead of ANSI-aware string surgery.

**Losses (be honest):**

- **Run bookkeeping.** Every structural op (`appendHorizontally`, stacking) now
  shifts/concats/normalizes runs in addition to moving text — work that was
  implicit in the string before. Style-dense content is roughly a wash.

**Allocation:** a combine allocates a new `[String]` (plain — *cheaper* to
build: no SGR interleaving) **plus** a parallel `[[StyleRun]]`. That second
structure is net-new allocation that today rode free inside the string. For
style-light trees the run arrays are tiny (and a shared empty-array singleton
keeps fully-default lines at zero extra allocation); for style-heavy trees they
grow. Roughly comparable, tilting to a small win when styling is sparse and a
small loss when dense.

**Neutral:** the unchanged-row diff skip is preserved (structural compare on
`text` + `styleRuns`, encode only changed rows). Cursor-compensation unchanged.

**Net:** a modest, profile-aligned CPU win concentrated exactly where the
current model is slow (measuring styled content, re-parsing ANSI up deep trees),
paid for with extra run bookkeeping on structural ops. Style-light UI (most of
it) wins clearly; style-dense UI is roughly a wash. **This thesis is exactly
what §7 measures — if it does not show in the profile, we do not ship.**

---

## 6. Migration plan

Incremental, behind the `lines: [String]` adapter, in this order. The adapter
is the migration *mechanism*, not a resting state.

**Step 0 — land the types.** Add `PackedColor`, `CellStyle`, `StyleRun` and a
normalize routine, with unit tests for the normalization invariant and a
lossless ANSI round-trip (encode ∘ ingest == identity on the SGR subset
`ANSIRenderer` emits). No `FrameBuffer` change yet.

**Step 1 — re-back `FrameBuffer`, preserving `overlays`/`hitTestRegions`.**
Store `text: [String]` + `styleRuns: [[StyleRun]]`. Keep `lines` as a
**computed** shim: `get` = encode(text+runs)→ANSI (reusing the encode pass);
`set` = ingest-parse ANSI→(plain, runs) via the `ansiSegments` scanner. All 187
files touching `FrameBuffer` and all 56 `FrameBuffer(lines:)` producers compile
**unchanged**. `width`/`linesAreUniformWidth`/`lineWidths`/`overlays`/
`hitTestRegions` carry over verbatim. Rekey the render/measure memo and golden
snapshots to structural `(text, styleRuns)` equality (§7 correctness gate).

**Step 2 — migrate the hot combining ops** to operate on runs directly:
`composited`/`insertOverlay`, `clamped`, `appendHorizontally`,
`applyPersistentBackground`/`BackgroundModifier`. Contrast in §3; each stops
paying the ingest→encode round-trip internally.

**Step 3 — migrate the hot producers** to emit `(text, runs)` directly,
deleting the ingest round-trip at each: `Text.renderToBuffer` (already computes
`lineWidths` from wrap — add runs there), `ANSIRenderer`/`BackgroundModifier`,
`BorderRenderer`/`TrackRenderer`, the `_*Core` leaves. Confirmed against
producers: a plain `Text` line is exactly **one** run (`ANSIRenderer.render`
wraps a whole line in one leading SGR + trailing reset); multi-run rows arise
only from composition (a `Toggle` "[x] Label" with focus highlight ≈ 3–5 runs).

**Step 4 — migrate the consumer of record:** `FrameDiffWriter` — diff on
`(text, styleRuns)`, encode changed rows, run cursor-compensation on the
encoded string (or fold it in). Re-validate `repaintRightEdge` and the
per-terminal advance compensation, which currently read the raw ANSI string;
update `Documentation/Terminal-compatibility.md` (encode/CUF move to flush
time).

**Step 5 — retire the dead surface.** Delete the ANSI-state-machine family from
`String+TerminalWidth.swift` (`ansiSegments`, `forEachVisibleANSIRun`,
`ansiAwarePrefix/Suffix/Slice`, `ansiStateBefore`,
`ansiSGRContextAndCleanSuffix`, `leadingANSISequences`) once no live caller
reads styled strings. Keep the *width* half (`Character.terminalWidth`,
`visibleRunWidth`, `padToVisibleWidth`) and the whole cursor-advance /
`String+CursorCompensation` apparatus — those are orthogonal and survive.

**Step 6 — drop the shim, decide on the caches.** Delete the computed `lines`
shim; rename `text` → `lines` (now plain). Re-evaluate whether
`linesAreUniformWidth` / `lineWidths` still earn their keep now that width is
decoupled from style and always takes the fast path (they may; keep if the
profile says so).

**The gate:** per CLAUDE.md, pre-1.0 forbids permanent compat shims. **If the
realistic end state would keep the `lines` shim permanently — i.e. Steps 3–5
cannot actually land — do not start.** The shim exists to stage the diff, and
the migration must complete to a structured `main` with the shim deleted, or it
is not worth doing.

---

## 7. Measurement plan / go-no-go

**The most important section.** The owner insists on measuring runtime cost
before committing. Everything below uses tools **already committed** — no new
harness — and **release** builds throughout.

### 7.1 Two-tier A/B behind the shim

**Tier 1 — shim upper-bound (cheap, whole-suite, no migration).** With Step 1
done and `lines` a computed shim, the *entire* existing benchmark + stress +
snapshot suite runs against the prototype with **zero producer/consumer edits**
— same views, same trees, two storage backends. Be explicit: in Tier 1 the shim
pays **both** ingest-parse **and** flush-encode every frame, so it is a
deliberate **worst-case upper bound** on CPU. If the prototype clears the
thresholds *while double-paying*, the migrated end state (which deletes both
round-trips) can only be better. If Tier 1 is far over, time the parse and
encode costs separately before concluding.

**Tier 2 — one-pair true cost.** Migrate exactly **one** hot producer+consumer
pair off the shim: `Text.renderToBuffer` emits runs directly (no ingest) and
`FrameDiffWriter` diffs/encodes runs directly (no round-trip). Re-run the
`FrameBuffer` micro-benchmarks + `textwall`/`megalist`. This is the **true,
no-shim** delta on the dominant path, at a fraction of a full migration. Tier 1
bounds the downside; Tier 2 reveals the upside.

**Data-model memory microbench.** Construct the three reference 200×50 frames —
(i) plain, (ii) lightly styled ~4 runs/line, (iii) truecolor-Image worst case —
in current vs chosen vs B vs D representations and measure
`.peakMemoryResident` directly, validating §5.1's arithmetic empirically. This
is where the escalation-to-B trigger is checked.

### 7.2 Harnesses → scenarios → what they prove

| Harness (committed) | Invocation | Scenarios | Proves |
|---|---|---|---|
| **`Benchmarks/TUIkitBenchmarks`** (ordo-one) | `swift package benchmark` (baselines in `.benchmarkBaselines/`) | `FrameBufferBenchmarks` covers exactly the combine ops: `init(lines:)` width *plain 50×120* + *ANSI 50×110*, `appendVertically ×50`, `appendHorizontally two 50×120`, `composited overlay at (5,10)`, `clamped to 80×24`; plus `render/*`, `layout/*`, `list/*` | **Primary A/B engine.** Metrics already configured in `Benchmarks.swift`: `.cpuTotal, .wallClock, .mallocCountTotal, .peakMemoryResident` — the owner's *wall-clock/frame, bytes-allocated/frame, peak RSS* out of the box |
| **`Stress --bench`** | `swift run -c release Stress -- --bench --scenario <id> --iterations N [--cold]` → per-frame µs + checksum | `megalist, table, table-multiline, tables-scroll, tables-vstack, deep, fanout, modifiers, textwall, anyview, dashboard, framedcolumns, churn, kitchensink` | App-shaped per-frame wall; **cold** (worst-case fresh state/cache) vs **warm** (steady state). Seeded → byte-identical trees across A and B |
| **`Tools/Profiling`** Time Profiler | `record.sh <scenario>` (Mode B, PTY) or `xctrace --launch` on `Stress --bench` (Mode A, no attach) → `analyze_timeprofile.py` | `tour, list, table, emoji, scroll`; FrameBuffer micro trees | **Central CPU thesis check** (§7.4): `strippedLength` / `forEachVisibleANSIRun` / `ansiAware*` inclusive share must collapse |
| **`Tools/Profiling/idle_cpu.py`** | `idle_cpu.py BIN [settle] [window] [keys]` | any static screen | **Hard idle gate** — flush-encode must stay diff-gated to changed rows |
| **Golden snapshots** (`Tests/TUIkitTests/__Snapshots__`) | `swift test` (record with `TUIKIT_RECORD_SNAPSHOTS=1`) | full corpus | **Correctness gate** — rekey to structural `(text, styleRuns)` equality |

### 7.3 Metrics (mapped to the owner's words)

- **bytes allocated / frame** → ordo `.mallocCountTotal`/iteration (canary: the
  `Text("OK")` / tiny-leaf population, §7.4). Cross-check with Instruments
  Allocations on a `Stress --bench` run if ambiguous.
- **wall-clock / frame** → ordo `.wallClock` (statistical, with baseline) **and**
  `Stress --bench` per-frame µs (app-shaped, cold+warm).
- **peak RSS** → ordo `.peakMemoryResident` on the heavy scenarios + the §7.1
  data-model microbench.

### 7.4 Numeric go / no-go thresholds

**MEMORY — GO if:** the 200×50 styled frame stays ≤ **~30 KB** (few×strings,
nowhere near the grid) **and** `.peakMemoryResident` on `kitchensink`,
`dashboard`, `megalist`-at-scale, and one truecolor-Image screen is ≤ **1.5×**
current.
**MEMORY — NO-GO / escalate-to-B if:** peak RSS > **2×** current on any
realistic scenario, **or** a truecolor Image frame blows run density past
**~250 KB/screen** (approaching the grid → defeats G2). *This is the specific
trigger to switch to Approach B's interned plane.*

**CPU — GO if:** warm per-frame wall on style-light scenarios (`deep, fanout,
megalist, list, table`) is ≤ current (target: *faster*), and **no scenario
regresses > 5% warm**; composite/overlay-heavy scenarios (`dashboard,
kitchensink`, dialogs) within **±10%** (style-dense wash accepted).
**CPU — NO-GO if:** the central thesis fails to show — combined inclusive share
of `strippedLength` + `forEachVisibleANSIRun` + `ansiAware*` does **not** fall
from its current ~20%+ toward **< 5%** on `emoji`/`textwall`. If those do not
nearly vanish from the layout path, the CPU rationale is false and this is not
worth the churn.

**ALLOCATION — GO if:** `.mallocCountTotal`/frame does **not** increase on
style-light scenarios — the empty-runs singleton / small-array inline path keeps
tiny leaves at ±0 (the `Text("OK")` canary). **NO-GO if:** it regresses > **15%**
on `megalist`/`fanout`: the sidecar is adding a per-buffer heap allocation the
inline-string model avoided — a direct hit to the many-transient-COW-buffers
budget.

**IDLE — hard gate (any regression = NO-GO):** `idle_cpu.py` on a static screen
stays **~0% CPU / 0 B/s**. The flush encode must be strictly diff-gated to
changed rows; re-encoding static content reintroduces the idle churn the
demand-driven animation clocks eliminated.

**CORRECTNESS — hard gate:** golden snapshots pass after rekeying to structural
equality; terminal output byte-identical **or** a *reviewed, intended* diff
(synth SGR coalescing may differ from hand-written bytes — expected, reviewed,
not asserted-equal). Re-validate `FrameDiffWriter.repaintRightEdge` + the
per-terminal cursor-advance compensation; update
`Documentation/Terminal-compatibility.md`.

### 7.5 Decision rule

Commit **iff** all four hard gates (idle, correctness, and the CPU-thesis
profile drop) pass **and** MEMORY-GO and ALLOCATION-GO hold across the stress
set. If MEMORY fails specifically on Image/style-dense frames → escalate to **B**
and re-run the same battery. If the CPU thesis fails to materialize → **stop**;
the consolidation is not worth the migration and rekey. Everything is measured
behind the shim *before* a single producer is permanently rewritten.

---

## 8. Alternatives considered

| Model | What it is | Why it lost for us |
|---|---|---|
| **Cell grid** `[[TerminalCell]]` (upstream `issue/11-terminal-cell-surface`) | AoS: each cell a `TerminalCell` (Content + `TerminalStyle` + flags), continuation cells for wide glyphs | ~1 MB/screen, O(W·H) regardless of styling — directly violates G2. Its one advantage (model-level wide-char correctness) is **moot for us** (§1.2). Disqualified on memory. |
| **B — interned style plane** | plain text + per-cell `StyleID: UInt16` plane, deduped through a frame-scoped `StyleTable` (TUIContext-owned, RenderCache-style), with a load-bearing `.uniform(StyleID)` fast path | Genuinely lighter (2 B/cell) on style-dense frames, but adds a **shared intern table** (buffers stop being self-contained), a fast path without which every tiny transient buffer gains a heap alloc, and an Image opt-out (UInt16 caps at 65,536 styles/frame). More machinery for a memory win we likely do not need. **Held as the documented fallback** if §7.4's memory trigger fires. |
| **D — columnar SoA cell surface** | 3 flat planes (glyphs `UInt32`, styles `UInt16`, kinds `UInt8`) + interned styles + a continuation plane; O(1) width | Model-level wide-char correctness — the benefit we already banked — at ~3–4× string memory and 3 allocations per buffer (over-allocs the numerous tiny/blank leaves). Taxes `appendVertically`, currently our *cheapest* op (re-strides unequal widths). SoA buys cache density but not vectorization here (our passes read glyph+style+kind together). Paying memory for a banked benefit is the worst trade on the board. |
| **C1 — "the lipstick"** | keep inline ANSI as source of truth; lazily memoize the parsed (plain, spans, widths) | Caches *around* inline metadata rather than removing it. Fails G1 by construction — "lipstick," as its own author conceded — and adds cache-coherence surface (the same reason `lineWidths` drops to `nil` on every mutation, multiplied). Excluded. |
| **Current `[String]`** | inline ANSI | The status quo we are leaving; violates G1. |

---

## 9. Risks and open questions

**Risks**

- **Two structures in lockstep.** `text` and `styleRuns` must stay consistent
  under a normalization invariant; get it wrong and equality/memo silently
  misbehaves. More moving parts than either self-describing alternative.
  Mitigation: a single `normalize()` chokepoint + debug asserts (mirroring
  `assertLineWidthsInvariant`, FrameBuffer.swift:697), and structural-equality
  snapshot coverage.
- **Overlay/hitTest threading regressions.** The re-backed combining ops must
  call `shiftedOverlays`/`shiftedHitTestRegions` at the same points with the
  same shifts (§4.2). This is the largest correctness risk. Mitigation:
  port op-by-op with the existing overlay/hit-test tests green at each step;
  the empty-`other` layer-lift edge cases (FrameBuffer.swift:288, 384, 503) are
  the easiest to drop.
- **Lossless SGR round-trip during migration.** The shim's `set` must parse
  every SGR `ANSIRenderer` can emit; anything unmodeled is lost on round-trip.
  Tractable — TUIkit owns its `ANSIRenderer` — but must be audited (256/truecolor,
  all 8 attributes) and OSC/hyperlinks explicitly handled or excluded. The
  Step 0 round-trip test is the guard.
- **Snapshot / memo rekey.** Synth SGR coalescing is not guaranteed
  byte-identical to today's hand-written escapes; any test asserting exact
  escape bytes must rekey to structural comparison (§7.4 correctness gate).
- **Style-dense reality.** If real apps produce more runs/line than the ~1–5
  assumed (heavy syntax highlighting, gradients, truecolor images), CPU and
  memory tilt toward a wash / the B trigger. §7 measures this directly rather
  than assuming.

**Open questions**

1. **`PackedColor` layout.** 2-bit tag + 30-bit payload is enough for
   ansi16/indexed256/rgb; confirm the rgb packing (24-bit) and the
   semantic-color case — `Color.resolve` is transitive (palette slots can hold
   semantic refs), so decide whether runs store *resolved* colors only (encode
   resolves) or may hold a semantic ref (adds a tag state). Resolved-only is
   simpler and matches the flush-time encode.
2. **Where does resolution happen?** If runs hold resolved colors, the leaf
   producer resolves at render time (as today); if deferred, encode needs the
   palette. Recommend resolved-at-produce to keep encode a pure function of
   `(text, runs)`.
3. **`Int32` vs `UInt16` for `start`/`length`.** `Int32` is generous and keeps
   arithmetic branch-free; a terminal is never 2^31 wide. `UInt16` halves
   `StyleRun` to ~14 B but reintroduces width-cap edge cases. Default `Int32`
   pending the memory microbench.
4. **Keep `linesAreUniformWidth` / `lineWidths`?** Width is now decoupled from
   style and always fast-path; these caches may no longer earn their keep.
   Decide in Step 6 from the profile, not upfront.
5. **Fold cursor-compensation into encode, or keep it post-encode?** Folding it
   into the encode grapheme-walk is a minor CPU bonus but couples two concerns;
   keep them separate unless the profile argues otherwise. Coordinate with
   `Documentation/Terminal-compatibility.md`.
