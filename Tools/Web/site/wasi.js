// 🖥️ TUIkit — Terminal UI Kit for Swift
// wasi.js — a WASI preview1 host for the browser, sized to what a TUI needs.
//
// This implements the thirty-odd `wasi_snapshot_preview1` calls a Swift
// executable imports (dump them with `Tools/Web/imports.py`), and nothing else.
// It is deliberately small and readable rather than general: a terminal app
// reads stdin, writes stdout, asks the clock, reads a few resource files and
// writes one settings file, and that is the whole of it.
//
// The one hard part is blocking. A terminal program waits — for a keystroke, or
// for the few milliseconds until its next animation frame — and `poll_oneoff`
// is where it does the waiting. In a browser that has to be a real block, or
// the Swift runtime spins; and a real block is only legal off the main thread.
// So this runs in a Web Worker and blocks with `Atomics.wait` on memory it
// shares with the page. That is also why the page must be served with
// cross-origin isolation headers (see `Tools/Web/serve.py`): without them
// `SharedArrayBuffer` does not exist and none of this works.

const WASI_ESUCCESS = 0;
const WASI_EAGAIN = 6;
const WASI_EBADF = 8;
const WASI_EEXIST = 20;
const WASI_EINVAL = 28;
const WASI_ENOENT = 44;
const WASI_ENOSYS = 52;
const WASI_ENOTDIR = 54;

const FILETYPE_UNKNOWN = 0;
const FILETYPE_CHARACTER_DEVICE = 2;
const FILETYPE_DIRECTORY = 3;
const FILETYPE_REGULAR_FILE = 4;

const CLOCKID_REALTIME = 0;

const EVENTTYPE_CLOCK = 0;
const EVENTTYPE_FD_READ = 1;

// The shared control block the page and the worker talk through. Slot 0 is the
// futex word `Atomics.wait` sleeps on; the page bumps it whenever it puts bytes
// in the ring, which is what wakes a waiting worker early.
export const CONTROL_SEQUENCE = 0;
export const CONTROL_WRITE_INDEX = 1;
export const CONTROL_READ_INDEX = 2;
export const CONTROL_SLOTS = 4;

export class BrowserWASI {
  /**
   * @param {object} options
   * @param {string[]} options.args           argv for the guest.
   * @param {Record<string,string>} options.env  the guest's environment.
   * @param {Map<string,Uint8Array>} options.files  absolute path -> contents.
   * @param {string[]} options.directories    absolute paths that exist as dirs.
   * @param {SharedArrayBuffer} options.control  the futex + ring indices.
   * @param {SharedArrayBuffer} options.input    the keystroke ring buffer.
   * @param {(bytes: Uint8Array) => void} options.writeOut  stdout/stderr sink.
   * @param {() => void} options.beforeBlock  called before the worker parks.
   */
  constructor({ args, env, files, directories, control, input, writeOut, beforeBlock }) {
    this.args = args;
    this.env = env;
    this.files = files;
    this.directories = new Set(directories);
    this.control = new Int32Array(control);
    this.input = new Uint8Array(input);
    this.writeOut = writeOut;
    this.beforeBlock = beforeBlock ?? (() => {});
    this.memory = null;
    this.exitCode = null;

    // fd 0/1/2 are the terminal, fd 3 is the preopened root directory. Files
    // opened by the guest take numbers from 4 up.
    this.nextFd = 4;
    this.openFiles = new Map();
  }

  bind(instance) {
    this.memory = instance.exports.memory;
  }

  get view() {
    return new DataView(this.memory.buffer);
  }

  get bytes() {
    return new Uint8Array(this.memory.buffer);
  }

  // MARK: - stdin, and the wait that makes it a terminal

  /** How many keystroke bytes are queued but not yet handed to the guest. */
  pendingInput() {
    const write = Atomics.load(this.control, CONTROL_WRITE_INDEX);
    const read = Atomics.load(this.control, CONTROL_READ_INDEX);
    return write - read;
  }

  /** Copies up to `max` queued bytes out of the ring. */
  takeInput(max) {
    const write = Atomics.load(this.control, CONTROL_WRITE_INDEX);
    let read = Atomics.load(this.control, CONTROL_READ_INDEX);
    const out = [];
    while (read < write && out.length < max) {
      out.push(this.input[read % this.input.length]);
      read += 1;
    }
    Atomics.store(this.control, CONTROL_READ_INDEX, read);
    return Uint8Array.from(out);
  }

  /**
   * Blocks the worker until input arrives or `timeoutMs` passes (`timeoutMs`
   * of `null` waits indefinitely). Returns true if input is waiting.
   *
   * `Atomics.wait` is the whole mechanism: it parks this thread in the engine,
   * costs nothing while parked, and returns the moment the page bumps the
   * sequence word. A polling loop with a spin would work too, and would burn a
   * core in a background tab.
   */
  waitForInput(timeoutMs) {
    if (this.pendingInput() > 0) return true;
    // Everything written so far goes out NOW, because the worker is about to
    // stop running. `_start()` never returns — the guest's run loop is inside
    // it — so anything deferred to a microtask or a timer would sit in a queue
    // this thread will not reach until the program exits. The first version of
    // this batched output into `queueMicrotask` and drew a blank terminal: the
    // frames were all there, queued behind a call that had another hour to go.
    this.beforeBlock();
    const seen = Atomics.load(this.control, CONTROL_SEQUENCE);
    Atomics.wait(this.control, CONTROL_SEQUENCE, seen, timeoutMs === null ? Infinity : timeoutMs);
    return this.pendingInput() > 0;
  }

  // MARK: - The filesystem, such as it is

  resolve(path) {
    if (path.startsWith("/")) return normalise(path);
    return normalise("/" + path);
  }

  // MARK: - The imports

  exports() {
    const self = this;
    const encoder = new TextEncoder();

    /** Writes a list of NUL-terminated strings the way WASI's *_get calls want. */
    function writeStringList(strings, pointersPtr, dataPtr) {
      const view = self.view;
      let cursor = dataPtr;
      strings.forEach((entry, index) => {
        view.setUint32(pointersPtr + index * 4, cursor, true);
        const encoded = encoder.encode(entry + "\0");
        self.bytes.set(encoded, cursor);
        cursor += encoded.length;
      });
      return WASI_ESUCCESS;
    }

    function stringListSizes(strings, countPtr, sizePtr) {
      const view = self.view;
      view.setUint32(countPtr, strings.length, true);
      const total = strings.reduce((sum, entry) => sum + encoder.encode(entry + "\0").length, 0);
      view.setUint32(sizePtr, total, true);
      return WASI_ESUCCESS;
    }

    const environment = Object.entries(self.env).map(([key, value]) => `${key}=${value}`);

    return {
      args_get: (pointersPtr, dataPtr) => writeStringList(self.args, pointersPtr, dataPtr),
      args_sizes_get: (countPtr, sizePtr) => stringListSizes(self.args, countPtr, sizePtr),
      environ_get: (pointersPtr, dataPtr) => writeStringList(environment, pointersPtr, dataPtr),
      environ_sizes_get: (countPtr, sizePtr) => stringListSizes(environment, countPtr, sizePtr),

      clock_res_get: (_id, resultPtr) => {
        // A millisecond, honestly stated: `performance.now()` is deliberately
        // coarsened in browsers, and claiming nanoseconds would be a lie the
        // guest's frame pacing would believe.
        self.view.setBigUint64(resultPtr, 1_000_000n, true);
        return WASI_ESUCCESS;
      },
      clock_time_get: (id, _precision, resultPtr) => {
        const milliseconds = id === CLOCKID_REALTIME ? Date.now() : performance.now();
        self.view.setBigUint64(resultPtr, BigInt(Math.round(milliseconds * 1e6)), true);
        return WASI_ESUCCESS;
      },

      fd_write: (fd, iovsPtr, iovsLen, writtenPtr) => {
        if (fd !== 1 && fd !== 2) return WASI_EBADF;
        const view = self.view;
        let written = 0;
        const chunks = [];
        for (let index = 0; index < iovsLen; index++) {
          const base = view.getUint32(iovsPtr + index * 8, true);
          const length = view.getUint32(iovsPtr + index * 8 + 4, true);
          chunks.push(self.bytes.slice(base, base + length));
          written += length;
        }
        const total = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
        const merged = new Uint8Array(total);
        let cursor = 0;
        for (const chunk of chunks) {
          merged.set(chunk, cursor);
          cursor += chunk.length;
        }
        self.writeOut(merged);
        view.setUint32(writtenPtr, written, true);
        return WASI_ESUCCESS;
      },

      fd_read: (fd, iovsPtr, iovsLen, readPtr) => {
        const view = self.view;
        if (fd === 0) {
          // Never blocks, which is what a terminal in raw mode gives a POSIX
          // guest: `VMIN`/`VTIME` of zero means "hand me what you have, even if
          // that is nothing". The waiting is `poll_oneoff`'s job, and TUIkit
          // asks for it there — so a read that blocked here would park the
          // worker inside a call the guest expected to return at once, and the
          // app would draw its first frame and then freeze. `EAGAIN` is the
          // right nothing: the drain loop treats a negative return as "no bytes
          // this time" and carries on.
          if (self.pendingInput() === 0) return WASI_EAGAIN;
          let total = 0;
          for (let index = 0; index < iovsLen && self.pendingInput() > 0; index++) {
            const base = view.getUint32(iovsPtr + index * 8, true);
            const length = view.getUint32(iovsPtr + index * 8 + 4, true);
            const taken = self.takeInput(length);
            self.bytes.set(taken, base);
            total += taken.length;
          }
          view.setUint32(readPtr, total, true);
          return WASI_ESUCCESS;
        }
        const file = self.openFiles.get(fd);
        if (!file) return WASI_EBADF;
        let total = 0;
        for (let index = 0; index < iovsLen; index++) {
          const base = view.getUint32(iovsPtr + index * 8, true);
          const length = view.getUint32(iovsPtr + index * 8 + 4, true);
          const slice = file.data.subarray(file.offset, file.offset + length);
          self.bytes.set(slice, base);
          file.offset += slice.length;
          total += slice.length;
          if (slice.length < length) break;
        }
        view.setUint32(readPtr, total, true);
        return WASI_ESUCCESS;
      },

      poll_oneoff: (subscriptionsPtr, eventsPtr, count, resultPtr) => {
        // The call the whole design turns on. Two kinds of subscription arrive
        // here — "wake me in N nanoseconds" and "wake me when stdin has bytes"
        // — and the guest submits them together, which is exactly the race a
        // run loop wants. So: take the shortest clock timeout, then block on
        // the input ring for that long.
        const view = self.view;
        let timeoutMs = null;
        let wantsInput = false;
        for (let index = 0; index < count; index++) {
          const base = subscriptionsPtr + index * 48;
          const type = view.getUint8(base + 8);
          if (type === EVENTTYPE_CLOCK) {
            const timeout = Number(view.getBigUint64(base + 24, true));
            const flags = view.getUint16(base + 40, true);
            // An absolute deadline (flag bit 0) is relative to the clock the
            // subscription names; the guest only ever asks for a relative one,
            // so an absolute request is honoured as "do not wait".
            const relativeMs = flags & 1 ? 0 : timeout / 1e6;
            timeoutMs = timeoutMs === null ? relativeMs : Math.min(timeoutMs, relativeMs);
          } else if (type === EVENTTYPE_FD_READ) {
            wantsInput = true;
          }
        }
        if (wantsInput) {
          self.waitForInput(timeoutMs);
        } else if (timeoutMs !== null && timeoutMs > 0) {
          // A pure sleep: park on a word nothing will bump — after flushing,
          // for the reason `waitForInput` gives.
          self.beforeBlock();
          Atomics.wait(self.control, CONTROL_SEQUENCE, Atomics.load(self.control, CONTROL_SEQUENCE), timeoutMs);
        }

        // A clock subscription is always ready once the wait is over — that is
        // what the wait was. An fd subscription is ready only if bytes are
        // actually queued, and this is load-bearing rather than pedantic: a
        // guest told stdin is readable reads it, and a read with nothing behind
        // it is how a terminal app hangs.
        const ready = self.pendingInput() > 0;
        let produced = 0;
        for (let index = 0; index < count; index++) {
          const subscription = subscriptionsPtr + index * 48;
          const type = view.getUint8(subscription + 8);
          if (type === EVENTTYPE_FD_READ && !ready) continue;
          const event = eventsPtr + produced * 32;
          view.setBigUint64(event, view.getBigUint64(subscription, true), true);
          view.setUint16(event + 8, WASI_ESUCCESS, true);
          view.setUint8(event + 10, type);
          view.setBigUint64(event + 16, BigInt(self.pendingInput()), true);
          view.setUint16(event + 24, 0, true);
          produced += 1;
        }
        view.setUint32(resultPtr, produced, true);
        return WASI_ESUCCESS;
      },

      fd_fdstat_get: (fd, resultPtr) => {
        const view = self.view;
        let filetype = FILETYPE_UNKNOWN;
        if (fd <= 2) filetype = FILETYPE_CHARACTER_DEVICE;
        else if (fd === 3) filetype = FILETYPE_DIRECTORY;
        else if (self.openFiles.has(fd)) {
          filetype = self.openFiles.get(fd).isDirectory ? FILETYPE_DIRECTORY : FILETYPE_REGULAR_FILE;
        } else return WASI_EBADF;
        view.setUint8(resultPtr, filetype);
        view.setUint16(resultPtr + 2, 0, true);
        // Rights: everything. Nothing here enforces them, and a guest that
        // finds a right missing declines to do something it is allowed to do.
        view.setBigUint64(resultPtr + 8, 0xffffffffffffffffn, true);
        view.setBigUint64(resultPtr + 16, 0xffffffffffffffffn, true);
        return WASI_ESUCCESS;
      },
      fd_fdstat_set_flags: () => WASI_ESUCCESS,

      fd_prestat_get: (fd, resultPtr) => {
        if (fd !== 3) return WASI_EBADF;
        const view = self.view;
        view.setUint8(resultPtr, 0); // preopentype: dir
        view.setUint32(resultPtr + 4, 1, true); // length of "/"
        return WASI_ESUCCESS;
      },
      fd_prestat_dir_name: (fd, pathPtr, pathLen) => {
        if (fd !== 3 || pathLen < 1) return WASI_EBADF;
        self.bytes.set(encoder.encode("/"), pathPtr);
        return WASI_ESUCCESS;
      },

      path_open: (_dirFd, _dirFlags, pathPtr, pathLen, openFlags, _rights, _inheriting, _fdFlags, resultPtr) => {
        const path = self.resolve(readString(self.bytes, pathPtr, pathLen));
        const isDirectory = self.directories.has(path);
        let data = self.files.get(path);
        if (data === undefined && !isDirectory) {
          // O_CREAT is bit 0. A settings file the app is about to write is the
          // only thing that takes this path.
          if (openFlags & 1) {
            data = new Uint8Array(0);
            self.files.set(path, data);
          } else {
            return WASI_ENOENT;
          }
        }
        const fd = self.nextFd++;
        self.openFiles.set(fd, { path, data: data ?? new Uint8Array(0), offset: 0, isDirectory });
        self.view.setUint32(resultPtr, fd, true);
        return WASI_ESUCCESS;
      },

      fd_close: (fd) => {
        self.openFiles.delete(fd);
        return WASI_ESUCCESS;
      },
      fd_seek: (fd, offset, whence, resultPtr) => {
        const file = self.openFiles.get(fd);
        if (!file) return WASI_EBADF;
        const target = Number(offset);
        if (whence === 0) file.offset = target;
        else if (whence === 1) file.offset += target;
        else file.offset = file.data.length + target;
        self.view.setBigUint64(resultPtr, BigInt(file.offset), true);
        return WASI_ESUCCESS;
      },
      fd_tell: (fd, resultPtr) => {
        const file = self.openFiles.get(fd);
        if (!file) return WASI_EBADF;
        self.view.setBigUint64(resultPtr, BigInt(file.offset), true);
        return WASI_ESUCCESS;
      },
      fd_pread: (fd, iovsPtr, iovsLen, offset, readPtr) => {
        const file = self.openFiles.get(fd);
        if (!file) return WASI_EBADF;
        const saved = file.offset;
        file.offset = Number(offset);
        const status = self.exports().fd_read(fd, iovsPtr, iovsLen, readPtr);
        file.offset = saved;
        return status;
      },
      fd_filestat_get: (fd, resultPtr) => {
        const file = self.openFiles.get(fd);
        if (!file && fd > 3) return WASI_EBADF;
        writeFilestat(self.view, resultPtr, file ? file.data.length : 0,
          file && !file.isDirectory ? FILETYPE_REGULAR_FILE : FILETYPE_DIRECTORY);
        return WASI_ESUCCESS;
      },
      fd_write_file: () => WASI_ENOSYS,
      fd_sync: () => WASI_ESUCCESS,
      fd_filestat_set_size: () => WASI_ESUCCESS,
      fd_filestat_set_times: () => WASI_ESUCCESS,
      fd_readdir: (_fd, _bufPtr, _bufLen, _cookie, resultPtr) => {
        // Nothing here enumerates a directory; reporting "empty" is both true
        // of this filesystem's shape and harmless to the one caller
        // (`FileManager`, checking a config directory it is about to write to).
        self.view.setUint32(resultPtr, 0, true);
        return WASI_ESUCCESS;
      },

      path_filestat_get: (_dirFd, _flags, pathPtr, pathLen, resultPtr) => {
        const path = self.resolve(readString(self.bytes, pathPtr, pathLen));
        if (self.directories.has(path)) {
          writeFilestat(self.view, resultPtr, 0, FILETYPE_DIRECTORY);
          return WASI_ESUCCESS;
        }
        const data = self.files.get(path);
        if (data === undefined) return WASI_ENOENT;
        writeFilestat(self.view, resultPtr, data.length, FILETYPE_REGULAR_FILE);
        return WASI_ESUCCESS;
      },
      path_create_directory: (_dirFd, pathPtr, pathLen) => {
        self.directories.add(self.resolve(readString(self.bytes, pathPtr, pathLen)));
        return WASI_ESUCCESS;
      },
      path_remove_directory: (_dirFd, pathPtr, pathLen) => {
        self.directories.delete(self.resolve(readString(self.bytes, pathPtr, pathLen)));
        return WASI_ESUCCESS;
      },
      path_unlink_file: (_dirFd, pathPtr, pathLen) => {
        self.files.delete(self.resolve(readString(self.bytes, pathPtr, pathLen)));
        return WASI_ESUCCESS;
      },
      path_rename: () => WASI_ENOSYS,
      path_link: () => WASI_ENOSYS,
      path_symlink: () => WASI_ENOSYS,
      path_readlink: () => WASI_EINVAL,
      path_filestat_set_times: () => WASI_ESUCCESS,

      random_get: (bufferPtr, length) => {
        crypto.getRandomValues(self.bytes.subarray(bufferPtr, bufferPtr + length));
        return WASI_ESUCCESS;
      },

      proc_exit: (code) => {
        self.exitCode = code;
        throw new WASIExit(code);
      },
    };
  }
}

/** Thrown by `proc_exit` to unwind out of the guest. */
export class WASIExit extends Error {
  constructor(code) {
    super(`exited with ${code}`);
    this.code = code;
  }
}

// MARK: - Small helpers

function readString(bytes, pointer, length) {
  return new TextDecoder().decode(bytes.subarray(pointer, pointer + length));
}

function normalise(path) {
  const parts = [];
  for (const part of path.split("/")) {
    if (part === "" || part === ".") continue;
    if (part === "..") parts.pop();
    else parts.push(part);
  }
  return "/" + parts.join("/");
}

function writeFilestat(view, pointer, size, filetype) {
  view.setBigUint64(pointer, 0n, true); // device
  view.setBigUint64(pointer + 8, 0n, true); // inode
  view.setUint8(pointer + 16, filetype);
  view.setBigUint64(pointer + 24, 1n, true); // link count
  view.setBigUint64(pointer + 32, BigInt(size), true);
  view.setBigUint64(pointer + 40, 0n, true); // atime
  view.setBigUint64(pointer + 48, 0n, true); // mtime
  view.setBigUint64(pointer + 56, 0n, true); // ctime
}

// Unused status codes are named above for the reader's benefit; this keeps a
// linter from calling them dead.
export const STATUS = { WASI_EEXIST, WASI_ENOTDIR, WASI_ENOSYS, WASI_EINVAL, WASI_ENOENT };
