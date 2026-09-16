#!/bin/bash
# Builds and RUNS a small swift-testing package for Crash.swift and a set of
# near-misses with each toolchain given, and prints one row per variant and one
# column per toolchain.
#
#   ./variants.sh                # the `swift` on PATH
#   ./variants.sh TOOLCHAIN...   # each an .xctoolchain directory
#
# README.md's table is the output of:
#
#   tcs=~/Library/Developer/Toolchains
#   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./variants.sh \
#       "$tcs/swift-6.2.4-RELEASE.xctoolchain" \
#       /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain \
#       "$tcs/swift-6.3.3-RELEASE.xctoolchain" \
#       "$tcs/swift-6.4.0-RELEASE.xctoolchain"
#
# A column is headed with its compiler's version, "Xcode" for Xcode's build, and
# "+a" for a build with assertions. The cells:
#   MISMATCH  the 'function type mismatch' error this directory is about
#   WRONG     built, then ran one closure in place of another
#   ok        built, and both closures ran their own bodies
#   error     failed some other way, which says nothing either way
#
# The oracle is the RUN, not the compile. On 6.2 and 6.3 this bug emits NO
# diagnostic — it silently drops one closure's body and calls the other — so a
# clean compile says nothing. Either of the two closures can be the one that loses
# its body, so every variant asserts a result for BOTH: the macro's predicate is
# true of every cell and the source closure's is not, so a conflation in EITHER
# direction flips an answer and fails the test. An `ok` that rests on an assertion
# only one direction can fail is worth nothing.
#
# Each variant is built through SwiftPM rather than by calling swiftc directly, so
# that every toolchain uses its OWN swift-testing and its own macro plugin. That
# is load-bearing: Xcode's 6.2.4 and swift.org's 6.2.4 ship DIFFERENT
# swift-testing builds (Testing Library 1501 against 6.2.4/5ee435b) and land on
# different sides of this bug, and pointing one toolchain's compiler at another's
# swift-testing reports collisions the real build does not have.
set -u
cd "$(dirname "$0")" || exit 2

compilers=()
if [ $# -eq 0 ]; then
    compilers=(swift)
else
    for toolchain in "$@"; do compilers+=("$toolchain/usr/bin/swift"); done
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
pkg="$work/pkg"
mkdir -p "$pkg/Tests/RTests"
cat > "$pkg/Package.swift" <<'EOF'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "R",
    targets: [.testTarget(name: "RTests", path: "Tests/RTests")])
EOF

print_line() { # $1 = line, printed without its trailing spaces
    local line="$1"
    printf '%s\n' "${line%"${line##*[! ]}"}"
}

heading() { # $1 = swift
    local version name
    version=$("$1" --version 2>&1)
    name=$(sed -n 's/.*Swift version \([^ ]*\).*/\1/p' <<<"$version" | head -n 1)
    case "$version" in *swiftlang-*) name="Xcode $name" ;; esac
    case "$version" in *+assertions*) name="$name +a" ;; esac
    printf '%s' "$name"
}

run() { # $1 = swift, $2 = scratch path; prints one cell
    local out status
    out=$(perl -e 'alarm 600; exec @ARGV' "$1" test --package-path "$pkg" \
        --scratch-path "$2" 2>&1)
    status=$?
    if grep -q 'function type mismatch' <<<"$out"; then
        echo "MISMATCH"
    elif [ $status -eq 0 ]; then
        echo "ok"
    elif grep -q 'Test run with' <<<"$out"; then
        echo "WRONG"
    else
        echo "error"
    fi
}

row() { # $1 = label; the test file is already in place
    local line index=0 swift
    line=$(printf '%-46s' "$1")
    for swift in "${compilers[@]}"; do
        line+=$(printf '%-14s' "$(run "$swift" "$work/build-$index")")
        index=$((index + 1))
    done
    print_line "$line"
}

# $1 = the declarations inside the suite, $2 = the body of the test function,
# $3 = the row's label.
variant() {
    {
        cat <<'HEAD'
import Testing

struct State { var flag = false }

func withCurrent<T>(_ body: () throws -> T) rethrows -> T { try body() }

@Suite struct R {
HEAD
        printf '%s\n' "$1"
        printf '%s\n' "    @Test func t() throws {"
        printf '%s\n' "$2"
        printf '%s\n' "    }"
        printf '%s\n' "}"
    } > "$pkg/Tests/RTests/RTests.swift"
    row "$3"
}

# The usual element: "a" is not flagged, "b" and "c" are, and none is "z".
tuple_cells='    func cells() -> [(character: Character, state: State)] {
        [("a", State(flag: false)), ("b", State(flag: true)), ("c", State(flag: true))]
    }'
# The macro's closure holds for EVERY cell; the source closure's holds for two.
# Borrowing either body in place of the other therefore flips a result.
macro_first='            #expect(drawn.allSatisfy { $0.character != "z" }, "the closure in the macro")'
source_filter='            let flagged = drawn.filter { $0.state.flag }'
check_filter='            #expect(flagged.map(\.character) == ["b", "c"], "\(flagged.map(\.character))")'

line=$(printf '%-46s' "")
for swift in "${compilers[@]}"; do line+=$(printf '%-14s' "$(heading "$swift")"); done
print_line "$line"

cp Crash.swift "$pkg/Tests/RTests/RTests.swift"
row "Crash.swift: macro closure, then filter"

variant "$tuple_cells" "        withCurrent {
            let drawn = cells()
$source_filter
$macro_first
$check_filter
        }" "one source closure BEFORE the macro"

variant "$tuple_cells" "        withCurrent {
            let drawn = cells()
$source_filter
            let others = drawn.filter { !\$0.state.flag }
$macro_first
$check_filter
            #expect(others.map(\\.character) == [\"a\"], \"\\(others.map(\\.character))\")
        }" "two source closures before the macro"

variant "$tuple_cells" "        withCurrent {
            let drawn = cells()
$macro_first
            let all = drawn.allSatisfy { \$0.state.flag }
            #expect(all == false, \"allSatisfy ran the predicate from the macro\")
        }" "partner allSatisfy, not filter (no error)"

variant "$tuple_cells" "        let drawn = cells()
$macro_first
$source_filter
$check_filter" "no enclosing closure"

variant "$tuple_cells
    func check(_ value: Bool, _ note: @autoclosure () -> String = \"\") {
        #expect(value, \"\\(note())\")
    }" "        withCurrent {
            let drawn = cells()
            check(drawn.allSatisfy { \$0.character != \"z\" }, \"the closure in the call\")
$source_filter
$check_filter
        }" "the macro call moved out of this scope"

variant "$tuple_cells" "        try withCurrent {
            let drawn = cells()
            let found = try #require(drawn.first { \$0.character == \"c\" })
            #expect(found.character == \"c\", \"#require ran the wrong closure: \\(found.character)\")
$source_filter
$check_filter
        }" "#require instead of #expect"

variant '    struct Cell { var character: Character; var state: State }
    func cells() -> [Cell] {
        [Cell(character: "a", state: State(flag: false)),
         Cell(character: "b", state: State(flag: true)),
         Cell(character: "c", state: State(flag: true))]
    }' "        withCurrent {
            let drawn = cells()
$macro_first
$source_filter
$check_filter
        }" "a struct element, not a tuple"

variant '    func cells() -> [(Character, State)] {
        [("a", State(flag: false)), ("b", State(flag: true)), ("c", State(flag: true))]
    }' "        withCurrent {
            let drawn = cells()
            #expect(drawn.allSatisfy { \$0.0 != \"z\" }, \"the closure in the macro\")
            let flagged = drawn.filter { \$0.1.flag }
            #expect(flagged.map { \$0.0 } == [\"b\", \"c\"], \"\\(flagged.map { \$0.0 })\")
        }" "an unlabelled tuple element"

variant "$tuple_cells" "        withCurrent {
            let drawn = cells()
$macro_first
            let characters = drawn.map { \$0.character }
            #expect(characters == [\"a\", \"b\", \"c\"], \"\\(characters)\")
        }" "a source closure of a different type"

variant "$tuple_cells" "        withCurrent {
            let drawn = cells()
            let noneIsZ = drawn.allSatisfy { \$0.character != \"z\" }
            #expect(noneIsZ, \"the hoisted closure\")
$source_filter
$check_filter
        }" "WORKAROUND: no closure inside the macro"
