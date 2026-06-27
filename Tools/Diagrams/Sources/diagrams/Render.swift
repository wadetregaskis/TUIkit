import Foundation

enum RenderError: Error, CustomStringConvertible {
    case dotNotFound
    case dotFailed(Int32, String)
    case noOutput

    var description: String {
        switch self {
        case .dotNotFound:
            return """
            Graphviz 'dot' was not found. Install it and ensure it is on PATH:
                macOS:  brew install graphviz
                Linux:  apt-get install graphviz
            …or set the DOT environment variable to the full path of `dot`.
            """
        case .dotFailed(let code, let stderr):
            return "dot exited with status \(code):\n\(stderr)"
        case .noOutput:
            return "dot produced no SVG output"
        }
    }
}

/// Locate the Graphviz `dot` executable: the `DOT` env var if set, else PATH.
func locateDot() -> String? {
    let env = ProcessInfo.processInfo.environment
    if let p = env["DOT"], !p.isEmpty,
       FileManager.default.isExecutableFile(atPath: p) {
        return p
    }
    let path = env["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
    for dir in path.split(separator: ":") {
        let candidate = "\(dir)/dot"
        if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
    }
    return nil
}

/// Run `dot -Tsvg` on the given DOT source and return the raw SVG.
func runDot(_ source: String, dot: String) throws -> String {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: dot)
    proc.arguments = ["-Tsvg"]
    let stdIn = Pipe(), stdOut = Pipe(), stdErr = Pipe()
    proc.standardInput = stdIn
    proc.standardOutput = stdOut
    proc.standardError = stdErr
    try proc.run()
    stdIn.fileHandleForWriting.write(Data(source.utf8))
    stdIn.fileHandleForWriting.closeFile()
    let outData = stdOut.fileHandleForReading.readDataToEndOfFile()
    let errData = stdErr.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    guard proc.terminationStatus == 0 else {
        throw RenderError.dotFailed(proc.terminationStatus,
                                    String(decoding: errData, as: UTF8.self))
    }
    let svg = String(decoding: outData, as: UTF8.self)
    guard svg.contains("<svg") else { throw RenderError.noOutput }
    return svg
}

/// Make a Graphviz SVG self-theming and DocC-friendly:
///  - drop the XML prolog / DOCTYPE so the file starts at `<svg>`;
///  - inject a `prefers-color-scheme: dark` override for the connectors and
///    edge labels. Node text is white on a coloured fill, so it already reads
///    on either background and is left untouched. One file themes both modes —
///    no fragile `~dark` companion required.
func postProcess(_ svg: String) -> String {
    var s = svg
    if let start = s.range(of: "<svg") {
        s = String(s[start.lowerBound...])
    }
    let style = """

    <style>
    @media (prefers-color-scheme: dark) {
      .edge text { fill: #cdd1d5; }
      .edge path { stroke: #9aa0a6; }
      .edge polygon { stroke: #9aa0a6; fill: #9aa0a6; }
      .cluster text { fill: #9aa0a6; }
      .cluster polygon, .cluster path { stroke: #5a5a5a; }
    }
    </style>
    """
    if let openTagEnd = s.range(of: ">") {
        s.insert(contentsOf: style, at: openTagEnd.upperBound)
    }
    return s.hasSuffix("\n") ? s : s + "\n"
}
