#!/bin/bash
#
#  🖥️ TUIKit — Terminal UI Kit for Swift
#  generate.sh
#
#  Created by LAYERED.work
#  License: MIT
#
#  Regenerates Sources/TUIkit/SFSymbols/SFSymbolTable.generated.swift from the
#  installed SF Symbols app. macOS only; requires the SF Symbols app (Beta or
#  release) in /Applications. See README.md and GenerateSFSymbols.swift.
#
#  Usage:  Tools/GenerateSFSymbols/generate.sh ["/path/to/SF Symbols.app"]
#
#  Run from the repository root (the output path is repo-relative).

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"

source_file="Tools/GenerateSFSymbols/GenerateSFSymbols.swift"
binary="$(mktemp -t generate-sfsymbols)"
trap 'rm -f "$binary"' EXIT

# `-undefined dynamic_lookup` lets the @_silgen_name binding to the private
# CoreGlyphsLib.Crypton decryptor link; it is resolved at run time by the
# dlopen() calls in the program.
swiftc -O \
    -framework CoreText -framework Foundation \
    -Xlinker -undefined -Xlinker dynamic_lookup \
    -o "$binary" "$source_file"

"$binary" "$@"
