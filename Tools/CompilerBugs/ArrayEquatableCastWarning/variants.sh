#!/bin/bash
# Type-checks Warning.swift and a set of near-misses with each toolchain given,
# then RUNS the cast, and prints one row per variant and one column per
# toolchain.
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
#       "$tcs/swift-6.4.0-RELEASE.xctoolchain"
#
# A column is headed with its compiler's version, "Xcode" for Xcode's build,
# and "+a" for a build with assertions. The cells of a type-check row:
#   WARNS    "conditional cast … always succeeds" was reported
#   quiet    type-checked with no such warning — the correct answer
#   error    failed some other way, which says nothing either way
#
# The "run" rows are the point of the exercise: they show what the cast the
# compiler called redundant actually does. A row reading `fails` is a cast the
# warning said would always succeed.
set -u
cd "$(dirname "$0")" || exit 2
warning='always succeeds'

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

classify() { # $1 = compiler output, $2 = its exit status; prints one cell
    if grep -q "$warning" <<<"$1"; then
        echo "WARNS"
    elif [ "$2" -eq 0 ]; then
        echo "quiet"
    else
        echo "error"
    fi
}

check() { # $1 = swiftc, $2 = file; prints one cell
    local out status
    out=$(perl -e 'alarm 180; exec @ARGV' "$1" -swift-version 6 -parse-as-library \
        -typecheck -sdk "$sdk" "$2" 2>&1)
    status=$?
    classify "$out" "$status"
}

row() { # $1 = label, $2 = file
    local line swiftc
    line=$(printf '%-48s' "$1")
    for swiftc in "${compilers[@]}"; do line+=$(printf '%-14s' "$(check "$swiftc" "$2")"); done
    print_line "$line"
}

variant() { # $1 = label, $2 = source
    printf '%s\n' "$2" > "$work/variant.swift"
    row "$1" "$work/variant.swift"
}

line=$(printf '%-48s' "")
for swiftc in "${compilers[@]}"; do line+=$(printf '%-14s' "$(heading "$swiftc")"); done
print_line "$line"

row "Warning.swift: [Plain] and [Row] to Equatable" Warning.swift
variant "the same, with no import" 'struct Plain { let x: Int }
func f(_ rows: [Plain]) -> Bool { (rows as? any Equatable) != nil }'
variant "[Row] to Hashable, Foundation" 'import Foundation
func f<Row>(_ rows: [Row]) -> Bool { (rows as? any Hashable) != nil }'
variant "Plain itself, not an array, Foundation" 'import Foundation
struct Plain { let x: Int }
func f(_ row: Plain) -> Bool { (row as? any Equatable) != nil }'
variant "a Dictionary, Foundation" 'import Foundation
struct Plain { let x: Int }
func f(_ rows: [String: Plain]) -> Bool { (rows as? any Equatable) != nil }'
variant "Set<Row> to Equatable, Foundation" 'import Foundation
func f<Row: Hashable>(_ rows: Set<Row>) -> Bool { (rows as? any Equatable) != nil }'
variant "Set<Row> to Equatable, no import" 'func f<Row: Hashable>(_ rows: Set<Row>) -> Bool { (rows as? any Equatable) != nil }'
variant "[Row] to CustomStringConvertible, no import" 'func f<Row>(_ rows: [Row]) -> Bool { (rows as? any CustomStringConvertible) != nil }'
variant "the collection as ONE generic, Foundation" 'import Foundation
func f<Rows>(_ rows: Rows) -> Bool { (rows as? any Equatable) != nil }'

# Now run it. The last two variants are the honest answer the warning denies.
cat > "$work/runtime.swift" <<'EOF'
import Foundation
struct Plain { let x: Int }
struct Comparable_: Equatable { let x: Int }
func isComparable<Row>(_ rows: [Row]) -> Bool { (rows as? any Equatable) != nil }
switch CommandLine.arguments[1] {
case "plain": print(isComparable([Plain(x: 1)]) ? "succeeds" : "fails")
case "equatable": print(isComparable([Comparable_(x: 1)]) ? "succeeds" : "fails")
case "empty-plain": print(isComparable([Plain]()) ? "succeeds" : "fails")
default: break
}
EOF
index=0
for swiftc in "${compilers[@]}"; do
    out=$(perl -e 'alarm 180; exec @ARGV' "$swiftc" -swift-version 6 -Onone -sdk "$sdk" \
        -o "$work/runtime-$index" "$work/runtime.swift" 2>&1)
    status=$?
    if [ $status -eq 0 ]; then echo ok > "$work/runtime-$index.cell"; else echo error > "$work/runtime-$index.cell"; fi
    index=$((index + 1))
done

run() { # $1 = label, $2 = case
    local line index=0 swiftc cell out status
    line=$(printf '%-48s' "$1")
    for swiftc in "${compilers[@]}"; do
        cell=$(cat "$work/runtime-$index.cell")
        if [ "$cell" = "ok" ]; then
            out=$(perl -e 'alarm 30; exec @ARGV' "$work/runtime-$index" "$2" 2>/dev/null)
            status=$?
            if [ $status -eq 0 ]; then cell="$out"; else cell="trap ($status)"; fi
        fi
        line+=$(printf '%-14s' "$cell")
        index=$((index + 1))
    done
    print_line "$line"
}
run "run: [Plain] as? any Equatable" plain
run "run: [Equatable] as? any Equatable" equatable
run "run: empty [Plain] as? any Equatable" empty-plain
