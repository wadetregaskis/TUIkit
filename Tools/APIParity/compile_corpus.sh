#!/bin/sh
#  🖥️ TUIkit — Terminal UI Kit for Swift
#  compile_corpus.sh
#
#  Type-checks CompileCorpus.swift against the built TUIkit modules. Nothing is
#  run and nothing is linked: a clean exit IS the assertion, because every
#  snippet in that file is SwiftUI source that must bind to something here.
#
#  Usage:  swift build && Tools/APIParity/compile_corpus.sh [debug|release]
#
#  Created by Wade Tregaskis
#  License: MIT
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
configuration=${1:-debug}
modules="$repo/.build/$configuration/Modules"

if [ ! -d "$modules" ]; then
    echo "no modules at $modules — run 'swift build' first" >&2
    exit 1
fi

swiftc -typecheck -I "$modules" "$here/CompileCorpus.swift"
echo "compile corpus: every SwiftUI snippet type-checks against TUIkit"
