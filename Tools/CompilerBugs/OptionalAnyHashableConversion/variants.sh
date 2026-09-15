#!/bin/bash
# Builds Tests/ReproTests/Crash.swift and a set of near-misses, each in a fresh
# copy of this package, printing which ones stop the compiler.
#
#   ./variants.sh                        # `swift` from PATH
#   ./variants.sh +6.3.3                 # `swiftly run swift … +6.3.3`
#   ./variants.sh /path/to/usr/bin/swift # that swift
#
# On macOS, swift-testing's macros come from Xcode, so set
# DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer for a swift.org
# toolchain.
#
# "error" means the variant failed to build for some other reason, so it says
# nothing either way about the abort.
set -u
cd "$(dirname "$0")" || exit 2
selector="${1:-}"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

build() { # in the current directory
    case "$selector" in
    "") swift build --build-tests --scratch-path "$work/build" ;;
    +*) swiftly run swift build --build-tests --scratch-path "$work/build" "$selector" ;;
    *) "$selector" build --build-tests --scratch-path "$work/build" ;;
    esac
}

check() { # $1 = label, $2 = the test file
    printf '%-44s' "$1"
    rm -rf "$work/pkg" "$work/build"
    mkdir -p "$work/pkg/Tests/ReproTests"
    cp Package.swift "$work/pkg/"
    cp "$2" "$work/pkg/Tests/ReproTests/Crash.swift"
    local out status
    out=$(cd "$work/pkg" && build 2>&1)
    status=$?
    if grep -q "TYPE MISMATCH IN ARGUMENT" <<<"$out"; then
        echo "ASSERTS"
    elif [ $status -ne 0 ]; then
        echo "error"
    else
        echo "ok"
    fi
}

variant() { # $1 = label, $2 = value()'s declaration, $3 = the test's body
    printf 'import Testing\n\n%s\n\n@Test func product() {\n    %s\n}\n' "$2" "$3" > "$work/variant.swift"
    check "$1" "$work/variant.swift"
}

optional='func value() -> Int64? { 1_050_000_003 }'

check "#expect(Int64? == 9 * 116_666_667)" Tests/ReproTests/Crash.swift
variant "a literal, not a product" "$optional" '#expect(value() == 1_050_000_003)'
variant "a sum, not a product" "$optional" '#expect(value() == 1 + 1_050_000_002)'
variant "the product typed, Int64(9) * ..." "$optional" '#expect(value() == Int64(9) * 116_666_667)'
variant "value not optional" 'func value() -> Int64 { 1_050_000_003 }' '#expect(value() == 9 * 116_666_667)'
variant "Int?, not Int64?" 'func value() -> Int? { 1_050_000_003 }' '#expect(value() == 9 * 116_666_667)'
variant "compared outside #expect" "$optional" 'let equal = value() == 9 * 116_666_667; #expect(equal)'
