#!/bin/bash
#
# 🖥️ TUIkit — Terminal UI Kit for Swift
# build.sh — builds the Example app for the browser.
#
#   Tools/Web/build.sh [--debug] [--no-opt]
#
# Produces `Tools/Web/site/`: the wasm module, the resource bundles SwiftPM
# built, and a manifest saying which guest path each of those files has to
# appear at. Serve it with `Tools/Web/serve.py`.
#
# Prerequisites, and why they are not the toolchain you build the rest with:
#
#   * a swift.org toolchain, not Xcode's. Xcode's compiler is built without the
#     WebAssembly LLVM target and stops at "No available targets are compatible
#     with triple wasm32-unknown-wasip1".
#   * 6.3 or newer. On 6.2.4 the compiler asserts on `TupleView`'s
#     pack-expansion conformance (SILGenPoly, `isPreconcurrency`) — see
#     CONTRIBUTING.md.
#   * the matching WebAssembly SDK. The SDK must be the *same version* as the
#     toolchain or the module files will not load.
#
#       swiftly install 6.3.3
#       swift sdk install \
#         https://download.swift.org/swift-6.3.3-release/wasm-sdk/swift-6.3.3-RELEASE/swift-6.3.3-RELEASE_wasm.artifactbundle.tar.gz \
#         --checksum <the one swift.org publishes>
#
set -euo pipefail

TOOLCHAIN_VERSION="${TUIKIT_WASM_TOOLCHAIN:-6.3.3}"
SDK_NAME="${TUIKIT_WASM_SDK:-swift-${TOOLCHAIN_VERSION}-RELEASE_wasm}"
CONFIGURATION="release"
RUN_WASM_OPT=1

for argument in "$@"; do
    case "$argument" in
        --debug) CONFIGURATION="debug" ;;
        --no-opt) RUN_WASM_OPT=0 ;;
        *) echo "unknown option: $argument" >&2; exit 2 ;;
    esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SITE="$ROOT/Tools/Web/site"
TOOLCHAIN="$HOME/Library/Developer/Toolchains/swift-${TOOLCHAIN_VERSION}-RELEASE.xctoolchain"
SWIFT="$TOOLCHAIN/usr/bin/swift"

if [ ! -x "$SWIFT" ]; then
    echo "no swift.org toolchain at $TOOLCHAIN" >&2
    echo "install one with: swiftly install ${TOOLCHAIN_VERSION}" >&2
    exit 1
fi
if ! swift sdk list 2>/dev/null | grep -qx "$SDK_NAME"; then
    echo "no Swift SDK named '$SDK_NAME' (see the header of this script)" >&2
    echo "installed SDKs:" >&2
    swift sdk list >&2 || true
    exit 1
fi

# The stack size is a real requirement, not a precaution. A view tree is
# rendered by recursion, and wasm's default 64 KB of linear-memory stack runs
# out inside the Example's deeper pages; 16 MB matches what the native builds
# get from the main thread.
echo "── building Example.wasm ($CONFIGURATION, SDK $SDK_NAME)"
"$SWIFT" build \
    --package-path "$ROOT" \
    -c "$CONFIGURATION" \
    --swift-sdk "$SDK_NAME" \
    --static-swift-stdlib \
    --product Example \
    -Xlinker -z -Xlinker stack-size=16777216 \
    -Xlinker --strip-debug

BIN="$("$SWIFT" build --package-path "$ROOT" -c "$CONFIGURATION" --swift-sdk "$SDK_NAME" --show-bin-path)"
MODULE="$BIN/Example.wasm"
[ -f "$MODULE" ] || { echo "no module at $MODULE" >&2; exit 1; }

mkdir -p "$SITE/resources"
rm -rf "$SITE/resources"/*

if [ "$RUN_WASM_OPT" = "1" ] && command -v wasm-opt >/dev/null 2>&1; then
    echo "── wasm-opt -Os"
    wasm-opt -Os --strip-debug --strip-dwarf "$MODULE" -o "$SITE/Example.wasm"
else
    [ "$RUN_WASM_OPT" = "1" ] && echo "── wasm-opt not found; shipping the linker's output"
    cp "$MODULE" "$SITE/Example.wasm"
fi

# The resource bundles, and the manifest that says where the guest expects to
# find each file. SwiftPM compiles the bundle's location into the binary as an
# absolute host path, so the page serves the files under exactly that path —
# there is no way to ask the module to look somewhere else.
echo "── collecting resource bundles"
python3 - "$BIN" "$SITE" <<'PYTHON'
import json, os, shutil, sys

build_dir, site = sys.argv[1], sys.argv[2]
resources = os.path.join(site, "resources")
files, directories = [], set()

for bundle in sorted(os.listdir(build_dir)):
    if not bundle.endswith(".resources"):
        continue
    source = os.path.join(build_dir, bundle)
    for base, _, names in os.walk(source):
        for name in names:
            host = os.path.join(base, name)
            guest = os.path.join(build_dir, bundle, os.path.relpath(host, source))
            served = os.path.relpath(host, build_dir)
            target = os.path.join(resources, served)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            shutil.copy2(host, target)
            files.append({"path": guest, "url": "./resources/" + served.replace(os.sep, "/")})
            directories.add(os.path.dirname(guest))

manifest = {
    "wasm": "./Example.wasm",
    "argv0": "Example",
    "files": files,
    "directories": sorted(directories | {"/config"}),
}
with open(os.path.join(site, "manifest.json"), "w") as handle:
    json.dump(manifest, handle, indent=2)
print(f"   {len(files)} resource file(s)")
PYTHON

SIZE=$(du -h "$SITE/Example.wasm" | cut -f1)
echo "── done: $SITE/Example.wasm ($SIZE)"
echo "   serve it with: Tools/Web/serve.py"
