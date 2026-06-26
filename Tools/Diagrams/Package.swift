// swift-tools-version: 6.2
import PackageDescription

// Standalone dev tool: regenerates the DocC architecture diagrams.
// Kept out of the root package so it builds with no dependencies and doesn't
// touch the library's package graph. Run from the repo root:
//
//     swift run --package-path Tools/Diagrams diagrams
//
// Requires Graphviz `dot` on PATH (brew install graphviz / apt-get install
// graphviz), or set the DOT environment variable to its path.
let package = Package(
    name: "diagrams",
    targets: [
        .executableTarget(name: "diagrams", path: "Sources/diagrams")
    ]
)
