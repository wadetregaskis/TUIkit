# WebAssembly

TUIkit builds for `wasm32-unknown-wasip1`, and the Example app runs in a
browser. This file is the record of what that took, what works, what does not,
and why — the same kind of record `Terminal-compatibility.md` keeps for
terminals.

    Tools/Web/build.sh      # builds Example.wasm and collects its resources
    Tools/Web/serve.py      # serves them with the headers the page needs
    open http://127.0.0.1:8000/

## The toolchain, and why it is not the one you already have

Three things have to line up, and two of them are not obvious.

1. **A swift.org toolchain, not Xcode's.** Xcode's compiler is built without
   the WebAssembly LLVM target: it does not fail to *link*, it stops at
   `No available targets are compatible with triple wasm32-unknown-wasip1`
   while compiling the first file.
2. **6.3 or newer.** On 6.2.4 the compiler aborts on `TupleView`'s
   pack-expansion conformance (`SILGenPoly.cpp`, `isPreconcurrency`) — the same
   assertion that blocks the Linux static-SDK check, and the reason
   `TUIkitView` cannot be built for either target on that version. 6.3.3 builds
   the whole package.
3. **A Swift SDK whose version matches the toolchain exactly.** A 6.2.4 SDK
   under a 6.3.3 toolchain fails to load the standard library.

```sh
swiftly install 6.3.3
swift sdk install \
  https://download.swift.org/swift-6.3.3-release/wasm-sdk/swift-6.3.3-RELEASE/swift-6.3.3-RELEASE_wasm.artifactbundle.tar.gz \
  --checksum <published by swift.org>
```

Two flags are not optional. `--static-swift-stdlib` is what points the compiler
at the SDK's `swift_static` resources, and without it Foundation is missing
(`no such module 'Foundation'`, from an SDK that plainly contains it). And the
SDK must be named by its *bundle id* — `--swift-sdk swift-6.3.3-RELEASE_wasm` —
not by the triple: the artifact bundle installs an embedded-Swift SDK under the
same triple, SwiftPM picks between them arbitrarily, and the embedded one has no
standard library to find.

## What had to change in the framework

Very little in the four lower modules, which is the dividend of the rule that
keeps POSIX in the umbrella: `TUIkitCore` built for wasm unchanged, and
`TUIkitStyling`, `TUIkitView` and `TUIkitImage` needed one fix each.

| Where | What | Why |
|---|---|---|
| `ShapeSampling` | a `WASILibc` arm on the libm ladder | `cos`/`sin` are C, and an unnamed platform gets no `cos` — the same failure Windows had |
| `BodyMutationDiagnostic` | `Thread.current` → a token | Foundation has no `Thread` where the platform has no threads |
| `ImageLoader` | the remote-image path is gated | `URLSession` is in neither Foundation nor FoundationNetworking on WASI, and wasip1 has no sockets to use it with |

The umbrella is where the work was. `Dispatch` does not exist on wasip1, and it
was imported into six files — mostly to read a clock. `MonotonicClock` (in
`TUIkitCore`) replaced `DispatchTime.now().uptimeNanoseconds` at a dozen call
sites, which removed the dependency from every file that only wanted to measure
an interval. What remained genuinely needed a platform arm:

| Subsystem | On WASI |
|---|---|
| `SignalManager` | a whole stub: no signals, no job control, no resize notification |
| `StdinArrivalNotifier` | `poll` — one call that waits on stdin *and* a timeout, which is exactly what the dispatch-source-plus-`Task.sleep` race was emulating |
| `Terminal` raw mode | the `termios` calls go; every escape sequence stays, because bracketed paste, mouse tracking and the modifier-key mode are the terminal's business, not the kernel's |
| `Terminal` size | no `ioctl`, so `COLUMNS`/`LINES` from the environment — the fallback that was already there |
| `SystemClipboard`, `OpenURLAction`, tmux queries | stubs: all three are subprocesses, and wasip1 cannot start one |
| `@AppStorage`'s file backend | writes inline instead of on a queue, and non-atomically — WASI's Foundation refuses `.atomic`, which needs a temporary file |

## Two bugs the port found in code that was not WebAssembly's

Worth recording, because both were latent everywhere:

- **`MonotonicClock`'s first reading.** Written as `SuspendingClock.now - epoch`
  with `epoch` a lazily-initialised `static let`, Swift evaluates the left
  operand first — so the very first call reads the clock, *then* initialises the
  origin from a later reading, and subtracts a larger number from a smaller one.
  The negative `Duration` has `seconds == 0` and negative attoseconds, walks
  past a `seconds >= 0` guard, and traps converting to `UInt64`. It aborted the
  first WebAssembly launch on its first frame and would have been a rare
  unreproducible crash anywhere.
- **Bundle resources are found by path, not by name.** `Bundle.module` resolves
  on WASI, but `url(forResource:withExtension:subdirectory:)` returns `nil` for
  a file that is sitting in the bundle directory. The symptom is quiet: the
  framework's own strings render as their keys (`statusbar.quit` across the
  status bar) and `tuiKitVersion` reads `unknown`. `moduleResourceURL(named:
  extension:subdirectory:)` asks by name first and works it out from the bundle
  URL second.

## Running it in a browser

The demo is three files under `Tools/Web/site/` and one non-obvious constraint.

**The program blocks, so it runs in a Worker.** A terminal app spends its life
in `poll_oneoff` waiting for a keystroke; that has to be a real block, or the
Swift runtime spins, and a real block on the main thread is a frozen tab. The
worker parks with `Atomics.wait` on a `SharedArrayBuffer` the page shares with
it, and the page wakes it by bumping a sequence word when a key arrives. This is
why the page must be **cross-origin isolated** — `SharedArrayBuffer` does not
exist otherwise — and why `serve.py` exists rather than a line in a README
telling you to use `python3 -m http.server`.

Three details in `wasi.js` are load-bearing, and each one was a bug first:

- **stdout is flushed before the guest blocks, not on a microtask.** `_start()`
  does not return while the app is running, so anything queued behind the
  current task never runs: the first version batched output into
  `queueMicrotask` and drew a blank terminal with every frame sitting in a queue.
- **`fd_read` on stdin never blocks; it returns `EAGAIN`.** That is what raw
  mode gives a POSIX guest (`VMIN`/`VTIME` of zero), and it is what TUIkit's
  drain loop expects. A blocking read parks the worker inside a call the guest
  expected to return at once, and the app draws one frame and freezes.
- **`poll_oneoff` reports an fd subscription ready only when bytes are queued.**
  A guest told stdin is readable reads it, and the read has to have something
  behind it.

**The stack has to be raised at link time.** A view tree renders by recursion,
and wasm's default linear-memory stack runs out inside the Example's deeper
pages. `Tools/Web/build.sh` links with `-z stack-size=16777216`.

## What works, and what does not

Works: the whole Example — every page, the focus ring's pulse, animations,
gradients, mouse-free navigation, `@AppStorage` within a session, all seven
languages, and a clean exit on `q`.

Does not, and why:

| | |
|---|---|
| Resize | wasip1 has no `ioctl` and the browser has no way to tell the guest; the size is fixed at start from `COLUMNS`/`LINES`. An in-band resize channel would fix it and is not built. |
| Remote images | no sockets. A file image works; `Image(url:)` reports that the platform has no URL loading. |
| Clipboard | the page has one; the guest cannot reach it. OSC 52 would let the *terminal* do it and is not wired up. |
| Opening links | no subprocess. OSC 8 hyperlinks still work, because the terminal opens those, not the app. |
| Terminal graphics | the handshake gets no answer, so pictures fall back to cells. xterm.js does not implement the Kitty protocol. |
| Size on disk | ~50 MB of wasm, ~20 MB gzipped, almost all of it Foundation and ICU. |

## The build's shape

`build.sh` writes `Tools/Web/site/manifest.json`, which maps each resource file
to the absolute path the binary expects it at. That path is the developer's own
build directory, because SwiftPM compiles the bundle's location into the binary
and there is no way to ask it to look elsewhere — the manifest is regenerated on
every build, so it stays true, but a site built on one machine will not find its
resources on another. Anyone shipping this properly should embed the resources
instead.
