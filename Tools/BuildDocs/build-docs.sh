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
#   Tools/BuildDocs/build-docs.sh --preview [--port <n>]
#
#   --output <dir>     where to write TUIkit.doccarchive (default: .build/docs)
#   --static-hosting   emit a tree servable from a plain web server (GitHub Pages)
#   --analyze          report every diagnostic DocC can produce, not just errors
#   --preview          serve the docs locally instead of writing an archive,
#                      and print the URL to open (default port 8080)
#
# To read the docs:
#   --preview                     browse them; this runs DocC's own server
#   open <output>/TUIkit.doccarchive   read them in Xcode's documentation window
#
# A plain `python3 -m http.server` will NOT work on the built archive: the
# renderer is a single-page app, so a deep link like /documentation/tuikit has
# to be answered with index.html rather than a 404 or a redirect. Static hosts
# need the 404.html fallback that the CI publish step sets up; locally, use
# --preview.
#
# Exit status is DocC's: non-zero on error. Warnings do not fail the build.

set -euo pipefail
cd "$(dirname "$0")/../.."

OUTPUT=".build/docs"
STATIC_HOSTING=()
ANALYZE=()
PREVIEW=0
PORT=8080

while [ $# -gt 0 ]; do
    case "$1" in
        --output) OUTPUT="$2"; shift 2 ;;
        --static-hosting) STATIC_HOSTING=(--transform-for-static-hosting); shift ;;
        --analyze) ANALYZE=(--analyze); shift ;;
        --preview) PREVIEW=1; shift ;;
        --port) PORT="$2"; shift 2 ;;
        -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
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
#
# Its exit status is deliberately NOT the check here. The command takes no
# target selector — it walks every target in the package, test targets
# included — and a test target's module cannot be loaded by
# swift-symbolgraph-extract:
#
#     error: Failed to emit symbol graph for 'TUIkitPackageTests':
#            Couldn't load module 'TUIkitPackageTests' in the current SDK …
#
# so it exits non-zero having already written every library graph this script
# actually wants. Only a CLEAN checkout hits it: once the test bundle has been
# built its module loads, which is why this passed locally for anyone who had
# run `swift test`, and failed in CI on every run.
#
# Those test graphs are unwanted regardless — unify_symbol_graphs.py keeps only
# the five library modules. What matters is that each of those five produced a
# graph, and that is precisely what unify_symbol_graphs.py asserts (it errors
# with "no symbol graph for …" if any is missing), backed by the required-pages
# check at the end of this script. Both are stronger than an exit code, so the
# failure is reported and stepped over rather than being fatal here.
DUMP_LOG="$(mktemp)"
trap 'rm -f "$DUMP_LOG"' EXIT
if ! swift package dump-symbol-graph --minimum-access-level public | tee "$DUMP_LOG"; then
    echo "note: dump-symbol-graph reported errors (above); continuing — the" >&2
    echo "      library modules are verified individually in the next step." >&2
fi
SYMBOL_GRAPHS="$(sed -n 's/^Files written to //p' "$DUMP_LOG" | tail -1)"
if [ ! -d "${SYMBOL_GRAPHS:-}" ]; then
    echo "error: could not determine the symbol-graph directory" >&2
    exit 1
fi

echo "==> Unifying them under a single module identity"
STAGED="$(mktemp -d)"
trap 'rm -f "$DUMP_LOG"; rm -rf "$STAGED"' EXIT
python3 Tools/BuildDocs/unify_symbol_graphs.py "$SYMBOL_GRAPHS" "$STAGED"

if [ "$PREVIEW" -eq 1 ]; then
    echo "==> Serving — open http://localhost:$PORT/documentation/tuikit"
    exec "$DOCC" preview Sources/TUIkit/TUIkit.docc \
        --port "$PORT" \
        --fallback-display-name TUIkit \
        --fallback-bundle-identifier dev.tuikit.TUIkit \
        --additional-symbol-graph-dir "$STAGED"
fi

echo "==> Converting the catalog"
mkdir -p "$OUTPUT"
ARCHIVE="$OUTPUT/TUIkit.doccarchive"
rm -rf "$ARCHIVE"
"$DOCC" convert Sources/TUIkit/TUIkit.docc \
    --fallback-display-name TUIkit \
    --fallback-bundle-identifier dev.tuikit.TUIkit \
    --additional-symbol-graph-dir "$STAGED" \
    --output-path "$ARCHIVE" \
    --emit-lmdb-index \
    ${STATIC_HOSTING[@]+"${STATIC_HOSTING[@]}"} ${ANALYZE[@]+"${ANALYZE[@]}"}
    # `--emit-lmdb-index` writes index/navigator.index + data.mdb. Xcode's
    # documentation window reads THAT, not index.json: without it Xcode opens
    # the archive and shows an empty navigator, which looks exactly like the
    # archive failing to load. The swift-docc-plugin passes it as a matter of
    # course, which is why an archive built by hand behaves differently.
    #
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
