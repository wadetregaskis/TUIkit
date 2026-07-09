#!/bin/bash
#
#  🖥️ TUIKit — Terminal UI Kit for Swift
#  generate.sh
#
#  Created by Wade Tregaskis
#  License: MIT
#
#  Regenerates Sources/TUIkitImage/ImageGlyphCalibration.generated.swift by
#  rasterising the reference monospace font (SF Mono Regular 11) and measuring
#  glyph ink coverage. macOS only (CoreText). See README.md and
#  main.swift.
#
#  Usage:  Tools/GenerateImageGlyphs/generate.sh
#
#  Run from the repository root (the output path is repo-relative).

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"

source_file="Tools/GenerateImageGlyphs/main.swift"
# Compile the framework's own sampling geometry INTO the tool, so the tool and
# the runtime share one definition of the circle centres / radius / spiral and
# cannot drift apart.
shared_file="Sources/TUIkitImage/ShapeSampling.swift"
binary="$(mktemp -t generate-image-glyphs)"
trap 'rm -f "$binary"' EXIT

swiftc -O \
    -framework AppKit -framework CoreText -framework CoreGraphics -framework Foundation \
    -o "$binary" "$shared_file" "$source_file"

"$binary" "$@"
