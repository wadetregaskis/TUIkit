#!/usr/bin/env python3
"""
Analyze an Instruments **Time Profiler** `.trace` and print the hot
functions — with zero external dependencies (only `xcrun xctrace`, which
you already have, and the Python standard library).

It exports the trace's `time-profile` table to XML via `xctrace export`,
then aggregates CPU time by:

  • self time  — the leaf frame of each sample (where the CPU actually was)
  • inclusive  — every distinct function on a sample's stack
  • module     — per-binary self time (your code vs. system libraries)
  • app only   — self/inclusive restricted to non-system binaries, i.e.
                 TUIkit + TUIkitExample, so your own hot code stands out

Why not just use DuckDB / the instruments-analyzer skill? Instruments'
XML dedups recurring stack frames with an id/ref scheme: the first
occurrence of `swift_release` is `<frame id="11" name="swift_release">`,
every later occurrence is `<frame ref="11"/>` with NO name. Parsers that
don't resolve those frame refs drop the name on every repeat — which
silently undercounts the hottest (most-repeated) functions. This script
resolves them, so a function that recurs across thousands of samples is
attributed correctly.

Usage:
    analyze_timeprofile.py TRACE [--run N] [--top N] [--thread main|all]
                                 [--state running|all]

All weights are nanoseconds in the trace; reported as milliseconds.
"""
import argparse
import io
import os
import subprocess
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict

SYSTEM_PREFIXES = ("/usr/", "/System/", "/Library/", "/var/", "/private/var/")
UNSYMBOLICATED = "<unsymbolicated>"


def export_table(trace: str, run: int, schema: str) -> str:
    xpath = f'/trace-toc/run[@number="{run}"]/data/table[@schema="{schema}"]'
    proc = subprocess.run(
        ["xcrun", "xctrace", "export", "--input", trace, "--xpath", xpath],
        capture_output=True, text=True)
    if proc.returncode != 0 or not proc.stdout.strip():
        sys.exit(f"xctrace export failed for schema '{schema}':\n{proc.stderr}")
    return proc.stdout


def is_app(path: str) -> bool:
    """A binary that is part of the app under test, not a system library."""
    return bool(path) and not path.startswith(SYSTEM_PREFIXES)


def analyze(trace: str, run: int, top: int, thread_filter: str, state_filter: str):
    xml = export_table(trace, run, "time-profile")

    # Global id -> value maps. Instruments shares ONE id namespace across
    # all element types, and a `ref` always re-appears as the same element
    # type it was defined as, so per-type maps keyed by the global id are
    # unambiguous.
    weight_by_id, thread_by_id, state_by_id = {}, {}, {}
    frame_by_id = {}    # id -> (name, binary_name, binary_path)
    binary_by_id = {}   # id -> (binary_name, binary_path)

    self_ms, self_n = defaultdict(float), defaultdict(int)
    incl_ms = defaultdict(float)
    mod_ms = defaultdict(float)
    app_self_ms = defaultdict(float)
    app_incl_ms = defaultdict(float)
    thread_ms = defaultdict(float)

    total_ms = 0.0
    rows = 0

    def resolve_weight(el):
        ref = el.get("ref")
        if ref is not None:
            return weight_by_id.get(ref, 0)
        val = int((el.text or "0").strip() or 0)
        if el.get("id") is not None:
            weight_by_id[el.get("id")] = val
        return val

    def resolve_thread(el):
        ref = el.get("ref")
        if ref is not None:
            return thread_by_id.get(ref, "")
        val = el.get("fmt", "")
        if el.get("id") is not None:
            thread_by_id[el.get("id")] = val
        return val

    def resolve_state(el):
        ref = el.get("ref")
        if ref is not None:
            return state_by_id.get(ref, "")
        val = el.get("fmt", "")
        if el.get("id") is not None:
            state_by_id[el.get("id")] = val
        return val

    def resolve_frame(f):
        ref = f.get("ref")
        if ref is not None:
            return frame_by_id.get(ref, (UNSYMBOLICATED, "", ""))
        name = f.get("name") or UNSYMBOLICATED
        # Collapse PLT trampolines into the function they jump to, so a
        # hot cross-module call shows up as one line, not two.
        if name.startswith("DYLD-STUB$$"):
            name = name[len("DYLD-STUB$$"):]
        bname, bpath = "", ""
        b = f.find("binary")
        if b is not None:
            bref = b.get("ref")
            if bref is not None:
                bname, bpath = binary_by_id.get(bref, ("", ""))
            else:
                bname, bpath = b.get("name", ""), b.get("path", "")
                if b.get("id") is not None:
                    binary_by_id[b.get("id")] = (bname, bpath)
        if f.get("id") is not None:
            frame_by_id[f.get("id")] = (name, bname, bpath)
        return (name, bname, bpath)

    # Stream the (potentially large) XML row by row.
    for _event, el in ET.iterparse(io.StringIO(xml), events=("end",)):
        if el.tag != "row":
            continue
        rows += 1

        w_el = el.find("weight")
        weight = resolve_weight(w_el) if w_el is not None else 0
        ms = weight / 1e6

        th_el = el.find("thread")
        thread = resolve_thread(th_el) if th_el is not None else ""

        st_el = el.find("thread-state")
        state = resolve_state(st_el) if st_el is not None else ""

        bt = el.find("backtrace")
        # Resolve every frame in document order (defs precede refs) so the
        # id maps stay correct even when we later .clear() the element.
        frames = [resolve_frame(f) for f in bt.findall("frame")] if bt is not None else []
        el.clear()

        if state_filter == "running" and state != "Running":
            continue
        if thread_filter == "main" and "Main Thread" not in thread:
            continue
        if not frames:
            continue

        total_ms += ms
        thread_ms[thread.split(" (")[0] or "?"] += ms

        leaf_name, _leaf_bn, leaf_bp = frames[0]
        self_ms[leaf_name] += ms
        self_n[leaf_name] += 1
        mod_ms[frames[0][1] or "<unknown>"] += ms
        if is_app(leaf_bp):
            app_self_ms[leaf_name] += ms

        seen, seen_app = set(), set()
        for name, _bn, bp in frames:
            if name in seen:
                continue
            seen.add(name)
            incl_ms[name] += ms
            if is_app(bp) and name not in seen_app:
                seen_app.add(name)
                app_incl_ms[name] += ms

    return {
        "rows": rows, "total_ms": total_ms, "thread_ms": thread_ms,
        "self_ms": self_ms, "self_n": self_n, "incl_ms": incl_ms,
        "mod_ms": mod_ms, "app_self_ms": app_self_ms, "app_incl_ms": app_incl_ms,
        "top": top,
    }


def print_table(title, items, total_ms, top, counts=None):
    print(f"\n## {title}")
    print(f"{'ms':>9}  {'%':>6}  {'n':>6}  function" if counts is not None
          else f"{'ms':>9}  {'%':>6}  function")
    ranked = sorted(items.items(), key=lambda kv: kv[1], reverse=True)[:top]
    for name, ms in ranked:
        pct = (ms / total_ms * 100) if total_ms else 0
        short = name if len(name) <= 78 else name[:75] + "..."
        if counts is not None:
            print(f"{ms:9.1f}  {pct:6.1f}  {counts.get(name,0):6d}  {short}")
        else:
            print(f"{ms:9.1f}  {pct:6.1f}  {short}")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("trace")
    ap.add_argument("--run", type=int, default=1)
    ap.add_argument("--top", type=int, default=30)
    ap.add_argument("--thread", choices=["main", "all"], default="all",
                    help="restrict to the Main Thread (the render loop) or all threads")
    ap.add_argument("--state", choices=["running", "all"], default="running",
                    help="restrict to on-CPU samples (default) or include all")
    args = ap.parse_args()

    if not os.path.exists(args.trace):
        sys.exit(f"no such trace: {args.trace}")

    r = analyze(args.trace, args.run, args.top, args.thread, args.state)

    print("=" * 78)
    print(f"Time Profiler analysis: {args.trace}")
    print(f"samples={r['rows']:,}  on-CPU≈{r['total_ms']:.0f} ms  "
          f"thread={args.thread}  state={args.state}")
    print("per-thread on-CPU ms: " + ", ".join(
        f"{t}={ms:.0f}" for t, ms in
        sorted(r["thread_ms"].items(), key=lambda kv: kv[1], reverse=True)[:6]))
    print("=" * 78)

    t = r["total_ms"]
    print_table("Self time — leaf frames (where the CPU actually was)",
                r["self_ms"], t, r["top"], counts=r["self_n"])
    print_table("Inclusive time — every function on the stack",
                r["incl_ms"], t, r["top"])
    print_table("Self time by module (your code vs. system)",
                r["mod_ms"], t, r["top"])
    print_table("APP ONLY — self time in TUIkit / TUIkitExample",
                r["app_self_ms"], t, r["top"])
    print_table("APP ONLY — inclusive time in TUIkit / TUIkitExample",
                r["app_incl_ms"], t, r["top"])


if __name__ == "__main__":
    main()
