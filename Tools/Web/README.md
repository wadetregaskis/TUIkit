# Tools/Web — the Example app in a browser

```sh
Tools/Web/build.sh          # compile to wasm, collect resources, write the manifest
Tools/Web/serve.py          # serve it, cross-origin isolated
open http://127.0.0.1:8000/
```

The design, the toolchain requirements and the list of what does not work are in
[`Documentation/WebAssembly.md`](../../Documentation/WebAssembly.md). This file
is the map of the directory.

| File | What it is |
|---|---|
| `build.sh` | builds `Example.wasm` with a swift.org 6.3+ toolchain and the WebAssembly SDK, runs `wasm-opt` when it is installed, copies the SwiftPM resource bundles into `site/resources/`, and writes `site/manifest.json` |
| `serve.py` | a static server that sets `Cross-Origin-Opener-Policy` and `Cross-Origin-Embedder-Policy`. The demo needs `SharedArrayBuffer`, which needs those headers, which `python3 -m http.server` cannot send |
| `site/index.html` | the page: an xterm.js terminal, the keystroke ring, and the worker |
| `site/worker.js` | instantiates the module and runs it; owns stdout batching |
| `site/wasi.js` | the WASI preview1 implementation — about 35 calls, the ones a Swift executable imports |
| `site/manifest.json` | generated; maps each resource file to the guest path the binary looks for it at |
| `site/Example.wasm` | generated |

`site/Example.wasm`, `site/resources/` and `site/manifest.json` are build
products and are not committed — run `build.sh` to make them.

## Poking at it

The page exposes a small handle for when something does not arrive:

```js
__tuikit.pending()      // keystroke bytes the guest has not taken yet
__tuikit.indices()      // [wake sequence, write index, read index, spare]
__tuikit.send("q")      // put bytes in without going through the keyboard
```

If the terminal stays blank, check the status line under it: `fetching…` and
`compiling…` come from the worker, and anything after `running` means the guest
started. If the page says it is not isolated, it was not served by `serve.py`.
