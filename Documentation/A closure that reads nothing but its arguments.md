# A closure that reads nothing but its arguments

*A feature request for Swift, written from one framework's measurements.
Drafted 2026-09-22 against Apple Swift 6.2.4 (`swift-6.2.4-RELEASE`,
`arm64-apple-macosx15.0`, `+assertions`). Every claim below about what the
compiler does today was compiled and run; the programs are short enough to be
reproduced from the listings.*

## The ask, in one sentence

Swift can already tell, from a bare closure literal's body, whether it throws —
and that answer participates in overload resolution, with graceful fallback.
We would like the same treatment for one more question: **does this function
read anything other than its arguments?**

---

## 1. Why a framework wants to know

TUIkit is a terminal UI framework with a SwiftUI-shaped API. Its `Table`
composes each drawn row from its columns every frame, and a scrolled,
frequently-updating table redraws rows whose text has not changed. So `Table`
memoises composed rows across frames. The memo has two tiers, and which tier a
table gets is decided entirely by which initialiser its columns were written
with:

```swift
TableColumn("Name", value: \.name)                                   // tier 1
TableColumn("Size", value: \.byteCount) { "\($0.byteCount.formatted(.byteCount(style: .file)))" }
                                                                     // tier 2
```

**Tier 1 — row-equal.** Every column names a `KeyPath<Value, String>`. The
cells are a pure function of the row, so an unchanged row means unchanged text
and the memo serves the kept line without reading a single property.

**Tier 2 — cell-compare.** Any column computes its value with a closure. The
closure may capture a search term, a `DateFormatter`, a units toggle; it may
read a global; it may read the clock. An equal row therefore proves nothing
about its text. The only sound test is to **run every closure for every drawn
row on every frame** and compare what came out. That is correct, and it is the
part nobody can skip — the memo can only save what comes *after* the closures.

The second initialiser is not exotic. It is the one you are obliged to use
whenever the display form differs from the sort form: a size shown as `4.2 KB`
that sorts by its `Int` byte count, a date shown formatted that sorts
chronologically. In our `file-browser` benchmark — 36 drawn rows, two such
columns — running those closures to discover that nothing changed is **18.6% of
the frame**, essentially all of it inside `Int.formatted(.byteCount)` and
`Date.formatted`.

The information that would eliminate it is *already in the source*. In

```swift
TableColumn("Size", value: \.byteCount) { "\($0.byteCount.formatted(.byteCount(style: .file)))" }
```

the closure reads nothing but `$0`. The compiler can see that. The framework
cannot, so it pays 18.6% of every frame to re-derive it.

This is not a niche shape. It is the general problem of **an API that can
memoise its caller's work, if only it knew the caller's work was a function of
what it was handed.** `map` on a lazily-recomputed collection, a diffing UI
framework, a dependency-tracking build system, an incremental parser and a
render cache all want the same fact.

## 2. The property we need is not any of the ones Swift has

The property is: *given equal arguments, this function returns an equal result,
for as long as the memo lives.* Equivalently, the result is determined by the
arguments alone.

It is worth being exact about what that is **not**, because three existing
features look like it and none of them is:

**It is not "captures nothing".** Globals are not captures in Swift. All four
of these compile as `@Sendable (Row) -> String` in Swift 6 language mode; the
first three capture nothing at all and not one of them is usable for the memo:

```swift
nonisolated(unsafe) var callCount = 0

let clock:     @Sendable (Row) -> String = { _ in "\(Date())" }
let bump:      @Sendable (Row) -> String = { r in callCount += 1; return r.name }
let formatted: @Sendable (Row) -> String = { $0.bytes.formatted(.byteCount(style: .file)) }
let search:    @Sendable (Row) -> String = { $0.name.contains(term) ? "hit" : "-" }  // captures `term`
```

Running it prints a live timestamp, a mutated counter, `4 kB`, and `hit`. Any
mechanism built on "this closure has an empty capture list" — the direction
`@convention(c)` and `@convention(thin)` point in — admits the first three
through the front door.

The fourth line matters too, in the other direction: `search` is pure in the
mathematical sense, and still wrong for this memo, because the framework holds a
kept line across frames and has no way to notice the day `term` changes. What we
need is stricter than mathematical purity: *determined by the arguments*, which
means reading no captured mutable state **and** no captured state the caller can
change between frames.

**It is not `@Sendable`.** `@Sendable` is genuinely part of a function type
(SE-0302), which is the right shape — but its subject is data-race safety, not
determinism. A closure capturing `let searchTerm: String` is perfectly
`@Sendable`: that is exactly our impure case. And it over-rejects in the other
direction: a closure capturing a `DateFormatter` is a hard error, though its
output may well be a pure function of the row.

**It is not `@const` / SE-0359.** That is about values known at *compile time*,
not about side-effect freedom. On 6.2.4 with
`-enable-experimental-feature CompileTimeValues`, `@const` on a function-typed
parameter compiles and **enforces nothing**: a closure that mutates a global, one
that reads the clock and one that captures a local all pass. And two
initialisers differing only by `@const` are `error: ambiguous use of
'init(_:f:)'` at every call site — the attribute does not participate in
overload resolution.

**It is not `@_effects(readnone)`.** The closest thing the compiler has is
reserved to the Swift repository, and for good reason. It is a *declaration*
attribute and cannot appear in a type at all —

```
error: attribute can only be applied to declarations, not types
```

— so it cannot constrain a parameter, cannot discriminate overloads, and is
dropped at the `(Row) -> String` boundary when an annotated `func` is passed as
a value. It is also entirely **unchecked**: it is a promise to the optimiser,
not a claim the compiler verifies. Its own reference guide says usage outside
the Swift monorepo is strongly discouraged, and the historical record of what
went wrong when the standard library leaned on it is not encouraging. A
framework cannot build a correctness-critical cache on an unchecked promise; a
wrong one shows up as a cell displaying last frame's value, which is a worse
defect than a slow frame.

## 3. Swift already does exactly this — for `throws`

This is the part that makes the request modest rather than sweeping. Swift
already infers an effect from a bare closure literal's body, already makes it
part of the function type, and already lets it select an overload with graceful
fallback. Here it is:

```swift
struct E: Error {}
struct Col {
    var which: String
    init(_ t: String, f: @escaping () -> String)        { which = "non-throwing overload" }
    init(_ t: String, f: @escaping () throws -> String) { which = "throwing overload" }
}

print(Col("a") { "x" }.which)         // non-throwing overload
print(Col("b") { throw E() }.which)   // throwing overload
```

No annotation at the call site. No `@_disfavoredOverload`. No ambiguity. The
compiler reads the body, decides, and picks the specialised overload when it
can. It is transitive, too — a literal that calls a throwing function selects
the throwing overload, and one that wraps the same call in `try!` selects the
non-throwing one:

```swift
func risky(_ r: Row) throws -> String { throw E() }
Col("c", f: { try! risky($0) })   // non-throwing
Col("d", f: { try  risky($0) })   // throwing
```

**This is the entire mechanism we are asking for, applied to a different
effect.** The precedent is not hypothetical or partial: it ships, it is
inferred, it is transitive, it discriminates overloads, and `rethrows` exists
for forwarding it through higher-order functions.

For completeness, the *attribute*-shaped half of the mechanism also already
works, in Swift 6 language mode. Two initialisers differing only by a
global-actor qualification on the closure parameter are legal (SE-0316 makes
global-actor qualification part of the function type; SE-0431 does the same for
`@isolated(any)`), and they dispatch correctly:

```swift
init(_ t: String, f: @escaping @MainActor (Row) -> String)  // "MainActor overload"
init(_ t: String, f: @escaping (Row) -> String)             // "plain overload"

Col("a", f: { $0.name })                            // plain overload      ← the gap
let m: @MainActor (Row) -> String = { $0.name }
Col("b", f: m)                                      // MainActor overload
let p: (Row) -> String = { $0.name }
Col("c", f: p)                                      // plain overload
```

(In Swift 5 language mode the two declarations are `error: invalid
redeclaration of 'init(_:f:)'`; this works only under `-swift-version 6`.)

The gap is the first line, and it is the whole ergonomic question. A *type
attribute* on a parameter does not make a bare literal infer into it — the
literal's type is driven by context, and context offers both. An *effect*, like
`throws`, is inferred from the body and therefore does. For an API like
`TableColumn`, where the closure is written as a trailing closure at the call
site and the caller should not have to annotate anything, only the effect-shaped
answer is usable.

## 4. Sketch

We are not proposing spelling or syntax; that is the review's job. The shape we
need, in the terms the language already uses:

**An effect, inferred from the body, written in the effects position.**
Provisionally `pure` (as `throws` and `async` are written), so that
`(Row) -> String` and `(Row) pure -> String` are distinct function types and the
second is a subtype of the first. A declaration may state it; a closure literal
never has to.

**Inference.** A function is `pure` when its body reads no storage outside its
parameters and its own locals, and calls only `pure` functions. Concretely, the
rejected reads are: a global or static `var`; a captured `var`; any property or
subscript access through a captured reference; any call to a non-`pure`
function, including anything that reads the clock, the file system, the
environment or a random source. Captured `let`s of value type are the
interesting boundary — see the open questions.

**Overload resolution.** A `pure` parameter is preferred when the argument
satisfies it and falls back to the general overload when it does not, exactly as
the `throws` pair above does. Notably *not* what `@convention(c)` does today,
which wins the overload and then hard-errors rather than falling back.

**Forwarding.** A `rethrows`-analogue, so `map`-shaped functions can be `pure`
exactly when their function argument is.

**An escape hatch.** Something in the spirit of `try!` — a way to say "I have
read this body and I promise", for the cases where the checker is conservative
(a memoised computed property, a lazily-initialised constant table, an
`os_log` in a debug build). Unchecked promises must be *opt-in and visible at
the promise site*, which is the difference between this and `@_effects`.

## 5. Open questions we cannot answer ourselves

These are the objections we would expect, and we do not think any of them is
fatal, but they are real:

1. **Virality.** Like `throws`, this colours the world: to call anything from a
   `pure` function it too must be `pure`, and a standard library that is not
   annotated makes the feature useless on day one. `throws` had the same problem
   and solved it by defaulting the other way — everything is impure unless
   stated — but the standard library would still need a meaningful annotated
   surface for the feature to be worth having. How large is that surface? Is
   `Int.formatted(_:)` pure? (It reads the current locale, so: no — which is a
   *correct* answer that would have caught a real bug class, and also means the
   TUIkit example above would not be `pure` as written. That is informative
   rather than disqualifying: the framework would then know to fall back, which
   is exactly right.)
2. **What counts as a read.** A captured `let String` is immutable and its
   value is fixed at capture time — but the closure *value* changes when the
   capture does, which is what our memo needs to notice. Is the right rule "no
   captures at all", "captures must be `let` of `Equatable` value type and are
   part of the closure's identity", or something else? The second would be more
   useful to us and much harder to specify.
3. **Dynamic dispatch and resilience.** A `pure` requirement on a protocol
   witness, a `pure` override, a `pure` function across a module boundary in a
   resilient library — all need rules, and all of them are places where an
   unchecked promise could leak in.
4. **Is it checkable at reasonable cost?** The checker needs to know, for every
   call in the body, whether the callee is `pure`. That is the same question
   `throws` already answers, so we expect the answer is yes, but we have not
   implemented it.
5. **Does it need to be a language feature at all?** A macro can inspect a
   closure's *syntax*, but macros have no name lookup: a macro cannot tell a
   global from a local, or see through a call. It can only be conservative to
   the point of uselessness. We do not see a library-level answer.

## 6. What we are doing meanwhile

Nothing in this document is blocking us; we are describing a cost, not an
outage. The options that ship today, all of which put the burden on the caller
rather than the compiler:

- **Hand over the dependencies instead of proving their absence.** A modifier —
  `.columnContentDepends(on: someHashable)` — folded into the memo key. This
  fits the framework's modifier-first API rule and is the likeliest thing we
  will do. It is also a promise, unchecked, made at a different place from the
  closure it is about.
- **Reify the transform as an `Equatable` value type** rather than a closure, so
  the framework can compare it. Correct, and a considerable ergonomic
  regression at every call site.
- **Do nothing and pay the 18.6%.** Which is where we are.

What none of these can do is what the compiler could do for free: read the
closure, see that it touches nothing but `$0`, and say so.

---

### Reproducing the claims

Every program above is self-contained. Compile with
`swiftc -swift-version 6 -parse-as-library <file>.swift` (the language mode
matters: several of these behave differently under `-swift-version 5`, and the
`@MainActor` overload pair does not compile there at all). `@const` needs
`-enable-experimental-feature CompileTimeValues`; note that unknown feature
names are accepted silently by 6.2.4, so "it compiled with the flag" is not on
its own evidence that the feature was enabled.

### For TUIkit readers

The memo this is about is `Sources/TUIkit/Views/TableRowMemo.swift`, the two
tiers are `TableRowMemoStore.namesItsValues` and the cell comparison in
`Table.renderRow`, and the flag that decides them is
`TableColumn.namesAProperty`. If Swift ever grows the effect described here,
`namesAProperty` becomes "every column's value extractor is `pure`" and the
key-path special case stops being a special case.
