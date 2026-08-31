#!/bin/bash
# Compiles Crash.swift and a set of near-misses, printing which ones assert.
#
#   ./variants.sh                       # uses `swiftc` from PATH
#   ./variants.sh /path/to/xctoolchain  # uses that toolchain's swiftc
set -u
cd "$(dirname "$0")" || exit 2
swiftc_bin="swiftc"
[ $# -ge 1 ] && swiftc_bin="$1/usr/bin/swiftc"
sdk=$(xcrun --show-sdk-path)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

emit() { # $1 = file, $2 = Region words, $3 = Event words, $4 = property decl
    {
        echo "struct Region {"
        for i in $(seq 1 "$2"); do echo "    var f$i = 0"; done
        echo "}"
        echo "struct Event {"
        for i in $(seq 1 "$3"); do echo "    var f$i = 0"; done
        echo "}"
        echo "final class Box {"
        echo "    $4"
        echo "}"
    } > "$1"
}

check() { # $1 = label, $2 = file
    printf '%-40s' "$1"
    if "$swiftc_bin" -c -Onone -swift-version 6 -sdk "$sdk" \
        -target arm64-apple-macos14.0 -o /dev/null "$2" 2>&1 |
        grep -q "LoadableByAddress"; then
        echo "ASSERTS"
    else
        echo "ok"
    fi
}

tuple='var pending: (region: Region, handler: (Event) -> Bool)?'
emit "$work/a.swift" 3 5 "$tuple"
check "3-word field, 5-word closure arg" "$work/a.swift"
emit "$work/b.swift" 2 5 "$tuple"
check "2-word field (tuple not large)" "$work/b.swift"
emit "$work/c.swift" 3 4 "$tuple"
check "4-word closure arg (arg not large)" "$work/c.swift"
emit "$work/d.swift" 3 5 'var pending: (Region, (Event) -> Bool)?'
check "unlabelled tuple" "$work/d.swift"
emit "$work/e.swift" 3 5 'var pending: (region: Region, handler: (Event) -> Bool) = (Region(), { _ in false })'
check "not Optional" "$work/e.swift"
emit "$work/f.swift" 3 5 'var pending: (region: Region, other: Event)?'
check "no closure in the tuple" "$work/f.swift"
{
    echo "struct Region { var a = 0, b = 0, c = 0 }"
    echo "struct Event { var a = 0, b = 0, c = 0, d = 0, e = 0 }"
    echo "struct Pending { var region: Region; var handler: (Event) -> Bool }"
    echo "final class Box { var pending: Pending? }"
} > "$work/g.swift"
check "a struct instead of a tuple" "$work/g.swift"
