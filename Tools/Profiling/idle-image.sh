#!/usr/bin/env bash
#
# idle-image.sh — does an on-screen `Image` stop the run loop going idle?
#
# `idle_cpu.py` can already answer "what does a static screen cost?", but only
# for a screen that is genuinely static. Every `Example` page that shows an
# `Image` also carries focusable controls, and a focused control pulses — so the
# loop is legitimately awake and the reading says nothing about the image.
#
# `IdleProbe` is the smallest app that can be asked: one view, nothing
# focusable, no timers. This runs it in each mode over the same window so the
# three numbers can be compared:
#
#   text     the CONTROL. Known static. Anything but ~0 here means the harness,
#            the terminal, or the framework's baseline is the source — not the
#            view under test, and nothing else in the run is interpretable.
#   image    the SUBJECT.
#   spinner  the known-NOT-idle case, proving the measurement can see activity
#            at all. ~0 here would mean the probe is broken, not efficient.
#
# Usage:
#   Tools/Profiling/idle-image.sh [window_s] [/path/to/image]
#
# With no image path the probe points at a file that does not exist, which is
# the *cheaper* test: the load fails fast and settles, and anything still
# burning CPU afterwards is the render path rather than the decoder. Pass a real
# file to measure a decoded image instead.
#
# Each run gets its own TUIKIT_CONFIG_DIR. Without that a PTY probe writes to
# the real preferences directory — $HOME does not isolate it on macOS.

set -euo pipefail
cd "$(dirname "$0")/../.."

WINDOW="${1:-5}"
IMAGE="${2:-}"

echo "Building IdleProbe (release)…"
swift build -c release --product IdleProbe >/dev/null
BIN="$(swift build -c release --product IdleProbe --show-bin-path)/IdleProbe"

printf '\n%-10s %s\n' "mode" "reading"
printf '%-10s %s\n' "----------" "-----------------------------"

for mode in text image spinner; do
    config_dir="$(mktemp -d)"
    # `|| true`: a probe that dies should print its failure and let the other
    # modes still run — one bad mode must not hide the comparison.
    reading="$(
        IDLE_PROBE_MODE="$mode" \
        IDLE_PROBE_IMAGE="$IMAGE" \
        TUIKIT_CONFIG_DIR="$config_dir" \
            python3 Tools/Profiling/idle_cpu.py "$BIN" 2.5 "$WINDOW" 2>&1 | tail -1
    )" || reading="FAILED"
    rm -rf "$config_dir"
    printf '%-10s %s\n' "$mode" "$reading"
done

cat <<'NOTE'

Reading it:
  text ~= image        an Image costs nothing extra when nothing is happening.
  image >> text        the render path is asking for frames it does not need —
                       the suspect is _ImageCore's unconditional
                       `lastSourceBox.value = source`, which invalidates on
                       every pass because StateBox cannot compare values.
  spinner ~= text      the measurement is not working; fix that before
                       believing either of the other two.
NOTE
