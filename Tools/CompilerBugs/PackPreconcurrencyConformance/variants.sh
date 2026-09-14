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
    printf '%-44s' "$1"
    local out
    out=$("$swiftc_bin" -parse-as-library -swift-version 6 -sdk "$sdk" \
        -target arm64-apple-macos14.0 -emit-library -o "$work/out.dylib" "$2" 2>&1)
    local status=$?
    if grep -q "isPreconcurrency" <<<"$out"; then
        echo "ASSERTS"
    elif [ $status -ne 0 ]; then
        echo "error"
    else
        echo "ok"
    fi
}

body='    static func == (lhs: Self, rhs: Self) -> Bool { true }'

check "@preconcurrency, pack condition" Crash.swift

cat > "$work/isolated.swift" <<EOF
@MainActor protocol View {}
struct Pack<each V: View>: View { let children: (repeat each V) }
extension Pack: @MainActor Equatable where repeat each V: Equatable {
$body
}
EOF
check "@MainActor (isolated) conformance" "$work/isolated.swift"

cat > "$work/trivial.swift" <<EOF
@MainActor protocol View {}
struct Pack<each V: View>: View { let children: (repeat each V) }
extension Pack: @preconcurrency Equatable where repeat each V: Equatable {
$body
}
EOF
check "@preconcurrency, pack condition, trivial ==" "$work/trivial.swift"

cat > "$work/unconditional.swift" <<EOF
@MainActor protocol View {}
struct Pack<each V: View>: View { let children: (repeat each V) }
extension Pack: @preconcurrency Equatable {
$body
}
EOF
check "@preconcurrency, pack, no condition" "$work/unconditional.swift"

cat > "$work/single.swift" <<EOF
@MainActor protocol View {}
struct Single<V: View>: View { let child: V }
extension Single: @preconcurrency Equatable where V: Equatable {
$body
}
EOF
check "@preconcurrency, ordinary generic" "$work/single.swift"

cat > "$work/nonisolated.swift" <<EOF
protocol View {}
struct Pack<each V: View>: View { let children: (repeat each V) }
extension Pack: Equatable where repeat each V: Equatable {
$body
}
EOF
check "protocol not main-actor isolated" "$work/nonisolated.swift"
