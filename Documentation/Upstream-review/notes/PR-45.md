# PR #45 — `codex/issue-8-runtime`

Commits 24–35 · 2026-07-19 · merged as `37fea050`

Upstream removes the `AppState.shared` singleton: every service moves onto
`TUIContext`, state invalidation routes to the runtime that owns it, and two
runtimes can coexist in one process without leaking into each other.

## Decision

Assessed at length on 2026-07-19, and the two load-bearing ideas were taken then
— see [[upstream-2026-07-19-deep-dive]]. Full singleton removal stays
**deferred**: nothing here needs two apps in one process, and the cost is a
sweep through every service. The rest of this branch is either already ours or
specific to the architecture we did not adopt.

### Taken

- **`744ef091` — invalidation routes to its owner.** Shipped as `44660d87`: a
  `RenderInvalidationSink` protocol in TUIkitView, `RenderCache` as the
  per-context sink, and `StateBox.didSet` enqueueing behind a lock rather than
  mutating the cache directly. That last part fixed a real (narrow) data race,
  not just a layering complaint — a `@State` write from a background `Task` was
  touching an unsynchronised cache.
- **`ded58c11` — image loading per runtime.** Our `URLImageCache` was a
  singleton whose initializer was private, so per-runtime image caching was not
  expressible at all. `24bbba32` made it constructible, which is the part of
  this that matters here; whether anything then *uses* a non-shared cache is the
  app's business.

### Deferred, not rejected

- **`021d1293` — services owned per runtime**, and **`f93dc8d6`**, the
  alternating-runtime isolation test that would gate it. `AppState.shared`
  stays: `RenderCache` and `StateStorage` are already per-`TUIContext`, so what
  remains global is the render signal, localization, and notifications. Those
  only matter with two apps in one process, which nothing has asked for. If that
  changes, `f93dc8d6` is the test to port first — it is the honest statement of
  what "isolated" has to mean.

### Two "Fix:" commits checked against our tree — neither applies

Both looked like defects we might share. Both were probed rather than assumed:

- **`f1ca2fe9` — AppStorage projections bound to the runtime.** Their
  `projectedValue` built a fresh `Binding` from `self`, deferring the runtime
  lookup until the write, by which time the active runtime could be the wrong
  one. Ours is the same *shape* (`Binding(get:set:)` over `wrappedValue`), so
  the question was real. Probed with a view reading `@AppStorage` through an
  injected backend, rendered twice on one `TUIContext` with a write between: the
  second frame shows the new value. No stale-memo hole. It does not apply
  because with a single `AppState.shared` there is no wrong runtime to capture.

  Worth recording that the *first* probe "found" the bug and was wrong — it gave
  the view the default storage backend and wrote to a mock, so of course the
  frame did not change. Two backends, no bug. See
  [[interaction-test-discipline]].

- **`9adb6be2` — one-shot runtime lifecycle.** `renderOnce` left its runtime's
  lifecycle tasks running. Ours cannot: `ViewRenderer` builds a private
  `TUIContext` with `LifecycleManager(firesEffects: false)`, so no effect tasks
  are spawned, and the context dies with the call.

### Already ours — `have`

- `7c6309db` (isolate runtime render caches) — `RenderCache` has been
  per-`TUIContext` here for a long time.
- `340250ff` (localization key examples) — upstream's DocC samples used a
  `.button(.ok)` shorthand that does not exist; ours already spell it
  `LocalizationKey.Button.ok` throughout `Articles/Localization.md`.

### Their architecture — `n-a`

`3fa8b235` (standalone render runtime), `2cd1d634` (migration guide),
`f42b92f8` (a test updated for the new ownership). All describe the change we
deferred.
