#!/bin/bash
# Compiles Crash.swift and a set of near-misses, printing which ones assert.
#
#   ./variants.sh                       # uses `swiftc` from PATH
#   ./variants.sh /path/to/xctoolchain  # uses that toolchain's swiftc
#
# "error" means the variant failed to compile for some other reason, so it
# says nothing either way about the assertion.
set -u
cd "$(dirname "$0")" || exit 2
swiftc_bin="swiftc"
[ $# -ge 1 ] && swiftc_bin="$1/usr/bin/swiftc"
sdk=$(xcrun --show-sdk-path)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

check() { # $1 = label, $2 = file
    printf '%-40s' "$1"
    local out
    out=$("$swiftc_bin" -parse-as-library -swift-version 6 -sdk "$sdk" \
        -target arm64-apple-macos14.0 -emit-library -o "$work/out.dylib" "$2" 2>&1)
    local status=$?
    if grep -q "no generic environment" <<<"$out"; then
        echo "ASSERTS"
    elif [ $status -ne 0 ]; then
        echo "error"
    else
        echo "ok"
    fi
}

each='func each<T, R>(_ values: [T], _ transform: (T) -> R) -> [R] { values.map(transform) }'

check "generic type, destructuring closure" Crash.swift

cat > "$work/pair.swift" <<EOF
$each
struct Core<Root> {
    func bar(pairs: [(Int, String)]) -> [some Equatable] { each(pairs) { pair in helper(pair.1) } }
    func helper(_ string: String) -> some Equatable { string }
}
EOF
check "one closure parameter, not destructured" "$work/pair.swift"

cat > "$work/nongeneric.swift" <<EOF
$each
struct Core {
    func bar(pairs: [(Int, String)]) -> [some Equatable] { each(pairs) { _, string in helper(string) } }
    func helper(_ string: String) -> some Equatable { string }
}
EOF
check "type not generic" "$work/nongeneric.swift"

cat > "$work/concrete.swift" <<EOF
$each
struct Core<Root> {
    func bar(pairs: [(Int, String)]) -> [String] { each(pairs) { _, string in helper(string) } }
    func helper(_ string: String) -> String { string }
}
EOF
check "helper's result not opaque" "$work/concrete.swift"

cat > "$work/notopaque.swift" <<EOF
$each
struct Core<Root> {
    func bar(pairs: [(Int, String)]) -> Int { each(pairs) { _, string in helper(string) }.count }
    func helper(_ string: String) -> some Equatable { string }
}
EOF
check "enclosing method's result not opaque" "$work/notopaque.swift"

cat > "$work/freefunction.swift" <<EOF
$each
func helper(_ string: String) -> some Equatable { string }
func bar<Root>(_: Root.Type, pairs: [(Int, String)]) -> [some Equatable] {
    each(pairs) { _, string in helper(string) }
}
EOF
check "generic free function, not a type" "$work/freefunction.swift"
