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
assertion='no generic environment'

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

row "Crash.swift: zero as () -> Any" Crash.swift
variant "zero returns Int, not some Any" 'func convert<Element>(_: Element) {
    func zero() -> Int { 0 }
    _ = zero as () -> Any
}'
variant "enclosing function not generic" 'func convert(_: Int) {
    func zero() -> some Any { 0 }
    _ = zero as () -> Any
}'
variant "underlying type uses Element" 'func convert<Element>(_: Element) {
    func zero() -> some Any { [Element]() }
    _ = zero as () -> Any
}'
variant "no conversion: a direct call" 'func convert<Element>(_: Element) {
    func zero() -> some Any { 0 }
    _ = zero()
}'
variant "conversion by annotation" 'func convert<Element>(_: Element) {
    func zero() -> some Any { 0 }
    let _: () -> Any = zero
}'
variant "wrapped in a closure instead" 'func convert<Element>(_: Element) {
    func zero() -> some Any { 0 }
    _ = { zero() } as () -> Any
}'
variant "methods of a generic struct" 'struct Holder<Element> {
    func zero() -> some Any { 0 }
    func convert() { _ = zero as () -> Any }
}'
variant "a destructuring closure instead" 'func convert<Element>(_: Element) {
    func zero() -> some Any { 0 }
    _ = [(0, 0)].map { _, _ in zero() }
}'
variant "one closure parameter, not destructured" 'func convert<Element>(_: Element) {
    func zero() -> some Any { 0 }
    _ = [(0, 0)].map { _ in zero() }
}'
variant "destructuring, zero generic at top level" 'func zero<Element>(_: Element) -> some Any { 0 }
func convert<Element>(_ element: Element) {
    _ = [(0, 0)].map { _, _ in zero(element) }
}'
variant "destructuring, zero outside generic context" 'func zero() -> some Any { 0 }
func convert<Element>(_: Element) {
    _ = [(0, 0)].map { _, _ in zero() }
}'
variant "the old repro: generic type, destructuring" 'func each<T, R>(_ values: [T], _ transform: (T) -> R) -> [R] { values.map(transform) }
struct Core<Root> {
    func bar(pairs: [(Int, String)]) -> [some Equatable] { each(pairs) { _, string in helper(string) } }
    func helper(_ string: String) -> some Equatable { string }
}'
