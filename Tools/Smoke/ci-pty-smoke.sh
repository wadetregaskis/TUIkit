#!/usr/bin/env bash
#
# The PTY half of the CI smoke test: drive both apps through a real terminal.
#
# `Stress --selfcheck` (run separately, on every CI lane including Windows)
# proves the render stack produces output, but it never opens a terminal. The
# crash classes that only appear in the interactive render loop — the
# 2026-07-17 debug-build stack overflow being the canonical one — are invisible
# to it and to the 3,000+ unit tests. This script is that net.
#
# POSIX only: tui_walk.py uses pty/termios/fcntl. A Windows equivalent needs
# ConPTY and does not exist yet, so the Windows lanes run --selfcheck alone.
#
# Usage: Tools/Smoke/ci-pty-smoke.sh [quick|full] [build-dir]
#
#   quick  (default) — a shallow walk, ~1 minute. Cheap enough to run on every
#                      CI lane, which is the point: an interactive-only crash
#                      that is specific to one Swift version or architecture
#                      still gets caught.
#   full             — every menu item, ~7 minutes. One lane per OS runs this.
#
# The split exists because tui_walk settles 0.25s after every keystroke and
# returns the cursor to the top between items, so cost grows with the SQUARE of
# the item count: 34 items is ~1,100 keystrokes, 12 items is ~130.

set -euo pipefail

DEPTH="${1:-quick}"
BUILD_DIR="${2:-.build/debug}"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
VENV="${TMPDIR:-/tmp}/tuikit-smoke-venv"

case "$DEPTH" in
    quick) EXAMPLE_ITEMS=12; STRESS_ITEMS=6 ;;
    full)  EXAMPLE_ITEMS=34; STRESS_ITEMS=15 ;;
    *)     echo "usage: $0 [quick|full] [build-dir]" >&2; exit 2 ;;
esac

# pyte is the screen reconstructor; a venv keeps this working on distros that
# mark the system Python externally-managed (PEP 668), which Ubuntu 24.04 does.
if [ ! -x "$VENV/bin/python" ]; then
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --quiet --disable-pip-version-check pyte
fi

# Never the developer's — or the runner's — real preferences.
export TUIKIT_CONFIG_DIR="${TUIKIT_CONFIG_DIR:-${TMPDIR:-/tmp}/tuikit-smoke-config}"

# Item counts are entries in each app's top-level menu. Walking past the end is
# harmless (Down saturates on the last row), so these stay correct as pages are
# added — but raise the `full` counts to keep coverage complete.
walk() {
    local binary="$1" count="$2"
    if [ ! -x "$REPO/$BUILD_DIR/$binary" ]; then
        echo "error: $BUILD_DIR/$binary not built" >&2
        return 1
    fi
    echo "── PTY walk ($DEPTH): $binary, $count items ──"
    "$VENV/bin/python" "$HERE/tui_walk.py" "$REPO/$BUILD_DIR/$binary" "$count" --settle 0.5
}

cd "$REPO"
walk Example "$EXAMPLE_ITEMS"
walk Stress  "$STRESS_ITEMS"
echo "PTY smoke ($DEPTH): both apps survived."
