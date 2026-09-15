#!/bin/bash
# Compiles Crash.swift and a set of near-misses with each toolchain given, and
# prints one row per variant and one column per toolchain.
#
#   ./variants.sh                # `swiftc` from PATH
#   ./variants.sh TOOLCHAIN...   # each an .xctoolchain directory
#
# README.md's table is the output of:
#
#   tcs=~/Library/Developer/Toolchains
#   ./variants.sh "$tcs/swift-6.2.4-RELEASE.xctoolchain" \
#       /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain \
#       "$tcs/swift-6.3.3-RELEASE.xctoolchain" \
#       "$tcs/swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-09-10-a.xctoolchain"
#
# A column is headed with its compiler's version, "Xcode" for Xcode's build, and
# "+a" for a build with assertions. The cells:
#   ABORTS   the assertion this directory is about
#   BAD SIL  -sil-verify-all rejected the SIL
#   ok       compiled
#   error    failed some other way, which says nothing either way
# Only a build with assertions can abort, so "ok" from a build without them does
# not show that the bug is absent. Builds without assertions still honour
# -sil-verify-all.
#
# The assertion is in the LoadableByAddress pass, which runs on the way to
# IRGen, so each variant is compiled to an object (-c) rather than to SILGen's
# output.
set -u
cd "$(dirname "$0")" || exit 2
assertion='LoadableByAddress.cpp'

compilers=()
if [ $# -eq 0 ]; then
    compilers=(swiftc)
else
    for toolchain in "$@"; do compilers+=("$toolchain/usr/bin/swiftc"); done
fi
sdk=$(xcrun --sdk macosx --show-sdk-path)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

print_line() { # $1 = line, printed without its trailing spaces
    local line="$1"
    printf '%s\n' "${line%"${line##*[! ]}"}"
}

heading() { # $1 = swiftc
    local version name
    version=$("$1" -version 2>&1)
    name=$(sed -n 's/.*Swift version \([^ ]*\).*/\1/p' <<<"$version" | head -n 1)
    case "$version" in *swiftlang-*) name="Xcode $name" ;; esac
    case "$version" in *+assertions*) name="$name +a" ;; esac
    printf '%s' "$name"
}

compile() { # $1 = swiftc, $2 = file; prints one cell
    local out status
    out=$(perl -e 'alarm 180; exec @ARGV' "$1" -c -Onone -Xfrontend -sil-verify-all \
        -sdk "$sdk" -o /dev/null "$2" 2>&1)
    status=$?
    if grep -q "$assertion" <<<"$out"; then
        echo "ABORTS"
    elif grep -q "SIL verification failed" <<<"$out"; then
        echo "BAD SIL"
    elif [ $status -eq 0 ]; then
        echo "ok"
    else
        echo "error"
    fi
}

row() { # $1 = label, $2 = file
    local line swiftc
    line=$(printf '%-48s' "$1")
    for swiftc in "${compilers[@]}"; do line+=$(printf '%-14s' "$(compile "$swiftc" "$2")"); done
    print_line "$line"
}

variant() { # $1 = label, $2 = Region words, $3 = Event words, $4 = Box's property, $5 = more declarations
    {
        echo "struct Region {"
        for i in $(seq 1 "$2"); do echo "    var f$i = 0"; done
        echo "}"
        echo "struct Event {"
        for i in $(seq 1 "$3"); do echo "    var f$i = 0"; done
        echo "}"
        [ -n "${5:-}" ] && echo "$5"
        echo "final class Box {"
        echo "    $4"
        echo "}"
    } > "$work/variant.swift"
    row "$1" "$work/variant.swift"
}

line=$(printf '%-48s' "")
for swiftc in "${compilers[@]}"; do line+=$(printf '%-14s' "$(heading "$swiftc")"); done
print_line "$line"

tuple='var pending: (region: Region, handler: (Event) -> Bool)?'
row "Crash.swift: 3-word field, 5-word closure arg" Crash.swift
variant "2-word field (tuple not large)" 2 5 "$tuple"
variant "4-word closure arg (arg not large)" 3 4 "$tuple"
variant "unlabelled tuple" 3 5 'var pending: (Region, (Event) -> Bool)?'
variant "not Optional" 3 5 'var pending: (region: Region, handler: (Event) -> Bool) = (Region(), { _ in false })'
variant "no closure in the tuple" 3 5 'var pending: (region: Region, other: Event)?'
variant "a struct instead of a tuple" 3 5 'var pending: Pending?' \
    'struct Pending { var region: Region; var handler: (Event) -> Bool }'
