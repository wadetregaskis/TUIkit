#!/bin/bash
# Compiles Crash.swift and a set of near-misses with each toolchain given, runs
# the conversion where it compiles, and prints one row per variant and one
# column per toolchain.
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
# "+a" for a build with assertions. The cells of a compile row:
#   ABORTS   the assertion this directory is about
#   BAD SIL  -sil-verify-all rejected what SILGen emitted
#   ok       compiled
#   error    failed some other way, which says nothing either way
# Only a build with assertions can abort, so "ok" from a build without them does
# not show that the bug is absent. Builds without assertions still honour
# -sil-verify-all. A "run" row prints what the program printed, or the exit
# status it trapped with.
#
# The #expect rows need swift-testing: a swift.org toolchain's own copy, or
# Xcode's from the SDK platform xcrun finds.
set -u
cd "$(dirname "$0")" || exit 2
assertion='TYPE MISMATCH IN ARGUMENT'

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

testing_flags() { # $1 = swiftc; prints one flag per line
    local resources
    resources=$("$1" -print-target-info -sdk "$sdk" 2>/dev/null |
        sed -n 's/.*"runtimeResourcePath": "\(.*\)".*/\1/p' | head -n 1)
    if [ -d "$resources/macosx/testing" ]; then
        printf '%s\n' -I "$resources/macosx/testing"
    else
        printf '%s\n' -F "$(xcrun --sdk macosx --show-sdk-platform-path)/Developer/Library/Frameworks"
    fi
    printf '%s\n' -plugin-path "$resources/host/plugins/testing"
}

classify() { # $1 = compiler output, $2 = its exit status; prints one cell
    if grep -q "$assertion" <<<"$1"; then
        echo "ABORTS"
    elif grep -q "SIL verification failed" <<<"$1"; then
        echo "BAD SIL"
    elif [ "$2" -eq 0 ]; then
        echo "ok"
    else
        echo "error"
    fi
}

compile() { # $1 = swiftc, $2 = file, $3 = "testing" or empty; prints one cell
    local out status flags=()
    if [ -n "$3" ]; then
        while IFS= read -r flag; do flags+=("$flag"); done < <(testing_flags "$1")
    fi
    out=$(perl -e 'alarm 180; exec @ARGV' "$1" -emit-silgen -Xfrontend -sil-verify-all \
        -sdk "$sdk" ${flags[@]+"${flags[@]}"} -o /dev/null "$2" 2>&1)
    status=$?
    classify "$out" "$status"
}

row() { # $1 = label, $2 = file, $3 = "testing" or empty
    local line swiftc
    line=$(printf '%-44s' "$1")
    for swiftc in "${compilers[@]}"; do line+=$(printf '%-14s' "$(compile "$swiftc" "$2" "${3:-}")"); done
    print_line "$line"
}

variant() { # $1 = label, $2 = source, $3 = "testing" or empty
    printf '%s\n' "$2" > "$work/variant.swift"
    row "$1" "$work/variant.swift" "${3:-}"
}

line=$(printf '%-44s' "")
for swiftc in "${compilers[@]}"; do line+=$(printf '%-14s' "$(heading "$swiftc")"); done
print_line "$line"

row "Crash.swift: to (Int?) -> Void" Crash.swift
variant "a function: to (Int?) -> Void" 'func convert(_ body: @escaping (AnyHashable) -> Void) -> (Int?) -> Void { body }'
variant "a function: to (Value?) -> Void, generic" 'func convert<Value: Hashable>(_ body: @escaping (AnyHashable) -> Void) -> (Value?) -> Void { body }'
variant "result: () -> Int? to () -> AnyHashable" 'func convert(_ body: @escaping () -> Int?) -> () -> AnyHashable { body }'
variant "#expect's expansion, in plain Swift" 'func check<T, U>(_ lhs: T, _ op: (T, () -> U) -> Bool, _ rhs: @escaping @autoclosure () -> U) -> Bool { op(lhs, rhs) }
func value() -> Int64? { 1_050_000_003 }
func test() -> Bool { check(value(), { $0 == $1() }, 9 * 116_666_667) }'
variant "the same, one literal" 'func check<T, U>(_ lhs: T, _ op: (T, () -> U) -> Bool, _ rhs: @escaping @autoclosure () -> U) -> Bool { op(lhs, rhs) }
func value() -> Int64? { 1_050_000_003 }
func test() -> Bool { check(value(), { $0 == $1() }, 1_050_000_003) }'
variant "to (Int) -> Void, not Optional" '_ = { (_: AnyHashable) in } as (Int) -> Void'
variant "from Any, not AnyHashable" '_ = { (_: Any) in } as (Int?) -> Void'
variant "from AnyHashable?, not AnyHashable" '_ = { (_: AnyHashable?) in } as (Int?) -> Void'
variant "a value, not a function" 'let erased: AnyHashable = Int?.none'
variant "a closure that erases it itself" 'func convert(_ body: @escaping (AnyHashable) -> Void) -> (Int?) -> Void { { body(AnyHashable($0)) } }'

expectation() { # $1 = label, $2 = the test's body
    variant "$1" "import Testing
func value() -> Int64? { 1_050_000_003 }
@Test func product() { $2 }" testing
}
expectation "#expect(Int64? == 9 * 116_666_667)" '#expect(value() == 9 * 116_666_667)'
expectation "#expect(Int64? == 1 + 1_050_000_002)" '#expect(value() == 1 + 1_050_000_002)'
expectation "#expect(Int64? == 1_050_000_003)" '#expect(value() == 1_050_000_003)'
expectation "#expect(Int64? == Int64(9) * 116_666_667)" '#expect(value() == Int64(9) * 116_666_667)'
expectation "#expect of a let holding the comparison" 'let equal = value() == 9 * 116_666_667; #expect(equal)'

# Run the conversion, -Onone, with each compiler that builds it.
cat > "$work/runtime.swift" <<'EOF'
func convert(_ body: @escaping (AnyHashable) -> String) -> (Int?) -> String { body }
let describe: (AnyHashable) -> String = { "\($0)" }
switch CommandLine.arguments[1] {
case "direct-nil": print(describe(Int?.none))
case "direct-5": print(describe(Int?.some(5)))
case "converted-nil": print(convert(describe)(nil))
case "converted-5": print(convert(describe)(5))
default: break
}
EOF
index=0
for swiftc in "${compilers[@]}"; do
    out=$(perl -e 'alarm 180; exec @ARGV' "$swiftc" -Onone -sdk "$sdk" \
        -o "$work/runtime-$index" "$work/runtime.swift" 2>&1)
    classify "$out" $? > "$work/runtime-$index.cell"
    index=$((index + 1))
done

run() { # $1 = label, $2 = case
    local line index=0 swiftc cell out status
    line=$(printf '%-44s' "$1")
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
run "run: nil, erased directly" direct-nil
run "run: 5, erased directly" direct-5
run "run: nil through (Int?) -> String" converted-nil
run "run: 5 through (Int?) -> String" converted-5
