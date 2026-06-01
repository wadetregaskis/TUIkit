#!/usr/bin/env bash
#
# Record an Instruments Time Profiler trace of TUIkitExample while a
# scripted scenario drives it, then print the hot functions.
#
# This is the end-to-end ("Mode B") profiling flow: it profiles the real
# app the way a user exercises it (input -> dispatch -> render -> diff ->
# write). For deterministic micro-profiling of the render pipeline alone,
# see the (proposed) headless harness in README.md.
#
# Usage:
#   Tools/Profiling/record.sh [scenario] [seconds] [rows] [cols]
#
# Examples:
#   Tools/Profiling/record.sh              # tour, 15s, 50x160
#   Tools/Profiling/record.sh emoji 20     # hammer the emoji list for 20s
#   Tools/Profiling/record.sh idle 12      # steady-state per-frame cost
#
# Requires: a macOS toolchain with `xcrun xctrace` (Instruments) and
# python3. Run from the repository root.
set -euo pipefail

SCENARIO="${1:-tour}"
SECS="${2:-15}"
ROWS="${3:-50}"
COLS="${4:-160}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

echo "==> Building TUIkitExample (release, with debug symbols)…"
swift build -c release --product TUIkitExample -Xswiftc -g
BIN="$(swift build -c release --product TUIkitExample --show-bin-path)/TUIkitExample"
[ -x "$BIN" ] || { echo "build did not produce $BIN" >&2; exit 1; }

OUTDIR="$REPO_ROOT/profiling-traces"
mkdir -p "$OUTDIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
TRACE="$OUTDIR/${SCENARIO}-${STAMP}.trace"

echo "==> Recording '$SCENARIO' for ${SECS}s at ${COLS}x${ROWS} → $TRACE"
python3 "$REPO_ROOT/Tools/Profiling/drive.py" "$BIN" \
    --scenario "$SCENARIO" --rows "$ROWS" --cols "$COLS" \
    --trace "$TRACE" --time-limit "$((SECS * 1000))"

echo "==> Analyzing…"
python3 "$REPO_ROOT/Tools/Profiling/analyze_timeprofile.py" "$TRACE" --top 25

echo
echo "Trace saved at: $TRACE"
echo "Re-analyze any time with:"
echo "  python3 Tools/Profiling/analyze_timeprofile.py \"$TRACE\" --thread main --top 40"
