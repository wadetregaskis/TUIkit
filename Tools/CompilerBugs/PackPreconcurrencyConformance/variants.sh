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
#   BAD SIL  -sil-verify-all rejected what SILGen emitted
#   ok       compiled
#   error    failed some other way, which says nothing either way
# Only a build with assertions can abort, so "ok" from a build without them does
# not show that the bug is absent. Builds without assertions still honour
# -sil-verify-all.
set -u
cd "$(dirname "$0")" || exit 2
assertion='isPreconcurrency'

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
    out=$(perl -e 'alarm 180; exec @ARGV' "$1" -emit-silgen -Xfrontend -sil-verify-all \
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

variant() { # $1 = label, $2 = source
    printf '%s\n' "$2" > "$work/variant.swift"
    row "$1" "$work/variant.swift"
}

line=$(printf '%-48s' "")
for swiftc in "${compilers[@]}"; do line+=$(printf '%-14s' "$(heading "$swiftc")"); done
print_line "$line"

runner='protocol Runner { func run() }'

row "Crash.swift: actor, pack, @preconcurrency" Crash.swift
variant "struct, @MainActor witness" "$runner
struct Holder<each Element>: @preconcurrency Runner { @MainActor func run() {} }"
variant "@MainActor struct storing a pack, Equatable" '@MainActor struct Holder<each Element> { let elements: (repeat each Element) }
extension Holder: @preconcurrency Equatable { static func == (lhs: Self, rhs: Self) -> Bool { true } }'
variant "stdlib protocol, property requirement" 'struct Holder<each Element>: @preconcurrency CustomStringConvertible {
    @MainActor var description: String { "" }
}'
variant "pack on an enclosing type" "$runner
struct Outer<each Element> { actor Holder: @preconcurrency Runner { func run() {} } }"
variant "no pack: actor Holder<Element>" "$runner
actor Holder<Element>: @preconcurrency Runner { func run() {} }"
variant "no pack: struct, @MainActor witness" "$runner
struct Holder: @preconcurrency Runner { @MainActor func run() {} }"
variant "requirement async" 'protocol Runner { func run() async }
actor Holder<each Element>: @preconcurrency Runner { func run() async {} }'
variant "witness nonisolated" "$runner
actor Holder<each Element>: @preconcurrency Runner { nonisolated func run() {} }"
variant "isolated conformance, @MainActor Equatable" '@MainActor struct Holder<each Element> { let elements: (repeat each Element) }
extension Holder: @MainActor Equatable { static func == (lhs: Self, rhs: Self) -> Bool { true } }'
