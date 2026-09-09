# SwiftLint: what we enforce, and every optional rule we don't

**Reviewed 2026-08-25 against SwiftLint 0.63.2** (the CI-pinned version), by
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

### Decline — conflicts with a project rule or another tool (7)

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

### Decline — wrong for this codebase (13)

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

### Borderline — defensible either way (6)

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

### Not applicable — the framework/tooling isn't used (41 of the zero-violation set)

All measured zero because the codebase never uses the thing they police, so
enabling them guards nothing:

- **XCTest** (`balanced_xctest_lifecycle`, `empty_xctest_method`, `single_test_class`, `test_case_accessibility`, `final_test_case`, `xct_specific_matcher`) — 0 files import XCTest; all 521 test files use swift-testing.
- **Quick / Nimble** (`quick_discouraged_call`, `quick_discouraged_focused_test`, `quick_discouraged_pending_test`, `prefer_nimble`, `nimble_operator`) — not used.
- **Interface Builder / UIKit** (`private_action`, `private_outlet`, `strong_iboutlet`, `prohibited_interface_builder`, `ibinspectable_in_extension`, `override_in_extension`, `overridden_super_call`, `prohibited_super_call`, `required_deinit`) — no IB, few classes.
- **SwiftUI accessibility & assets** (`accessibility_label_for_image`, `accessibility_trait_for_button`, `prefer_asset_symbols`, `object_literal`, `discouraged_object_literal`) — a terminal has no asset catalog or VoiceOver.
- **Foundation localization** (`nslocalizedstring_key`, `nslocalizedstring_require_bundle`) — the project ships its own `LocalizedStringKey`.
- **Misc inapplicable**: `discarded_notification_center_observer`, `discouraged_assert`, `expiring_todo`, `file_name_no_space`, `raw_value_for_camel_cased_codable_enum`, `required_enum_case`, `legacy_objc_type`, `prefixed_toplevel_constant`, `explicit_enum_raw_value`, `literal_expression_end_indentation`, `multiline_literal_brackets`, `no_empty_block`, `extension_access_modifier`, `shorthand_argument`, `async_without_await`, `unneeded_throws_rethrows`, `vertical_parameter_alignment_on_call`, `vertical_whitespace_opening_braces`, `file_name`.

### Analyzer rules — a different workflow (5)

`unused_declaration`, `unused_import`, `capture_variable`, `explicit_self`,
`typesafe_array_init` require `swiftlint analyze` with a compiler log, not
`swiftlint lint`. **`unused_declaration` and `unused_import` are the two worth
having**: dead code and stale imports are real findings a linter can't
otherwise see. They belong in a periodic manual sweep rather than the CI gate,
because the build-log requirement makes them slow and fragile.

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

The linter now enforces 54 opt-in rules on top of the defaults, at 0
violations across 1,094 files.
