#!/usr/bin/env bash
#
# verify-versioned-consumer.sh — build and RUN a package that depends on this
# one by version, the way anyone else would.
#
# Everything we build in-tree builds the package as itself. That misses the
# questions a consumer asks: does it resolve at all, does its public surface
# suffice without `@testable`, do its resource bundles find themselves when the
# product belongs to someone else's build.
#
# The consumer here does not merely compile — it RUNS, and checks two things
# that only exist at runtime:
#
#   tuiKitVersion                  reads Sources/TUIkit/VERSION via
#                                  Bundle.module, and answers "unknown" if the
#                                  bundle cannot be found. A compile-only check
#                                  would sail straight past that.
#   LocalizationService().string   reads Localization/translations the same way.
#                                  A miss returns the key unchanged, so asking
#                                  for a key whose value differs from it proves
#                                  the directory resolved.
#
# Both would fail silently in a real app — wrong version in a status bar,
# every string falling back to its dotted key — which is precisely the class of
# failure worth a gate.
#
# What it tests is the CURRENT TREE as a dependency, not a published tag: the
# working tree is copied into a throwaway repository and tagged there. That is
# deliberate. A gate that only examines what is already released tells you about
# a mistake you have already made.
#
# The cheap half of this — the manifest constructs that make resolution
# impossible outright — is Tools/validate-package-manifest.sh, which runs on
# every push. This one is the expensive half, for tags.
#
# Usage:
#   Tools/verify-versioned-consumer.sh
#
# Exit status: 0 if a versioned consumer resolves, builds, and runs.
#
# Needs no network: the dependency is a local throwaway repository, and the
# package's own dependencies come from the checked-in Package.resolved.

set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT_DIR="$PWD"
TEMP_DIR="$(mktemp -d)"
PACKAGE_REPO="$TEMP_DIR/TUIkit"
CONSUMER_DIR="$TEMP_DIR/Consumer"

trap 'rm -rf "$TEMP_DIR"' EXIT

printf '── Staging the working tree as a versioned package\n'
mkdir -p "$PACKAGE_REPO" "$CONSUMER_DIR/Sources/Consumer"

# The WHOLE tree, not just Sources/ and the manifests.
#
# SwiftPM validates every target's path when it loads a manifest, including
# targets the consumer will never build. Ours declares four outside Sources/ —
# Tools/EmojiBugScanner, Tools/EmojiBenchmark, Tools/Profiling/RenderHarness,
# Benchmarks/TUIkitBenchmarks — so a staging area holding only Sources/ fails
# resolution with "invalid custom path", which says nothing about whether the
# package is consumable. (It said exactly that on this gate's first run.)
#
# A consumer clones the repository, so copying the tree is also the faithful
# thing. It costs nothing at build time: the consumer builds the TUIkit product
# and only what that product needs, so Tests/ and the harnesses are never
# compiled.
#
# Excludes are the artefacts a clone would not carry. `.build` in particular
# holds the host's own build products, which would be both enormous and wrong.
tar -cf - --exclude=./.git --exclude=./.build --exclude=./.swiftpm -C "$PROJECT_DIR" . \
    | tar -xf - -C "$PACKAGE_REPO"

git -C "$PACKAGE_REPO" init --quiet
git -C "$PACKAGE_REPO" config user.name "TUIkit consumer gate"
git -C "$PACKAGE_REPO" config user.email "consumer-gate@localhost"
git -C "$PACKAGE_REPO" add .
git -C "$PACKAGE_REPO" commit --quiet -m "Working tree under test"
# The version is arbitrary — what matters is that the consumer asks for it
# EXACTLY, so SwiftPM resolves through the version machinery rather than
# treating the dependency as a local checkout.
git -C "$PACKAGE_REPO" tag 1.0.0

cat > "$CONSUMER_DIR/Package.swift" <<EOF
// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "TUIkitConsumer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "file://$PACKAGE_REPO", exact: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Consumer",
            dependencies: [.product(name: "TUIkit", package: "TUIkit")]
        )
    ]
)
EOF

# Plain `import TUIkit` — no @testable — so anything the public surface fails to
# expose fails here. Then the two resource reads, each with the failure spelled
# out, because a gate is only useful if its failure explains itself.
cat > "$CONSUMER_DIR/Sources/Consumer/main.swift" <<'EOF'
// Foundation for `exit` — importing TUIkit does not bring it in, and a
// consumer's own imports are its business. That it has to be said here is a
// small proof the gate is honest: nothing is being handed to this program.
import Foundation
import TUIkit

var failures: [String] = []

// Resolves Sources/TUIkit/VERSION through Bundle.module, or answers "unknown".
if tuiKitVersion == "unknown" || tuiKitVersion.isEmpty {
    failures.append(
        """
        tuiKitVersion is "\(tuiKitVersion)".
        The VERSION resource did not resolve through Bundle.module when TUIkit was
        built as a dependency. Check the `resources:` entry for the TUIkit target.
        """)
}

// Resolves Localization/translations the same way. A miss returns the key.
let ok = LocalizationService().string(for: "button.ok")
if ok == "button.ok" {
    failures.append(
        """
        LocalizationService returned the key "button.ok" unchanged.
        The bundled translations did not resolve, so every framework string would
        fall back to its dotted key in a consumer's app.
        """)
}

guard failures.isEmpty else {
    for failure in failures { print("FAIL: \(failure)") }
    exit(1)
}

print("versioned consumer OK — TUIkit \(tuiKitVersion), button.ok = \(ok)")
EOF

printf '── Resolving\n'
swift package --package-path "$CONSUMER_DIR" resolve

printf '── Building\n'
swift build --package-path "$CONSUMER_DIR"

printf '── Running\n'
swift run --package-path "$CONSUMER_DIR" Consumer

printf '\nVersioned consumer gate passed\n'
