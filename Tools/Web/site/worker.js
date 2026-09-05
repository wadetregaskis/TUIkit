// 🖥️ TUIkit — Terminal UI Kit for Swift
// worker.js — runs the Swift program, off the page's thread.
//
// Everything here happens in a Web Worker for one reason: the guest blocks.
// A terminal app spends most of its life parked in `poll_oneoff` waiting for a
// keystroke, and a block on the main thread is a frozen tab. In a worker it is
// just a thread doing nothing, which is what it should be.

import { BrowserWASI, WASIExit, CONTROL_SEQUENCE } from "./wasi.js";

let pendingOutput = [];

/**
 * Collects stdout; `flush` sends it.
 *
 * A frame is dozens of small writes, and posting each one separately spends
 * more time in `postMessage` than the render did — so they are batched. What
 * they cannot be batched behind is a *queue*: `_start()` does not return while
 * the app is running, so a microtask or a timer would never run. The flush
 * happens instead at the one moment that is both frequent and correct — just
 * before the guest blocks, which is exactly when it has finished a frame.
 */
function writeOut(bytes) {
  pendingOutput.push(bytes);
}

function flush() {
  if (pendingOutput.length === 0) return;
  const total = pendingOutput.reduce((sum, chunk) => sum + chunk.length, 0);
  const merged = new Uint8Array(total);
  let cursor = 0;
  for (const chunk of pendingOutput) {
    merged.set(chunk, cursor);
    cursor += chunk.length;
  }
  pendingOutput = [];
  self.postMessage({ kind: "stdout", bytes: merged }, [merged.buffer]);
}

self.onmessage = async (event) => {
  const message = event.data;
  if (message.kind !== "start") return;

  const { wasmURL, manifest, columns, rows, control, input } = message;

  // The guest's filesystem: the resource bundles SwiftPM built, fetched as
  // bytes and filed under the absolute paths the binary was compiled to look
  // in. `Tools/Web/build.sh` writes the manifest that says which is which.
  const files = new Map();
  const directories = new Set(["/"]);
  await Promise.all(
    manifest.files.map(async (entry) => {
      const response = await fetch(entry.url);
      if (!response.ok) throw new Error(`could not fetch ${entry.url}: ${response.status}`);
      files.set(entry.path, new Uint8Array(await response.arrayBuffer()));
      let directory = entry.path.slice(0, entry.path.lastIndexOf("/"));
      while (directory.length > 0) {
        directories.add(directory);
        directory = directory.slice(0, directory.lastIndexOf("/"));
      }
    })
  );
  for (const directory of manifest.directories ?? []) directories.add(directory);

  const wasi = new BrowserWASI({
    args: [manifest.argv0 ?? "Example"],
    env: {
      // The size is fixed at start: wasip1 has no `ioctl`, so this is the only
      // way the guest can learn the terminal's shape (`Terminal.getSize()`
      // falls back to exactly these two).
      COLUMNS: String(columns),
      LINES: String(rows),
      TERM: "xterm-256color",
      COLORTERM: "truecolor",
      LANG: message.language ?? "en_US.UTF-8",
      TUIKIT_CONFIG_DIR: "/config",
      ...(message.env ?? {}),
    },
    files,
    directories: [...directories, "/config"],
    control,
    input,
    writeOut,
    beforeBlock: flush,
  });

  try {
    self.postMessage({ kind: "status", text: "fetching…" });
    const response = await fetch(wasmURL);
    if (!response.ok) throw new Error(`could not fetch the module: ${response.status}`);
    self.postMessage({ kind: "status", text: "compiling…" });
    const { instance } = await WebAssembly.instantiateStreaming(response, {
      wasi_snapshot_preview1: wasi.exports(),
    });
    wasi.bind(instance);
    self.postMessage({ kind: "status", text: "running" });
    // `_start` is the WASI entry point. It returns when the guest's `main`
    // does, and throws `WASIExit` when it calls `proc_exit` — which is what
    // quitting the app looks like from here.
    instance.exports._start();
    flush();
    self.postMessage({ kind: "exit", code: 0 });
  } catch (error) {
    flush();
    if (error instanceof WASIExit) {
      self.postMessage({ kind: "exit", code: error.code });
    } else {
      self.postMessage({ kind: "error", message: String(error && error.stack ? error.stack : error) });
    }
  }
};
