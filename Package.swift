// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "TUIkit",
    // Minimum deployment targets for Apple platforms
    // Linux is automatically supported (no platform specification needed)
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // ── Low-level (no deps) ─────────────────────────────────────────────────────────────────────────
        .library(name: "TUIkitCore", targets: ["TUIkitCore"]),
        .library(name: "TUIkitStyling", targets: ["TUIkitStyling"]),

        // ── Mid-level ───────────────────────────────────────────────────────────────────────────────────
        .library(name: "TUIkitView", targets: ["TUIkitView"]),
        .library(name: "TUIkitImage", targets: ["TUIkitImage"]),

        // ── High-level (aggregates all) ─────────────────────────────────────────────────────────────────
        .library(name: "TUIkit", targets: ["TUIkit"]),

        // ── App ─────────────────────────────────────────────────────────────────────────────────────────
        .executable(name: "Example", targets: ["Example"]),

        // ── Stress test (perf instrument; secondarily a complex-TUI demo) ────────────────────────────────
        .executable(name: "Stress", targets: ["Stress"]),

        // ── Tools ───────────────────────────────────────────────────────────────────────────────────────
        .executable(name: "EmojiBugScanner", targets: ["EmojiBugScanner"]),
        .executable(name: "EmojiBenchmark",  targets: ["EmojiBenchmark"]),
        .executable(name: "RenderHarness",   targets: ["RenderHarness"]),
        .executable(name: "ImageHarness",    targets: ["ImageHarness"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.3"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.5.1"),
        // ordo-one/benchmark is added conditionally at the bottom of this file
        // (gated on TUIKIT_BENCHMARKS), so the default build/test graph stays
        // free of its plugin's upstream deprecation warnings and the jemalloc
        // build requirement.
    ],
    targets: [
        // Tools/validate-test-boundaries.sh keeps a hand copy of the four
        // library targets' `dependencies:` below (its `allowed_for` table,
        // which decides what each per-module test target may import). It
        // cannot read this file, so change that table whenever these change.

        // ── Low-level (no deps) ─────────────────────────────────────────────────────────────────────────
        .target(name: "CSTBImage", publicHeadersPath: "include"),
        .target(name: "TUIkitCore"),
        .target(name: "TUIkitStyling"),

        // ── Mid-level ───────────────────────────────────────────────────────────────────────────────────
        // TUIkitStyling came in for `Color: View`, which has to be declared in
        // the module that owns `View`: declared anywhere else, a `Color` in a
        // `@ViewBuilder` pack beside a generic view segfaults the debug
        // runtime while instantiating the pack's metadata. See §14 of
        // `Documentation/Gradients where a colour is accepted.md` — it is a
        // toolchain bug, reproduced on Swift 6.2.4 and still present on the
        // 6.5-dev snapshot of 2026-08-30. PaletteEnvironment.swift and
        // ColorAnimation.swift moved down with it.
        //
        // It is no longer the only use. OpacityClaim.swift derives a
        // translucent paint's opacity claim from the `Color`s it painted with,
        // and RenderCache.swift records the surface `Color` a memoized buffer
        // was blended over. So a toolchain fix would let `Color: View` move
        // back up, but as the code stands the dependency would stay.
        .target(name: "TUIkitView", dependencies: ["TUIkitCore", "TUIkitStyling"]),
        .target(name: "TUIkitImage", dependencies: ["CSTBImage", "TUIkitStyling"]),

        // ── High-level (aggregates all) ─────────────────────────────────────────────────────────────────
        .target(
            name: "TUIkit",
            dependencies: [
                "TUIkitCore", "TUIkitStyling", "TUIkitImage", "TUIkitView",
                .product(name: "DequeModule", package: "swift-collections"),
            ],
            resources: [.copy("Localization/translations"), .copy("VERSION")]
        ),

        // ── App & Tests ─────────────────────────────────────────────────────────────────────────────────
        .executableTarget(
            name: "Example",
            dependencies: ["TUIkit"],
            resources: [.copy("Resources")]
        ),
        // The umbrella test target: integration tests + every test that exercises
        // a control, the App/run loop, focus, or the shared render helpers (which
        // live in this target). Module-specific *unit* tests live in the
        // per-module test targets below, which link ONLY their module (+ its
        // real deps) so a test that reaches across a module boundary fails to
        // compile. `swift test` runs every target, so the full suite is
        // unchanged. Tools/validate-test-boundaries.sh enforces this going
        // forward (see also the per-target import guard it applies).
        .testTarget(
            name: "TUIkitTests",
            dependencies: ["TUIkit", "CTestSupport"],
            // Golden snapshots are read/written by path (#filePath-relative, see
            // TestHelpers/SnapshotTesting.swift), not via the resource bundle, so
            // exclude them from the build rather than declaring them as resources.
            exclude: ["__Snapshots__"]
        ),
        // C declarations a test needs that only the C importer makes — a struct
        // with bitfields, which the runtime's field list leaves out. Tests
        // only; no product names it.
        .target(name: "CTestSupport", path: "Tests/CTestSupport"),

        // The Example app's own views, where a test must hold the view the
        // app ships rather than a copy of its shape — a copy goes on passing
        // after the app's view is changed back. `@testable import Example`: an
        // executable target can be imported by a test target on macOS and
        // Linux, its `main.swift` left unrun.
        .testTarget(
            name: "ExampleTests",
            dependencies: ["Example", "TUIkit"]
        ),

        // ── Per-module unit-test targets (compiler-enforced layering) ──────────────────────────────────────
        // Each links ONLY its module. A unit test that drifts into a sibling or
        // higher layer stops compiling here — that is the point: it keeps every
        // module provably testable in isolation.
        .testTarget(name: "TUIkitCoreTests", dependencies: ["TUIkitCore"]),
        .testTarget(name: "TUIkitStylingTests", dependencies: ["TUIkitStyling"]),
        .testTarget(name: "TUIkitViewTests", dependencies: ["TUIkitView"]),
        .testTarget(name: "TUIkitImageTests", dependencies: ["TUIkitImage"]),

        // ── Stress test ─────────────────────────────────────────────────────────────────────────────────
        // A performance stress harness shaped like an app: deep/wide view
        // hierarchies over large, pseudo-randomly synthesised data sets. Runs
        // interactively, or headless (`--bench`/`--selfcheck`) as a no-PTY
        // profiling instrument (see Sources/Stress/README.md).
        .executableTarget(
            name: "TerminalClientQuirks",
            dependencies: ["TUIkit"],
            exclude: ["README.md"]  // documentation, not a bundled resource
        ),
        .executableTarget(
            name: "Stress",
            dependencies: ["TUIkit"],
            exclude: ["README.md"]  // documentation, not a bundled resource
        ),

        // ── Tools ───────────────────────────────────────────────────────────────────────────────────────
        .executableTarget(
            name: "EmojiBugScanner",
            dependencies: ["TUIkitCore"],
            path: "Tools/EmojiBugScanner"
        ),
        .executableTarget(
            name: "EmojiBenchmark",
            dependencies: ["TUIkitCore"],
            path: "Tools/EmojiBenchmark"
        ),
        // Mode A profiling harness (see Tools/Profiling/README.md): a
        // no-PTY, no-attach executable that loops `renderToBuffer` over a
        // representative tree so it can be profiled with `xctrace --launch`
        // in environments where `--attach` is denied.
        .executableTarget(
            name: "RenderHarness",
            dependencies: ["TUIkit"],
            path: "Tools/Profiling/RenderHarness"
        ),

        // The same, for the IMAGE pipeline: an `ASCIIConverter` looped over a
        // picture. Separate from `RenderHarness` because the two halves of the
        // image path — per cell (`convert`) and per pixel (`recoloured`) —
        // have to be measured separately, and neither is a view render.
        .executableTarget(
            name: "ImageHarness",
            dependencies: ["TUIkitImage", "TUIkitStyling"],
            path: "Tools/Profiling/ImageHarness"
        ),

        // The smallest app that can be asked "does this view cost anything when
        // nothing is happening?" — one view, nothing focusable, no timers. Every
        // Example page carrying an Image also carries focusable controls, whose
        // focus pulse keeps the loop legitimately awake and makes the reading
        // meaningless. Driven by `Tools/Profiling/idle-image.sh`.
        .executableTarget(
            name: "IdleProbe",
            dependencies: ["TUIkit"],
            path: "Tools/Profiling/IdleProbe"
        ),
    ]
)

// ── Benchmarks (opt-in) ───────────────────────────────────────────────────────────────────────────
// ordo-one/package-benchmark and the `TUIkitBenchmarks` target are gated behind
// an environment flag so the default `swift build` / `swift test` graph never
// pulls in the benchmark dependency. That keeps test output free of the plugin's
// upstream PackagePlugin deprecation warnings and removes the jemalloc build
// requirement for ordinary development. Enable benchmarking by exporting
// TUIKIT_BENCHMARKS, e.g.
//   TUIKIT_BENCHMARKS=1 swift package benchmark
//   TUIKIT_BENCHMARKS=1 swift package benchmark run TUIkitBenchmarks <name>
if Context.environment["TUIKIT_BENCHMARKS"] != nil {
    package.dependencies.append(
        .package(url: "https://github.com/ordo-one/benchmark", from: "1.29.4", traits: [])
    )
    package.targets.append(
        .executableTarget(
            name: "TUIkitBenchmarks",
            dependencies: [
                "TUIkit",
                .product(name: "Benchmark", package: "benchmark"),
            ],
            path: "Benchmarks/TUIkitBenchmarks",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "benchmark")
            ]
        )
    )
}
