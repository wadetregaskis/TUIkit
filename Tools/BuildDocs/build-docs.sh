#!/usr/bin/env bash
#
# build-docs.sh — build the TUIkit documentation as ONE unified archive.
#
# Every public symbol lands under /documentation/tuikit/, whichever library
# module declares it, because the module split is an implementation detail of
# the package and not something a reader should have to know. See
# unify_symbol_graphs.py for how (and why the obvious approach does not work).
#
# Usage:
#   Tools/BuildDocs/build-docs.sh [--output <dir>] [--static-hosting] [--analyze]
#
#   --output <dir>     where to write TUIkit.doccarchive (default: .build/docs)
#   --static-hosting   emit a tree servable from a plain web server (GitHub Pages)
#   --analyze          report every diagnostic DocC can produce, not just errors
#
# Exit status is DocC's: non-zero on error. Warnings do not fail the build.

set -euo pipefail
cd "$(dirname "$0")/../.."

OUTPUT=".build/docs"
STATIC_HOSTING=()
ANALYZE=()

while [ $# -gt 0 ]; do
    case "$1" in
        --output) OUTPUT="$2"; shift 2 ;;
        --static-hosting) STATIC_HOSTING=(--transform-for-static-hosting); shift ;;
        --analyze) ANALYZE=(--analyze); shift ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

DOCC="${DOCC:-$(xcrun --find docc 2>/dev/null || command -v docc)}"
if [ -z "$DOCC" ]; then
    echo "error: docc not found — install a Swift toolchain or set \$DOCC" >&2
    exit 1
fi

echo "==> Emitting symbol graphs for every target"
# `dump-symbol-graph` prints the directory it wrote to; capture it rather than
# guessing, since the path carries the build triple.
DUMP_LOG="$(mktemp)"
trap 'rm -f "$DUMP_LOG"' EXIT
swift package dump-symbol-graph --minimum-access-level public | tee "$DUMP_LOG"
SYMBOL_GRAPHS="$(sed -n 's/^Files written to //p' "$DUMP_LOG" | tail -1)"
if [ ! -d "${SYMBOL_GRAPHS:-}" ]; then
    echo "error: could not determine the symbol-graph directory" >&2
    exit 1
fi

echo "==> Unifying them under a single module identity"
STAGED="$(mktemp -d)"
trap 'rm -f "$DUMP_LOG"; rm -rf "$STAGED"' EXIT
python3 Tools/BuildDocs/unify_symbol_graphs.py "$SYMBOL_GRAPHS" "$STAGED"

echo "==> Converting the catalog"
mkdir -p "$OUTPUT"
ARCHIVE="$OUTPUT/TUIkit.doccarchive"
rm -rf "$ARCHIVE"
"$DOCC" convert Sources/TUIkit/TUIkit.docc \
    --fallback-display-name TUIkit \
    --fallback-bundle-identifier dev.tuikit.TUIkit \
    --additional-symbol-graph-dir "$STAGED" \
    --output-path "$ARCHIVE" \
    ${STATIC_HOSTING[@]+"${STATIC_HOSTING[@]}"} ${ANALYZE[@]+"${ANALYZE[@]}"}
    # (the `[@]+` guards are for macOS's bash 3.2, where `set -u` treats an
    # empty array expansion as an unbound variable)

PAGES=$(find "$ARCHIVE/data/documentation" -name '*.json' | wc -l | tr -d ' ')
echo "==> $ARCHIVE ($PAGES pages)"

# A regression guard with teeth: these types live in the sibling modules, and
# their absence is the exact failure this script exists to prevent. Cheap to
# check, and it fails loudly the day someone documents just one target again.
MISSING=()
for symbol in view color binding state environmentvalues framebuffer palette; do
    [ -e "$ARCHIVE/data/documentation/tuikit/$symbol.json" ] || MISSING+=("$symbol")
done
if [ ${#MISSING[@]} -gt 0 ]; then
    echo "error: no page for ${MISSING[*]} — the modules did not get unified" >&2
    exit 1
fi
