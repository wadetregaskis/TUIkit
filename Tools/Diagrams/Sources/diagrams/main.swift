import Foundation

// Regenerates the DocC architecture diagrams: each Diagram → DOT → `dot -Tsvg`
// → a self-theming SVG written into the DocC Resources directory.
//
//   swift run --package-path Tools/Diagrams diagrams
//   swift run --package-path Tools/Diagrams diagrams --list
//   swift run --package-path Tools/Diagrams diagrams --dot lifecycle-main-loop   # print DOT
//   swift run --package-path Tools/Diagrams diagrams --output <dir>
//
// Requires Graphviz `dot` on PATH (brew/apt install graphviz) or the DOT env var.

let args = CommandLine.arguments

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

if args.contains("--list") {
    for d in allDiagrams { print(d.name) }
    exit(0)
}

// Print one diagram's DOT (handy for inspecting / piping into `dot` by hand).
if let name = option("--dot") {
    guard let d = allDiagrams.first(where: { $0.name == name }) else {
        fail("unknown diagram '\(name)'. Known: \(allDiagrams.map(\.name).joined(separator: ", "))")
    }
    print(d.dot(), terminator: "")
    exit(0)
}

// Default: render every diagram to <output>/<name>.svg.
let outputDir = option("--output") ?? "Sources/TUIkit/TUIkit.docc/Resources"

guard let dot = locateDot() else {
    fail(RenderError.dotNotFound.description)
}

do {
    try FileManager.default.createDirectory(
        atPath: outputDir, withIntermediateDirectories: true)
    for d in allDiagrams {
        let svg = postProcess(try runDot(d.dot(), dot: dot))
        let path = "\(outputDir)/\(d.name).svg"
        try svg.write(toFile: path, atomically: true, encoding: .utf8)
        print("wrote \(path)")
    }
} catch let e as RenderError {
    fail(e.description)
} catch {
    fail("\(error)")
}
