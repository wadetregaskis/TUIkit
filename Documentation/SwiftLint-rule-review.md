# SwiftLint: what we enforce, and every optional rule we don't

**CI pins SwiftLint 0.65.1 since 2026-09-28, and Part 3 (before the summary)
reviews what changed since the 0.63.2 pin.** Six rules are new — all of them
from 0.63.3; 0.64.x and 0.65.x added none — and one of them is now enabled.
Part 3 also covers every changed default or behaviour of an existing rule.
Both lists come from diffing `swiftlint rules` and `swiftlint rules
--default-config` between the two binaries, not only from the changelog.

Parts 1 and 2 are the original review. Their counts are as of 2026-08-25
(1,094 files); most have grown with the tree (1,736 files on 2026-09-28),
but the verdicts turn on the *shape* of the sites, not the totals.

**Reviewed 2026-08-25 against SwiftLint 0.63.2** (then the CI-pinned version), by
rolling each existing exception back one at a time and by measuring every
opt-in rule against the whole tree. Counts below are real: each rule was run
over `Sources` + `Tests` (1,094 files) and the violations counted, so
"decline" never means "looks noisy" — it means *this many sites, and here is
why they are right as they are*.

Two project rules outrank the linter throughout, and several verdicts turn on
them: **SwiftUI API parity** (public signatures must match SwiftUI's) and
**swift-format owns formatting** (`.swift-format` is committed and run).

## Part 1 — the existing exceptions, re-examined

### Rolled back (now enforced)

| Was | Now | Why it was safe |
|---|---|---|
| `nesting` disabled | `nesting: type_level: 2` | Its 6 hits are all SwiftUI-parity shapes (`OpenURLAction.Result.Disposition`, `TimelineView.Context.Cadence`). Depth 3 still warns, so the rule has teeth again. |
| `type_name` + ~90 enumerated exclusions | `allowed_symbols: ["_"]` | Every entry was a `_`-prefixed core/helper — the project's SwiftUI-style convention. Length limits still apply. Config −137 lines, and 4 inconsistent `swiftlint:disable:this type_name` pragmas deleted. |
| `fatal_error_message` "disabled" | opted in | It is an **opt-in** rule, so listing it under `disabled_rules` never did anything. Enabling it for real found exactly one bare `fatalError()` in a test helper, now fixed. |

### Kept, with the reason verified rather than assumed

| Rule | Sites | Why it stays off |
|---|---|---|
| `trailing_comma` | 450 | `.swift-format` sets `multiElementCollectionTrailingCommas: true`. Enabling makes the two tools rewrite each other forever. |
| `opening_brace` | 161 | Same conflict, via `lineBreakBeforeEachArgument: true`. |
| `type_body_length` | 75 | `file_length` already bounds the same thing at the granularity this project actually splits on. The two worst (`_TableCore` 1589, `_ListCore` 1500) are deliberate cohesive cores. |
| `discouraged_none_name` | 14 | All public `.none` API mirrored from SwiftUI (`BorderStyle`, `SymbolVariants`, `Scrollbar`, …). Parity outranks it. Also was dead config — it is opt-in. |
| `identifier_name.excluded` | 935 without it | Dominated by `x`/`y` coordinates and `i` loop indices. Renaming those makes the render maths *less* readable. |

### The numeric limits: already ratchets

Every limit sits **exactly at the codebase's current high-water mark**, so
nothing can grow past today without a deliberate config change. Tightening
further is real refactoring, priced here so the choice is informed:

| Limit | Current | Max in tree | Cost to tighten |
|---|---|---|---|
| `line_length` | 160 | 158 | → 140: 14 sites; → 120: 215 |
| `file_length` | 600 | 599 | → 500: 27 files; → 400: 59 |
| `function_body_length` | 100 | 100 | → 90: 19 functions |
| `function_parameter_count` | 8 | 8 | → 7: 16 functions |
| `cyclomatic_complexity` | 15 | 15 | → 13: 19 functions |
| `large_tuple` | 6 | 6 | → 5: 2 sites (both labelled, documented return tuples) |

### In-file suppressions (46)

Sampled and sound: they are narrow (`:next` / `:this`), documented at the point
of use, and mostly genuine rule misfires — `empty_count` on a stored `Int`
that *is* the definition of `isEmpty`; `unused_setter_value` on
`EmptyAnimatableData`, which has nothing to store; `redundant_discardable_let`
on `let _ = …` used for a side effect inside a `@ViewBuilder`. The 14 on
generated files waive only `line_length`/`file_length` while leaving every
other rule enforced, which is stricter than adding the directory to
`excluded:` — so that stays as it is too.

### The two `file_length` suppressions, evaluated

`Table.swift` (3,197 lines) and `_ListCore.swift` (2,754) suppress
`file_length` outright, against a project convention of ~500, so they were
examined as split candidates in the mould of the `ItemListHandler` /
`ContainerViewCore` / `ScrollView+Content` splits already done.

**Conclusion: do not split them.** Swift's `private` is file-scoped, so moving
any part of one of these cores into a second file widens everything the two
halves share. Measured:

| | `_TableCore` | `_ListCore` | `_ScrollViewCore` (the precedent that *was* split) |
|---|---|---|---|
| explicitly `private` members | 43 | 41 | 9 |
| members crossing the seam | see below | — | ~4–8 |

The ScrollView split worked because its seams are genuinely separable
concerns — content extents, scrollbars, reveal, anchor — so only a handful of
members had to become module-visible. These two have no such seam: their
sections are sequential stages of one pipeline (window → compose → clip →
publish bands) reading the same stored state. Probing the most
self-contained-looking candidate, the ~450-line mouse-wiring section of
`_TableCore`, it still reaches **9 private helpers and 6 stored properties**,
several of them (`floatCarriedRows`, `previewRow`,
`registerRowDropDestination`) belonging to the reorder and render paths.

So the cost of a split is converting most of ~43 intricate,
deliberately-private helpers into module-visible surface, in the two files
whose invariants are hardest to hold (measure/render parity, windowing,
mouse-region mapping). That is a real loss of the compiler-enforced guarantee
that only this file can call them — paid for a line count. `Table.swift`'s own
header already recorded this judgement before the review; it is now measured
rather than asserted.

The one genuinely cheap move available is lifting the public `Table` API
(~360 lines) away from `_TableCore` into a sibling `TableCore.swift`, matching
`List`/`_ListCore` and `ContainerView`/`ContainerViewCore`. It costs one
access level on an already-underscored type — but it leaves a 2,800-line core
still suppressed, so it buys consistency rather than a smaller file. Left for
a moment when someone is touching that file anyway.

## Part 2 — every optional rule not enabled (109)

As of 0.63.2, once Part 1 had enabled `fatal_error_message`: the 108 rules
below, plus `discouraged_none_name` in Part 1. (Until 2026-09-28 the lists
below held 107: `private_subject` was in none of them.) The four opt-in rules
0.63.3 added are reviewed in Part 3.

### `file_header` — enabled, and it was never doing anything

The rule checks **nothing** until it is given a `required_pattern`, so its
"zero violations" meant "inert", not "clean". It is now configured (see
`.swiftlint.yml` for the pattern and what it deliberately does not pin), and
enabling it found 21 real defects: two headers naming a *different* file,
18 with no `Created by`, and one with no licence line. Verified adversarially
against ten hand-built bad headers — it flags nine and accepts only the valid
one.

### Enabled by this review — zero violations, genuinely applicable (9)

| Rule | Verdict |
|---|---|
| `unavailable_function` | Marks stub functions `@available(*, unavailable)`; fits the `body: Never { fatalError(…) }` pattern used throughout. Free ratchet. |
| `untyped_error_in_catch` | Catches `catch let error` without a type; free. |
| `unhandled_throwing_task` | Real correctness guard for `Task { try … }` whose error is dropped. Free, and this codebase spawns tasks. |
| `optional_enum_case_matching` | Prevents `case .foo?` drift in optional switches; free. |
| `static_operator` | Operators declared static; free. |
| `reduce_into` | Nudges `reduce(into:)` over allocating `reduce`; free and perf-aligned. |
| `lower_acl_than_parent` | Catches `public` members of internal types; free. |
| `non_overridable_class_declaration` | Encourages `final`; free, and this project already finalises its classes. |
| `sorted_imports` | Deterministic import order — one fix (`SFSymbol.swift`), and it removes a class of pointless merge conflict. |

All nine verified at **0 violations** before enabling, so they are pure
ratchets: they cost nothing today and stop the drift tomorrow.

### Enable after a small, mechanical fix (3 — two of them since enforced)

| Rule | Sites | Verdict |
|---|---|---|
| `missing_docs` | 41 | **Recommended.** This is a public-API framework that documents heavily; 41 undocumented public declarations (Theme 8, UserDefaultsStorage 8, RadioButton 5, AppStorage 4) are gaps, not style. Fix, then it ratchets. **Taken:** `16f07698` (2026-08-25) documented all 41 and enabled it — `.swiftlint.yml:68`. |
| `direct_return` | 2 | `let x = …; return x` → `return …`. Genuinely clearer, but two sites is thin justification for a standing rule. Your call — **called: enabled** in `b08531db` (2026-08-25), the two sites fixed. `.swiftlint.yml:50`. |
| `multiline_parameters_brackets` | 3 | Cosmetic, and swift-format already owns wrapping. Marginal. |

### Decline — conflicts with a project rule or another tool (9)

| Rule | Sites | Verdict |
|---|---|---|
| `contrasted_opening_brace` | 30,235 | Directly contradicts swift-format's brace placement. Non-starter. |
| `unneeded_escaping` | 11 | All 9 framework hits are `.alert`/`.sheet`/`.popover`/`.confirmationDialog` content closures, where `@escaping` **matches SwiftUI's own signature**. Parity outranks it. |
| `prefer_key_path` | 255 | Already evaluated and rejected 2026-07-20: its autocorrect produces code that does not compile inside swift-testing's `#expect` (3,004 assertions at risk). |
| `trailing_closure` | 188 | Previously declined: explicit `make:` / `action:` labels read better than bare trailing closures in this API. |
| `force_unwrapping` | 507 | Previously declined: the framework hits are intentional present-during-render invariants (`context.environment.x!`) where fail-fast is correct. |
| `explicit_acl` / `explicit_top_level_acl` | 9,411 / 1,129 | `internal` is Swift's default and the project relies on it. Spelling it everywhere is pure noise. |
| `no_grouping_extension` | 423 | The codebase deliberately groups conformances into extensions — the pattern the `_*Core` architecture is built on. |
| `no_extension_access_modifier` | 2 | Looks trivial and is not: it would move `public` off `extension View` onto each of ~10 static witnesses in the hottest, most carefully-commented declaration block in the framework. (Worth noting swift-format's equivalent rule is enabled yet these survive, so the two tools already disagree here.) |

### Decline — wrong for this codebase (17)

| Rule | Sites | Verdict |
|---|---|---|
| `no_magic_numbers` | 21,107 | A terminal renderer is *made* of cell arithmetic. Every `- 1`, `+ 2`, `/ 2` would demand a constant. |
| `explicit_type_interface` | 20,965 | Requires a type annotation on every property — the opposite of Swift idiom and of this codebase's style. |
| `number_separator` | 16,209 (218 even at 7 digits) | The long literals are Unicode scalars and hash constants; `0x1_F600` is worse, not better. |
| `sorted_enum_cases` | 409 | Enum order here is semantic (`.small/.medium/.large`, edge orders). Alphabetising would destroy meaning. |
| `type_contents_order` / `file_types_order` | 2,194 / 632 | Impose one member ordering; this codebase orders by narrative (public API, then core, then helpers), which reads better. |
| `conditional_returns_on_newline` | 1,261 | `guard x else { return }` on one line is idiomatic and compact. |
| `multiline_arguments*` / `multiline_call_arguments` / `multiline_parameters` | 3,556 / 2,743 / 1,180 / 159 | swift-format already owns argument wrapping. |
| `switch_case_on_newline` | 795 | One-line `case .foo: return bar` is the dominant, readable form here. |
| `vertical_whitespace_between_cases` | 718 | Would inflate dense, well-organised switches. |
| `one_declaration_per_file` | 1,017 | Fights the deliberate "public view + private `_*Core` in one file" pattern. |
| `strict_fileprivate` | 129 | `fileprivate` is used purposefully for the split core/handler pairs. |
| `attributes` | 212 | Attribute placement is swift-format's job. |
| `indentation_width` | 169 | Ditto. |

### Decline — low value, high churn (9)

`let_var_whitespace` (98), `pattern_matching_keywords` (105),
`anonymous_argument_in_multiline_closure` (209), `closure_body_length` (70),
`function_default_parameter_at_end` (56), `multiline_function_chains` (46),
`period_spacing` (29), `local_doc_comment` (27), `superfluous_else` (25).
Each is defensible in the abstract; none changes correctness, and all would
produce a large diff across code that currently reads fine.

### Borderline — defensible either way (8)

| Rule | Sites | Note |
|---|---|---|
| `private_swiftui_state` | 121 | `@State` should be private, and all 121 are in Example/Stress/Tests. Mechanical and safe; low value. Enable if you want the demo app exemplary. **Enabled** in `b08531db` (2026-08-25): 105 privatised, and the 16 the language will not let us close — a stored property read by an `extension` in another file, plus test fixtures read by sibling suites — carry a documented `disable:this`. `.swiftlint.yml:76`. |
| `discouraged_optional_boolean` | 43 | `Bool?` is a real smell, but several here are genuine tri-state (inherited-or-overridden) values. |
| `discouraged_optional_collection` | 68 | Same shape; some are meaningfully "absent vs empty". |
| `redundant_self` | 14 | Small; swift-format has its own view on `self`. |
| `convenience_type` | 5 | Would convert 5 caseless enums/structs; cosmetic. |
| `prefer_condition_list` | 93 | Modern `if a, b` over `&&`; readable but a wide diff. |
| `unused_parameter` | 194 | Many are protocol-witness signatures that must keep the parameter. |
| `incompatible_concurrency_annotation` | 79 | Suggests `@preconcurrency`; worth a look **specifically** because this is a Swift 6 concurrency codebase, but each hit needs judgement, not a sweep. |

### Not applicable — the framework/tooling isn't used (30)

Measured zero because the codebase never uses the thing they police, so
enabling them guards nothing. (Until 2026-09-28 this list named 46 rules under
a heading of 41 and called them all zero; 17 were not — see the next section.)

- **XCTest** (`balanced_xctest_lifecycle`, `empty_xctest_method`, `single_test_class`, `test_case_accessibility`, `final_test_case`, `xct_specific_matcher`) — 0 files import XCTest; all 521 test files use swift-testing.
- **Quick / Nimble** (`quick_discouraged_call`, `quick_discouraged_focused_test`, `quick_discouraged_pending_test`, `prefer_nimble`, `nimble_operator`) — not used.
- **Interface Builder / UIKit** (`private_action`, `private_outlet`, `strong_iboutlet`, `prohibited_interface_builder`, `ibinspectable_in_extension`, `override_in_extension`, `overridden_super_call`, `prohibited_super_call`) — no IB, few classes.
- **SwiftUI assets** (`prefer_asset_symbols`, `object_literal`, `discouraged_object_literal`) — a terminal has no asset catalog.
- **Foundation localization** (`nslocalizedstring_key`, `nslocalizedstring_require_bundle`) — the project ships its own `LocalizedStringKey`.
- **Combine** (`private_subject`) — nothing imports Combine.
- **Misc inapplicable**: `discarded_notification_center_observer`, `discouraged_assert`, `expiring_todo`, `file_name_no_space`, `required_enum_case`.

### Listed as zero, but not (17) — corrected 2026-09-28

The measurement behind every other count in this review, rerun with 0.63.2
over the tree at `cefdc8fa`, finds these 17 non-zero; 15 of them already were
on the day, so the list was wrong when it was written, not overtaken. None is
enabled. Each has its count then and today (0.65.1, 1,736 files) and a
verdict:

| Rule | 2026-08-25 | 2026-09-28 | Verdict |
|---|---|---|---|
| `vertical_whitespace_opening_braces` | 700 | 1,174 | swift-format owns vertical whitespace. |
| `vertical_parameter_alignment_on_call` | 10 | 22 | swift-format owns alignment. |
| `multiline_literal_brackets` | 12 | 14 | swift-format owns wrapping. |
| `literal_expression_end_indentation` | 0 | 1 | swift-format owns indentation. |
| `extension_access_modifier` | 504 | 578 | The mirror image of `no_extension_access_modifier` (declined above), and it contradicts swift-format's `NoAccessLevelOnExtensionDeclaration`, which `.swift-format` enables. |
| `no_empty_block` | 611 | 1,102 | Empty blocks here are no-op closures (`Button("OK") {}`, `set: { _ in }`) and SwiftUI-parity `public init() {}`. Its new `allow_compact_empty_blocks` still leaves 120, all `{ _ in }` shapes (Part 3). |
| `required_deinit` | 307 | 541 | An empty `deinit` in every class says nothing. |
| `explicit_enum_raw_value` | 155 | 446 | A `String` enum's implicit raw value is its case name; `case top = "top"` only restates it. |
| `prefixed_toplevel_constant` | 21 | 53 | A `k` prefix is the C and Objective-C convention the Swift API guidelines drop. |
| `file_name` | 200 | 280 | Files here are named for the feature they hold (`DialogPreferredWidth.swift`: an environment key and the `View` modifier that sets it; `MediumGuaranteedModifiers.swift`: a group of `View` modifiers), not for one type. |
| `legacy_objc_type` | 12 | 16 | `NSString`'s path API (`appendingPathComponent`, `pathExtension`), which `String` lacks, in the localization code, its tests and the Example's file browser, plus two `NSLocale.preferredLanguages`. Low value. |
| `unneeded_throws_rethrows` | 10 | 22 | All in Tests: 20 test functions declared `throws` that do not throw, and two `init(from:) throws` `Decodable` witnesses in fixtures. No production signature carries a needless `throws`. Low value. |
| `async_without_await` | 3 | 4 | The wasip1 `SignalManager.install(wake:)` no-op keeps the real one's `async` signature; two test helpers are the `.task { await … }` bodies under test; one test is `async` with nothing to await. |
| `shorthand_argument` | 1 | 6 | Style: `$0` or `$1` a few lines into a closure. |
| `raw_value_for_camel_cased_codable_enum` | 0 | 7 | All in `TerminalQuirks` (`SkinTones`, `Keycaps`): public `Codable` enums whose wire spelling is the case name by design. The rule assumes a snake_case format; raw values equal to the case names would only restate them. |
| `accessibility_label_for_image` / `accessibility_trait_for_button` | 2 / 1 | 3 / 2 | SwiftUI accessibility rules matching TUIkit's own `Image` and `.onTapGesture`. A terminal has no VoiceOver, so they stay off. |

### Analyzer rules — a different workflow (5)

`unused_declaration`, `unused_import`, `capture_variable`, `explicit_self`,
`typesafe_array_init` require `swiftlint analyze` with a compiler log, not
`swiftlint lint`. **`unused_declaration` and `unused_import` are the two worth
having**: dead code and stale imports are real findings a linter can't
otherwise see. They belong in a periodic manual sweep rather than the CI gate,
because the build-log requirement makes them slow and fragile.

## Part 3 — SwiftLint 0.63.3 to 0.65.1, reviewed 2026-09-28

**Method.** The original review's measurement, repeated with both binaries:
every opt-in rule on, `disabled_rules` dropped, the project's rule
configuration kept, over `Sources` + `Tests`. Run by 0.63.2 over the tree as it
stood at `cefdc8fa` (the original review), it reproduces every count in Part
2's tables — `contrasted_opening_brace` 30,235, `no_magic_numbers` 21,107,
`explicit_acl` 9,411 and the rest — so the numbers below are measured the same
way. Run by both binaries over today's tree (1,736 files), the per-rule counts
differ only for the new rules, for the five existing rules the second table
shows moving, and for `superfluous_disable_command`, which 0.63.2 raises on the
two disables that name a rule it does not know.

### New rules (6)

| Rule | Kind | Sites | Verdict |
|---|---|---|---|
| `redundant_final` | opt-in, autocorrects | 0 | **Enabled.** `final` on a member of a `final class`, or on an actor or its members, says nothing. This project already finalises its classes and enforces `non_overridable_class_declaration`, so a `final func` inside a `final class` is the drift left to stop. Perturbed before enabling: `final` added to `Lock.withLock` (a member of `final class Lock`) is reported, and under the previous config it is not. |
| `invisible_character` | default | 0 | Already enforced, now **configured**. By default it rejects only U+200B, U+200C and U+FEFF inside a string literal; `additional_code_points` adds the other characters that draw nothing: the bidi controls behind "Trojan Source" (U+202A–202E, U+2066–2069), the direction marks (U+200E, U+200F, U+061C), the word joiner and invisible operators (U+2060–2064) and the soft hyphen (U+00AD), each at 0 raw occurrences today. In a literal they must now be `\u{…}` escapes, which a reviewer can see. U+200D and the tag characters stay allowed: they are the content of emoji-sequence and flag literals (98 and 6 raw occurrences outside comments). Perturbed: each of the 18, raw in a `TerminalWidthCorpus` literal, is reported and a raw U+200D is not; the previous config reports only the default three. |
| `legacy_swiftui_aspect_ratio` | default, autocorrects | 2, suppressed | Its only sites are the definitions of `scaledToFit()` and `scaledToFill()`, which *are* the spelling it recommends, and the 0.65.1 pin disabled it on those two lines. The disables matter beyond the lint: on a copy of `Image.swift` without them, `swiftlint --fix` rewrites each body into a call to itself. The comment at each site now says so. |
| `variable_shadowing` | opt-in | 245 | **Decline.** Its commonest shapes here are deliberate. Re-binding a parameter to its checked form, so the unchecked value can no longer be reached: `let innerWidth = max(0, innerWidth)` (the negative-size clamp), `let context = context.publishingContainerAxis(.horizontal)`, `guard let other = other as? Self`. And snapshotting a stored property before a closure captures it: `let destination = self.destination`. Renaming either kind makes the stale value reachable again, which is the mistake the shadowing prevents. The default `ignore_parameters: true` still reports a local that re-binds a parameter; turning it off adds the parameters themselves (476). |
| `discouraged_default_parameter` | opt-in | 331 | **Decline.** 309 internal and 22 package functions; public ones are not flagged by default. Default arguments are this codebase's test seam: production callers take the environment-reading default (`isITerm2: Bool = TerminalHost.isITerm2`, `date: Date = FrameClock.nowDate`, `depth: ColorDepth = ColorDepth.current`, `locale: Locale = .current`) and a test passes a fixed value. The internal cores also carry the defaults of the public SwiftUI-parity API they back. Without defaults, each becomes an overload or a value spelled out at every call site. |
| `legacy_uigraphics_function` | opt-in | 0 | Not applicable: it polices UIKit's `UIGraphicsBeginImageContext`, and nothing here imports UIKit. |

### Changed defaults and behaviour of existing rules

| Rule | Here | What changed | On this tree |
|---|---|---|---|
| `prefer_self_in_static_references` | enabled, autocorrected | 0.63.3 applies it inside extensions too. 0.64.0 stops it rewriting a cast's type operand to `Self` in a class — `x is Self` is not `x is A` in a non-final class, so the old rewrite changed behaviour — and in protocol compositions, existentials and generic constraints. | The 44 extension sites were fixed with the pin (`15d6ae3e`). For the cast fix, the question was whether an earlier autocorrect had already done the damage: all seven `as? Self` casts in the tree are in protocol extensions or a struct, none in a class. |
| `force_unwrapping` | declined | New `ignored_literal_argument_functions` (0.63.3) exempts `URL(string:)`, `NSURL(string:)`, `UIImage(named:)`, `NSImage(named:)` and `Data(hexString:)` called with literal arguments. Since 0.64.0 a configured list replaces those defaults instead of adding to them. | 732 → 702. Verdict unchanged: the rest are the render-time invariants Part 2 describes. |
| `identifier_name` | default | `--default-config` now prints `additional_operators: []` where 0.63.2 printed the operator characters. | Display only: an operator declaration passes under both versions, and the rule's result over the tree is the same. |
| `unowned_variable_capture` | enabled | New `allow_explicit_unsafe_unowned` (0.65.1), off by default. | Nothing to decide: the tree has no `unowned(unsafe)` capture. |
| `line_length` | enabled, `ignores_urls: true` | 0.65.1 stops treating a member access whose name is a top-level domain (`.app`, `.dev`) as a URL. | Clean at 160 under 0.65.1, so no long line was hiding behind that misfire. |
| `no_empty_block` | not enabled | New `allow_compact_empty_blocks` (0.65.1). | 1,102 sites, still 120 with the option on: the remainder is `{ _ in }`, the no-op closure that takes arguments (`set: { _ in }`, `.onChange(of:) { _, _ in }`). |
| `unused_parameter` | not enabled | New `allow_underscore_prefixed_names` (0.63.3). | 291 either way: none of the unused parameters is spelled `_name`. |
| `pattern_matching_keywords` | not enabled | Extended beyond `switch` cases (0.63.3). | 196 → 234. |
| `indentation_width` | not enabled | Continuation lines of a multi-line condition are skipped unless `include_multiline_conditions` is set (0.63.3). | 217 → 206. |
| `multiline_call_arguments` | not enabled | Enum-case patterns are no longer reported (0.63.3). | 2,340 → 2,357, the net of every change to the rule; not investigated further, since wrapping is swift-format's job here. |
| `unneeded_throws_rethrows` | not enabled | A `try` in the arguments of a call that also has a trailing closure now counts (0.63.3). | 23 → 22. |
| `opening_brace` | disabled | `allow_multiline_func` removed (0.65.1). | Not configured here, so nothing to migrate. |
| SwiftLint itself | — | Runs on Windows from 0.64.0, but requires `\n` line endings in every file it lints. | Noted beside `file_header`'s `\r?\n` in `.swiftlint.yml`: a Windows lint lane would need an LF checkout regardless. |

Also changed, and clean here with nothing to configure: `modifier_order`
recognises `isolated`; `statement_position` checks the space before a
`guard`'s `else`; `optional_data_string_conversion` renamed
`allow_implicit_init` to `include_implicit_init` (not set here);
`implicit_optional_initialization` gained `ignore_attributes`;
`closure_end_indentation` and `closure_spacing` correct CRLF files and
trivia-only closures properly. The analyzer rule `unused_import` now
understands access-level modifiers on imports, which matters only to the
manual sweep.

## Summary

Three exceptions retired, one latent bug fixed (the bare `fatalError()`), and
137 lines of config removed — with the remaining exceptions now carrying
measured justifications instead of assertions. Of 109 optional rules, **9 were
enabled** (all verified at zero violations first), both follow-ups have since been
taken — `missing_docs` (41 public declarations documented) and `file_header`
(configured, 21 defects fixed) — two more of the verdicts below were called the
same day (`direct_return` and `private_swiftui_state`, `b08531db`), and the rest
decline for reasons
that are now written down rather than rediscovered.

The 2026-09-28 review of SwiftLint 0.63.3 to 0.65.1 (Part 3) enabled
`redundant_final` at zero violations, gave the default `invisible_character`
the rest of the characters that draw nothing, and declined `variable_shadowing`
and `discouraged_default_parameter` for the idioms they would take away. No
changed default of an existing rule needs a configuration change.

The linter now enforces 55 opt-in rules on top of the defaults, at 0
violations across 1,736 files (SwiftLint 0.65.1).
