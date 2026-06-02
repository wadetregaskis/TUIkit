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
        .executable(name: "TUIkitExample", targets: ["TUIkitExample"]),

        // ── Tools ───────────────────────────────────────────────────────────────────────────────────────
        .executable(name: "EmojiBugScanner", targets: ["EmojiBugScanner"]),
        .executable(name: "EmojiBenchmark",  targets: ["EmojiBenchmark"]),
        .executable(name: "RenderHarness",   targets: ["RenderHarness"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.3"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.5.1"),
        // swift-benchmark (ordo-one/benchmark): proper warmup /
        // statistics / baseline tracking for the perf-sensitive
        // code paths. The plugin is invoked via 'swift package
        // benchmark'; see
        // https://swiftpackageindex.com/ordo-one/benchmark
        .package(url: "https://github.com/ordo-one/benchmark", from: "1.29.4", traits: []),
    ],
    targets: [
        // ── Low-level (no deps) ─────────────────────────────────────────────────────────────────────────
        .target(name: "CSTBImage", publicHeadersPath: "include"),
        .target(name: "TUIkitCore"),
        .target(name: "TUIkitStyling"),

        // ── Mid-level ───────────────────────────────────────────────────────────────────────────────────
        .target(name: "TUIkitView", dependencies: ["TUIkitCore"]),
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
            name: "TUIkitExample",
            dependencies: ["TUIkit"],
            resources: [.copy("Resources")]
        ),
        .testTarget(name: "TUIkitTests", dependencies: ["TUIkit"]),

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

        // ── Benchmarks ──────────────────────────────────────────────────────────────────────────────────
        // Driven by ordo-one/package-benchmark. Invoke via
        // 'swift package benchmark' (full suite) or
        // 'swift package benchmark run TUIkitBenchmarks <name>' (one).
        .executableTarget(
            name: "TUIkitBenchmarks",
            dependencies: [
                "TUIkit",
                .product(name: "Benchmark", package: "benchmark"),
            ],
            path: "Benchmarks/TUIkitBenchmarks",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "benchmark"),
            ]
        ),
    ]
)
