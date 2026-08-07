#!/usr/bin/env bash
#
# validate-package-manifest.sh — reject manifest constructs that make this
# package impossible to depend on.
#
# SwiftPM refuses to RESOLVE a versioned dependency whose manifest uses
# `unsafeFlags`, or that depends on a local filesystem path, or that pins
# another package to a branch or a revision rather than a version. The refusal
# happens in the CONSUMER's resolution, not in ours — so a manifest carrying any
# of them builds here, passes every test here, ships a green CI here, and is
# simply undownloadable by anyone else. There is no other detector: nothing we
# build in-tree ever exercises the constraint.
#
# `unsafeFlags` is the realistic way one arrives: reaching for `-Xfrontend` to
# chase a profiling question, and forgetting to take it out again.
#
# This is the cheap half of the consumer gate — milliseconds, every push. The
# expensive half (Tools/verify-versioned-consumer.sh) actually resolves and
# builds the package as a dependency, and runs only on tags.
#
# Usage:
#   Tools/validate-package-manifest.sh
#   Tools/validate-package-manifest.sh --self-test   # prove the checks bite
#
# Exit status: 0 if the manifest is consumable, 1 otherwise.
#
# Reads `swift package dump-package` rather than the manifest source. The JSON
# is what SwiftPM itself resolved the manifest to, so a construct cannot hide
# behind a comment, a string literal, or a helper variable — and `//` inside a
# dependency URL cannot be mistaken for a comment, which is exactly what a
# source-text scanner gets wrong here.
#
# Bash 3.2 compatible (macOS ships 3.2).

set -euo pipefail
cd "$(dirname "$0")/.."

# Each check is a name, a pattern matched against the manifest JSON, and the
# explanation a reader needs at the moment it fires.
#
# The patterns match JSON *keys*, which dump-package emits verbatim, so a
# dependency URL that happens to contain the word "branch" cannot trip them.
check_manifest() {
    local json="$1" failures=0

    if printf '%s' "$json" | grep -q '"unsafeFlags"'; then
        printf 'FAIL unsafeFlags\n'
        printf '     SwiftPM refuses to resolve a versioned dependency whose manifest\n'
        printf '     uses unsafeFlags. Every consumer of this package would be unable to\n'
        printf '     add it at all. Express the flag as a supported setting, or drop it.\n'
        failures=$((failures + 1))
    fi

    if printf '%s' "$json" | grep -q '"fileSystem"'; then
        printf 'FAIL local path dependency\n'
        printf '     A .package(path:) dependency exists only on this machine. A consumer\n'
        printf '     resolving this package by version cannot follow it.\n'
        failures=$((failures + 1))
    fi

    if printf '%s' "$json" | grep -qE '"requirement" *: *\{ *"(branch|revision)"'; then
        printf 'FAIL branch or revision dependency\n'
        printf '     A versioned package may only depend on other packages by version.\n'
        printf '     A branch or revision pin makes this package unresolvable downstream.\n'
        failures=$((failures + 1))
    fi

    return $failures
}

# The checks are only worth having if they actually fire, so prove it against
# synthetic manifests rather than trusting the patterns by eye. Each fixture is
# the shape `swift package dump-package` emits for that construct.
self_test() {
    local failures=0 name json

    run_case() {
        name="$1"; json="$2"; local want="$3" got=0
        check_manifest "$json" >/dev/null 2>&1 || got=1
        if [ "$got" != "$want" ]; then
            printf 'SELF-TEST FAIL: %s (expected %s, got %s)\n' "$name" "$want" "$got"
            failures=$((failures + 1))
        else
            printf 'ok  %s\n' "$name"
        fi
    }

    run_case "clean manifest passes" \
        '{"dependencies":[{"sourceControl":[{"identity":"x","requirement":{"range":[{"lowerBound":"1.0.0","upperBound":"2.0.0"}]}}]}],"targets":[{"name":"T","settings":[]}]}' 0
    run_case "unsafeFlags caught" \
        '{"targets":[{"name":"T","settings":[{"kind":{"unsafeFlags":[["-Xfrontend"]]}}]}]}' 1
    run_case "path dependency caught" \
        '{"dependencies":[{"fileSystem":[{"identity":"local","path":"/Users/someone/dep"}]}]}' 1
    run_case "branch dependency caught" \
        '{"dependencies":[{"sourceControl":[{"identity":"x","requirement":{"branch":["main"]}}]}]}' 1
    run_case "revision dependency caught" \
        '{"dependencies":[{"sourceControl":[{"identity":"x","requirement":{"revision":["abc123"]}}]}]}' 1
    # A URL containing a check word must NOT trip the scanner — the reason this
    # reads dump-package's JSON keys rather than the manifest source.
    run_case "a URL containing 'branch' is not a branch pin" \
        '{"dependencies":[{"sourceControl":[{"identity":"x","location":{"remote":[{"urlString":"https://example.com/branch/revision"}]},"requirement":{"exact":["1.0.0"]}}]}]}' 0

    if [ "$failures" -eq 0 ]; then
        printf '\nself-test passed: every check fires on its construct and on nothing else\n'
        return 0
    fi
    printf '\n%d self-test failure(s)\n' "$failures"
    return 1
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

manifest_json="$(swift package dump-package)"

if check_manifest "$manifest_json"; then
    printf 'Package.swift is consumable: no unsafeFlags, no path/branch/revision dependencies\n'
    exit 0
fi

printf '\nSee Tools/validate-package-manifest.sh for why each of these is fatal to a consumer.\n'
exit 1
