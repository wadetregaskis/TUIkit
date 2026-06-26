#!/usr/bin/env python3
"""Regenerate TUIkit's DocC architecture diagrams from source.

Usage:
    python3 Tools/Diagrams/build.py            # write all diagrams
    python3 Tools/Diagrams/build.py --list     # list diagram names
    python3 Tools/Diagrams/build.py --stdout NAME   # print one SVG (light) to stdout

Each diagram is rendered to ``<name>.svg`` and ``<name>~dark.svg`` in the DocC
Resources directory; DocC swaps to the ``~dark`` variant automatically. To change
a diagram, edit its builder below and re-run — no external tools required.

The diagram CONTENT is the source of truth for "how the loop works", so keep it
in step with the prose in the matching DocC article (and with the code).
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tuidiagram import Flow, write_pair  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
RESOURCES = os.path.join(REPO, "Sources", "TUIkit", "TUIkit.docc", "Resources")


# --------------------------------------------------------------------------
# Diagram definitions. Each returns a Flow.
# --------------------------------------------------------------------------

def lifecycle_main_loop() -> Flow:
    """AppLifecycle.md — setup → demand-driven loop → cleanup."""
    f = Flow(title="TUIkit application lifecycle and demand-driven main loop")
    f.step("setup", "Terminal setup",
           ["install signals · alt screen", "raw mode · mouse tracking"], kind="terminal")
    f.step("observers", "Register observers",
           ["AppState → requestRerender", "focus change → needsRender + wake()"])
    f.step("timers", "Prepare animation timers",
           ["Pulse · Cursor — started only while", "a rendered frame consumes them"])
    f.step("initial", "Render first frame")
    f.step("shutdown", "shouldShutdown?", kind="decision")
    f.step("resize", "Consume resize flag",
           ["on SIGWINCH, invalidate the diff cache"])
    f.step("input", "Drain & dispatch input",
           ["≤ 128 events / frame", "keys: 5 layers · mouse: hit-test"])
    f.step("render", "Render if a frame is due",
           ["at most once per App.maxFrameRate"])
    f.step("block", "Block until woken",
           ["input · render request · signal", "static screen ⇒ zero renders"], kind="accent")
    f.branch("cleanup", "shutdown", "Cleanup",
             ["restore terminal", "show cursor · exit"], kind="terminal")

    for a, b in [("setup", "observers"), ("observers", "timers"),
                 ("timers", "initial"), ("initial", "shutdown"),
                 ("resize", "input"), ("input", "render"), ("render", "block")]:
        f.edge(a, b)
    f.edge("shutdown", "resize", label="no")
    f.edge("shutdown", "cleanup", label="yes", route="right")
    f.edge("block", "shutdown", route="loopback")
    return f


def architecture_event_loop() -> Flow:
    """Architecture.md — the demand-driven, frame-capped event loop."""
    f = Flow(title="TUIkit demand-driven, frame-capped event loop")
    f.step("init", "Subsystems initialised",
           ["Terminal · AppState · Focus · TUIContext",
            "RenderLoop · InputHandler · signal handlers"], kind="terminal")
    f.step("shutdown", "shouldShutdown?", kind="decision")
    f.step("resize", "Consume resize flag",
           ["SIGWINCH → invalidate diff cache"])
    f.step("input", "Drain & dispatch input",
           ["≤ 128 events / frame", "keys → 5 layers · mouse → hit-test"])
    f.step("render", "Render if a frame is due",
           ["coalesce requests · ≤ App.maxFrameRate"])
    f.step("block", "Block until woken",
           ["input · render request · signal", "self-pipe delivers SIGWINCH"], kind="accent")
    f.branch("cleanup", "shutdown", "Cleanup & exit",
             ["restore the terminal"], kind="terminal")

    for a, b in [("init", "shutdown"), ("resize", "input"),
                 ("input", "render"), ("render", "block")]:
        f.edge(a, b)
    f.edge("shutdown", "resize", label="no")
    f.edge("shutdown", "cleanup", label="yes", route="right")
    f.edge("block", "shutdown", route="loopback")
    return f


DIAGRAMS = {
    "lifecycle-main-loop": lifecycle_main_loop,
    "architecture-event-loop": architecture_event_loop,
}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--list", action="store_true", help="list diagram names and exit")
    ap.add_argument("--stdout", metavar="NAME", help="print one diagram's light SVG to stdout")
    args = ap.parse_args()

    if args.list:
        for name in DIAGRAMS:
            print(name)
        return 0
    if args.stdout:
        if args.stdout not in DIAGRAMS:
            print(f"unknown diagram {args.stdout!r}; choices: {', '.join(DIAGRAMS)}", file=sys.stderr)
            return 2
        sys.stdout.write(DIAGRAMS[args.stdout]().render("light"))
        return 0

    os.makedirs(RESOURCES, exist_ok=True)
    for name, fn in DIAGRAMS.items():
        for path in write_pair(fn(), RESOURCES, name):
            print("wrote", os.path.relpath(path, REPO))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
