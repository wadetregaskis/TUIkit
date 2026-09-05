#!/usr/bin/env python3
"""Serves the WebAssembly demo with the two headers that make it work.

    Tools/Web/serve.py [port]        # default 8000, serves Tools/Web/site

`SharedArrayBuffer` — which is how the page hands keystrokes to the worker, and
how the worker parks while it waits for them — exists only on a *cross-origin
isolated* page, and a page is isolated only if the server says so with

    Cross-Origin-Opener-Policy: same-origin
    Cross-Origin-Embedder-Policy: require-corp

`python3 -m http.server` cannot set headers, which is the whole reason this file
exists rather than a line in the README. The third header below (`CORP`) lets
the worker and the wasm module load under that policy.

Only the standard library, like the rest of `Tools/`.
"""
import http.server
import json
import os
import re
import sys
from functools import partial

SITE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "site")
DATA = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "TerminalProbes", "data")


class IsolatedHandler(http.server.SimpleHTTPRequestHandler):
    """A static file server that opts the page into cross-origin isolation."""

    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".js": "text/javascript",
        ".json": "application/json",
    }

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        # The module is tens of megabytes and rebuilt often; a cached copy of
        # the previous build is a confusing way to spend an afternoon.
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_POST(self):
        """Saves a probe record into `Tools/TerminalProbes/data/`.

        `glyph-probe.html` measures a browser terminal against the shared width
        corpus, and the result belongs beside the records the Python probes
        write for real terminals. Copying ten kilobytes of JSON out of a browser
        by hand is how a measurement gets truncated, so the page posts it.

        Deliberately narrow: one directory, one extension, a name that cannot
        escape it, and a size limit. This is a probe's dev server, and it is
        bound to the loopback address, but "write a file where the page says"
        is still not a thing to leave general.
        """
        if self.path != "/save-probe":
            self.send_error(404)
            return
        name = self.headers.get("X-Probe-Name", "")
        if not re.fullmatch(r"[A-Za-z0-9._-]{1,80}", name) or name.startswith("."):
            self.send_error(400, "bad probe name")
            return
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > 4 * 1024 * 1024:
            self.send_error(400, "bad length")
            return
        body = self.rfile.read(length)
        try:
            parsed = json.loads(body)
        except ValueError:
            self.send_error(400, "not JSON")
            return
        target = os.path.join(DATA, f"{name}.json")
        with open(target, "w") as handle:
            json.dump(parsed, handle, indent=1, ensure_ascii=False, sort_keys=True)
            handle.write("\n")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(f"wrote {target}\n".encode())

    def log_message(self, format, *args):  # noqa: A002 - matching the base class
        # One line per request, without the date noise the base class prints.
        sys.stderr.write("  %s\n" % (format % args))


def main() -> int:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    if not os.path.isdir(SITE):
        print(f"no site directory at {SITE}", file=sys.stderr)
        return 1
    if not os.path.exists(os.path.join(SITE, "manifest.json")):
        print("no manifest.json — run Tools/Web/build.sh first", file=sys.stderr)
        return 1
    handler = partial(IsolatedHandler, directory=SITE)
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
    print(f"serving {SITE} on http://127.0.0.1:{port}/  (cross-origin isolated)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
