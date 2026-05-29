# Actor isolation and the input-reader loop

This document is a design discussion, not yet a specification. It catalogues
two coupled questions that came up while adopting `ordo-one/benchmark`
(task #26) and revisiting input responsiveness:

1. **The input-reader loop.** TUIkit currently sleeps between polls of
   stdin. The desired shape is "respond to input immediately, never
   busy-spin, never block the main actor." What does the read path look
   like?
2. **Actor isolation.** TUIkit's `View` API and render pipeline are
   `@MainActor`-isolated. That isolation is the proximate cause of the
   benchmark-deadlock that prevents view-using benchmarks from running.
   Should TUIkit move its render pipeline onto a dedicated global actor?

The two questions are loosely coupled — most input-reader approaches
work under either actor model — but the actor decision shapes what "the
render loop runs on" actually means, and choosing well on one influences
the other.

## The input-reader question

The "poll-and-sleep" loop is the wrong shape regardless of where TUIkit
lives. Conceptually:

```swift
// What we don't want
while !shouldExit {
    if let event = readEventNonBlocking() {
        dispatch(event)
    } else {
        Thread.sleep(0.01)  // wastes time, adds up to ~10 ms latency
    }
}
```

The right shape is **a reader that blocks on stdin and pushes parsed
events into an `AsyncStream`**, with the render loop awaiting that
stream from wherever it runs. Zero polling, zero busy-loop, zero
artificial latency.

```swift
let inputStream = AsyncStream<InputEvent> { continuation in
    let source = DispatchSource.makeReadSource(
        fileDescriptor: STDIN_FILENO,
        queue: .global(qos: .userInteractive)
    )
    source.setEventHandler {
        for event in parseAvailableEvents() { continuation.yield(event) }
    }
    source.setCancelHandler { continuation.finish() }
    source.activate()
}

// In the render loop, on whatever actor it lives on:
for await event in inputStream {
    dispatch(event)
    render()
}
```

### Reader implementations worth considering

#### A — DispatchSource read source

`DispatchSource.makeReadSource(fileDescriptor:queue:)` fires whenever
stdin has data. Wrap in an `AsyncStream<InputEvent>`. Cancellation via
`source.cancel()`.

- Cross-platform — `libdispatch` ships on both macOS and Linux, the
  swift-corelibs build on Linux has gotten steadily more reliable.
- Trivial cancellation lifecycle.
- No raw thread to manage.
- Integrates naturally with Swift Concurrency through the `AsyncStream`
  wrapper.

The escape ramp if Linux's dispatch implementation lets us down on a
specific source type is small — fall back to (B).

#### B — Dedicated POSIX reader thread + self-pipe trick

`Thread { }` blocks on `read(2)` from stdin, parses, pushes into the
stream. Cancellation via the self-pipe trick: write a byte to a pipe
the reader is also polling with `select(2)`, which wakes the read and
lets it exit cleanly.

- Maximum portability — works wherever `read` does.
- Hand-rolled threading: you own the lifecycle.
- More code than (A).

Use as the fallback if DispatchSource misbehaves on a platform.

#### C — kqueue (macOS) / epoll (Linux) directly

Lower-level than (A), platform-specific, no real benefit unless
DispatchSource specifically fails us. Skip unless that happens.

#### D — swift-nio

Battle-tested cross-platform I/O. Pulling a 10 MB dependency for "read
from stdin" is heavyweight. Skip unless TUIkit grows other network
needs.

**Recommendation:** reach for (A) first, hold (B) as the fallback.

## The actor question

Four options worth thinking about.

### 1. Status quo — everything `@MainActor`

Pros:

- Zero churn.
- Matches SwiftUI's conceptual model (Views are `@MainActor` there too).
- User-written action closures, `body` computations, and state mutations
  all share one isolation domain — easy to reason about.
- TUIkit-the-whole-app is the common case, and in that case `MainActor`
  effectively *is* the TUIkit thread.

Cons:

- The package-benchmark deadlock isn't fixable here. Same crash shape
  on macOS as Linux: package-benchmark blocks the main thread on a
  `DispatchSemaphore`, async benchmark closures hop to `MainActor`,
  and the work queues against a blocked thread until the runtime
  detects the deadlock and traps with SIGTRAP.
- Tests that want to run TUIkit code from non-main contexts need
  contortions.
- If TUIkit is ever embedded inside a hybrid app (e.g., a CLI tool that
  also pops a SwiftUI window), it competes for `MainActor` with the
  host.
- The input reader thread, after parsing events, has to hop to
  `MainActor` to dispatch. Fine for keystroke rates, but if the user's
  `MainActor` is busy with other work, events queue.

### 2. Full migration — everything moves to a new `@TUIkitActor`

Pros:

- Benchmark deadlock disappears. package-benchmark blocks `MainActor`,
  not `TUIkitActor`, so `await TUIkitActor.run { ... }` is
  non-deadlocking.
- Tests can spawn arbitrary tasks, each entering `TUIkitActor` cleanly.
- Input reader dispatches events directly to `TUIkitActor` without
  competing with anything the host does on `MainActor`.
- Explicit conceptual model: "TUIkit owns its actor."
- Future-proof for custom executors, priority assignment, etc.

Cons:

- Massive refactor. Every `@MainActor` annotation across the
  View/render/focus/state code becomes `@TUIkitActor`. Hundreds of
  declarations.
- Breaks SwiftUI conceptual parity. `View` in SwiftUI is `@MainActor`;
  here it would be `@TUIkitActor`. Users coming from SwiftUI will trip
  on this.
- Action callbacks (`Button("Save") { ... }`) now run on `TUIkitActor`.
  User code in those callbacks that wants to do `MainActor` work has
  to explicitly hop. Most user actions are "update a `@State` value"
  which is fine, but the API surface is wider.
- Cross-actor `Sendable` requirements — anything that crosses the
  boundary (e.g., user data passed to a `Binding`) needs to be
  `Sendable`. Painful for some shapes.

### 3. Hybrid — View construction nonisolated, render pipeline on `@TUIkitActor`, actions stay `@MainActor`

The most interesting middle ground.

- `View` protocol: `nonisolated`. View structs are pure value types;
  their constructors don't need an actor.
- `body: some View`: nonisolated by default; the user can opt into
  `@MainActor` or `@TUIkitActor` if needed.
- `renderToBuffer`, `FocusManager`, `StateStorage`,
  `MouseEventDispatcher`: `@TUIkitActor`.
- Action callbacks (`Button(action:)`, `.onTapGesture { }`, etc.):
  typed as `@MainActor () -> Void`. The dispatcher hops to `MainActor`
  to fire them.

Pros:

- Benchmarks work. Constructors are nonisolated (call from anywhere),
  the render call hops to `TUIkitActor` which package-benchmark's
  worker can enter.
- User actions feel natural — they run on `MainActor`, the place users
  expect "their" code to run. No surprise hops.
- View construction in tests is free.
- Cleanest actor story for a SwiftUI-shaped API.

Cons:

- Still a sizable refactor — less than option 2 but more than 1.
- The render loop now has two actor hops per click: dispatcher
  (`TUIkitActor`) → action (`MainActor`) → state update (which may
  trigger render). Manageable but real.
- Need to be careful about which state goes where. `@State`-stored
  values that the body reads need to be on the same actor as the body.
  If body is nonisolated, state needs to be `Sendable` or held in a
  reference type that handles its own synchronization.

### 4. Custom executor for `MainActor`

Reroute `MainActor`'s executor to a TUIkit-owned executor — `MainActor`
becomes "TUIkit's main thread" by construction. Doesn't actually solve
the benchmark deadlock (the issue is package-benchmark's *blocking
call* on the main thread, not the actor binding) and requires deep
runtime poking. Skip.

## How the input-reader interacts with the actor choice

The reader implementation is the same under any actor model. What
differs is what happens after the reader yields an event into the
stream:

- **Under (1) MainActor:** the consumer `await`s on `MainActor`. If
  the user's app has any other `MainActor` work scheduled (a timer
  firing, a Combine subscriber, an async function awaiting on
  `MainActor`), input events queue behind that work. For a "TUIkit is
  the whole app" CLI tool this is invisible; for anything more
  interesting it matters.
- **Under (2) or (3) TUIkitActor:** the consumer awaits on
  `TUIkitActor`. Events get dispatched to TUIkit immediately. Only the
  action callbacks themselves (under option 3) wait for `MainActor`.

So the actor choice mostly buys you latency robustness in hybrid
embeddings. For a pure TUIkit app it's roughly invisible.

## Where this leaves the project

- **The input-reader change is high-value, low-cost, and doesn't depend
  on the actor decision.** DispatchSource + AsyncStream gets instant
  input response now. Worth doing soon regardless of which actor
  direction we take.
- **Status quo (option 1) plus the input-reader fix is a coherent
  stopping point.** It gives up benchmark coverage of view rendering
  until further notice, but everything else works fine. If the
  benchmark gap doesn't actually bite — because the image benchmarks
  cover the historically-hot path and #29 has other ways to measure
  regressions like manual timing in tests — this is the lowest-cost
  answer.
- **The hybrid (option 3) is the right destination if we ever take it
  on.** It's a big enough refactor that we shouldn't do it
  speculatively — wait until one of: (a) benchmark coverage of view
  rendering becomes the bottleneck, (b) the embedding-in-a-host-app
  use case becomes real, (c) a third pain point shows up that #3
  solves and #1 doesn't.
- **Option 2 (full migration) buys little over option 3 at much higher
  cost.** Don't pick it.

Recommended order: do the input-reader async-stream conversion first
(small, decoupled, high-value), use it for a while to validate the
latency improvement, and then revisit whether option 3 is worth taking
on based on what shows up in practice. Don't commit to the actor
refactor *just* to unblock benchmarks — the cost-to-benefit on that
alone is wrong.
