#!/usr/bin/env bash
#
# validate-test-boundaries.sh — enforce per-module unit-test isolation.
#
# TUIkit's unit tests are split into per-module test targets (see Package.swift):
# each links ONLY its module, so a test that reaches across a module boundary
# fails to compile. This script is the fast, human-readable guard for that
# property: it flags a module test target importing a module outside its
# dependency closure BEFORE a full build would, with a clear message. The
# umbrella `TUIkitTests` target is unrestricted (integration tests live there).
#
# `swift test` already builds every target, so SPM enforces this at compile
# time too; this script exists so the rule is explicit, documented, and catches
# a stray `import TUIkit` in a module test the moment it lands (CI + pre-commit),
# not only when the offending symbol happens to be referenced.
#
# Exit status: 0 if all module test targets stay within their layer, 1 otherwise.

set -euo pipefail
cd "$(dirname "$0")/.."

# Allowed framework imports per module test target = the module + its transitive
# framework dependencies. (Foundation / Testing / Dispatch etc. are never flagged
# — only TUIkit* modules are checked.) A `case` keeps this portable to macOS's
# stock bash 3.2 (no associative arrays).
allowed_for() {
    case "$1" in
        TUIkitCoreTests) echo "TUIkitCore" ;;
        TUIkitStylingTests) echo "TUIkitStyling" ;;
        TUIkitViewTests) echo "TUIkitView TUIkitCore" ;;
        TUIkitImageTests) echo "TUIkitImage TUIkitStyling" ;;
    esac
}

violations=0

for target in TUIkitCoreTests TUIkitStylingTests TUIkitViewTests TUIkitImageTests; do
    dir="Tests/$target"
    [ -d "$dir" ] || continue
    allowed=" $(allowed_for "$target") "

    # Every `import TUIkit<Module>` (optionally @testable) in the target's files.
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        file="${line%%:*}"
        rest="${line#*:}"
        lineno="${rest%%:*}"
        module=$(printf '%s\n' "$rest" | grep -oE 'TUIkit[A-Za-z]*' | head -1)
        # Only TUIkit* modules are governed here.
        case "$module" in TUIkit*) ;; *) continue ;; esac
        if [[ "$allowed" != *" $module "* ]]; then
            echo "✘ $file:$lineno imports '$module', which is outside $target's layer."
            echo "    Allowed: $(allowed_for "$target"). Move this test to Tests/TUIkitTests/"
            echo "    (the umbrella integration target) or drop the cross-module dependency."
            violations=$((violations + 1))
        fi
    done < <(grep -rnE '^[[:space:]]*(@testable[[:space:]]+)?import[[:space:]]+TUIkit' "$dir" 2>/dev/null || true)
done

if [ "$violations" -gt 0 ]; then
    echo ""
    echo "✘ $violations test-boundary violation(s). Per-module test targets must stay within their module's layer."
    exit 1
fi

echo "✓ Test module boundaries intact (TUIkit{Core,Styling,View,Image}Tests each stay within their layer)."
