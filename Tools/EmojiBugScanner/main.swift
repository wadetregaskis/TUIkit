//  🖥️ TUIKit — Terminal UI Kit for Swift
//  EmojiBugScanner / main.swift
//
//  Probes Terminal.app for the actual cursor advance of each emoji
//  cluster in a programmatically-generated corpus and reports any
//  cluster whose advance differs from its claimed visible width.
//
//  Usage:  swift run EmojiBugScanner [--single|--vs16|--skin-tone|--flags|--all]
//                                    [--output FILE]
//                                    [--quiet]
//
//  MUST be run interactively in Terminal.app — DSR (`\e[6n`) requires
//  a real TTY that will respond.  The scanner enables raw mode on
//  STDIN_FILENO, sends DSR queries, and parses the `\e[<row>;<col>R`
//  replies to determine where Terminal.app's cursor counter ended up
//  after writing each cluster.

#if canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Darwin)
    import Darwin
#endif
import Foundation
import TUIkitCore

// MARK: - Raw mode

struct RawMode {
    var original: termios

    static func enable() -> RawMode {
        var original = termios()
        tcgetattr(STDIN_FILENO, &original)
        var raw = original
        let lflagOff: UInt = UInt(ECHO | ICANON | ISIG | IEXTEN)
        let iflagOff: UInt = UInt(IXON | ICRNL | BRKINT | INPCK | ISTRIP)
        let oflagOff: UInt = UInt(OPOST)
        raw.c_lflag &= ~tcflag_t(lflagOff)
        raw.c_iflag &= ~tcflag_t(iflagOff)
        raw.c_oflag &= ~tcflag_t(oflagOff)
        raw.c_cflag |= tcflag_t(CS8)
        withUnsafeMutablePointer(to: &raw.c_cc) { p in
            p.withMemoryRebound(to: cc_t.self, capacity: Int(NCCS)) { cc in
                cc[Int(VMIN)]  = 1   // block until at least 1 byte available
                cc[Int(VTIME)] = 1   // 100ms timeout between bytes once started
            }
        }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
        return RawMode(original: original)
    }

    func restore() {
        var orig = original
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &orig)
    }
}

// MARK: - Low-level I/O

func writeBytes(_ bytes: [UInt8]) {
    _ = bytes.withUnsafeBytes { write(STDOUT_FILENO, $0.baseAddress, $0.count) }
}

func writeString(_ s: String) {
    writeBytes(Array(s.utf8))
}

/// Reads bytes from STDIN until a terminator byte is encountered (inclusive),
/// or until `maxBytes` accumulate without a terminator.  Returns the read
/// bytes (including the terminator), or `nil` if reading times out.
func readUntil(terminator: UInt8, maxBytes: Int = 32) -> [UInt8]? {
    var buf: [UInt8] = []
    while buf.count < maxBytes {
        var b: UInt8 = 0
        let n = read(STDIN_FILENO, &b, 1)
        if n <= 0 { return nil }
        buf.append(b)
        if b == terminator { return buf }
    }
    return nil
}

/// Sends `ESC [ 6 n` (DSR), parses the `ESC [ <row> ; <col> R` reply, and
/// returns `(row, col)`.  Returns `nil` on timeout or parse failure.
func queryCursorPosition() -> (row: Int, col: Int)? {
    writeBytes([0x1B, UInt8(ascii: "["), UInt8(ascii: "6"), UInt8(ascii: "n")])
    guard let reply = readUntil(terminator: UInt8(ascii: "R")) else { return nil }
    // Reply form:  ESC [ <row> ; <col> R
    guard reply.count >= 6, reply[0] == 0x1B, reply[1] == UInt8(ascii: "[") else { return nil }
    let body = reply.dropFirst(2).dropLast()
    guard let semi = body.firstIndex(of: UInt8(ascii: ";")) else { return nil }
    let rowBytes = body[body.startIndex..<semi]
    let colBytes = body[body.index(after: semi)..<body.endIndex]
    guard
        let rowStr = String(bytes: Array(rowBytes), encoding: .ascii),
        let colStr = String(bytes: Array(colBytes), encoding: .ascii),
        let row = Int(rowStr),
        let col = Int(colStr)
    else { return nil }
    return (row, col)
}

// MARK: - Probe

enum Verdict: String {
    case normal       = "normal"
    case underAdvance = "under-advance"
    case overAdvance  = "over-advance"
    case parseFailure = "parse-failure"
}

struct Result {
    let codepoints: [Unicode.Scalar]
    let cluster: String
    let claimedWidth: Int
    let actualAdvance: Int
    let verdict: Verdict
}

/// Probes a single cluster.  Pre-condition: cursor at row 2, column 1,
/// line clear, no other content on the row.  Post-condition: same row,
/// cursor wherever Terminal.app left it.
func probe(cluster: String) -> Result {
    // Build the codepoint list for reporting.
    let codepoints = Array(cluster.unicodeScalars)

    // Move to row 2 col 1, erase line, write cluster, query position.
    // `\e[2;1H` — CUP row 2 col 1.  Row 1 is reserved for our progress
    // line, so we don't fight for that real estate.
    writeString("\u{1B}[2;1H\u{1B}[2K")
    writeString(cluster)

    let claimed = Character(cluster).terminalWidth
    let actual: Int
    if let pos = queryCursorPosition() {
        actual = pos.col - 1   // col 1 == 0 cells advanced
    } else {
        return Result(codepoints: codepoints, cluster: cluster,
                      claimedWidth: claimed, actualAdvance: -1,
                      verdict: .parseFailure)
    }

    let verdict: Verdict
    if actual == claimed       { verdict = .normal }
    else if actual <  claimed  { verdict = .underAdvance }
    else                       { verdict = .overAdvance }
    return Result(codepoints: codepoints, cluster: cluster,
                  claimedWidth: claimed, actualAdvance: actual,
                  verdict: verdict)
}

// MARK: - Corpus generators
//
// The corpus is built from Unicode properties exposed by Swift's
// standard library (backed by Apple's bundled ICU on Darwin and
// swift-foundation-icu on Linux).  This avoids us bundling our own
// copy of `emoji-data.txt` and keeps the corpus aligned with whatever
// Unicode version the running Swift toolchain knows about.
//
// Properties used:
//   - `isEmojiPresentation`  — codepoint defaults to a coloured 2-cell
//                              emoji glyph.  These are the candidates
//                              for Bug A (VS-16 under-advance has no
//                              effect on them — VS-16 is a no-op when
//                              the default presentation is already
//                              emoji — but any cluster that includes
//                              one of these as its base IS a candidate
//                              for an over-advance bug).
//   - `isEmoji && !isEmojiPresentation`
//                            — codepoint defaults to text presentation
//                              but can be PROMOTED to emoji by adding
//                              U+FE0F.  Classic Bug A territory:
//                              `<base>+FE0F` glyph is 2 cells but
//                              Terminal.app advances the cursor by 1.
//   - `isEmojiModifierBase`  — codepoint legitimately accepts a
//                              Fitzpatrick modifier (U+1F3FB..1F3FF).
//                              Skipping every other base avoids the
//                              "Mahjong tile + skin tone" noise that
//                              programmatic enumeration produced
//                              before.

let fitzpatrick: [Unicode.Scalar] = (0x1F3FB...0x1F3FF).compactMap { Unicode.Scalar($0) }
let vs16: Unicode.Scalar = Unicode.Scalar(0xFE0F)!

/// All assigned Unicode codepoints worth scanning — anything that is
/// either default emoji presentation, or could become one with VS-16,
/// or is an emoji modifier base, or is the start of a flag sequence.
/// Filtered with `Unicode.Scalar.Properties` so we get exactly the set
/// of codepoints Apple's renderer treats as candidate emoji.
func emojiCandidates() -> [Unicode.Scalar] {
    var out: [Unicode.Scalar] = []
    // Range chosen to cover every assigned scalar (BMP + supplementary)
    // up to the end of the Symbols & Pictographs Extended-A block plus
    // some slack.  We let `Unicode.Scalar.Properties` filter.
    for cp: UInt32 in 0x0023...0x1FBFF {
        guard let s = Unicode.Scalar(cp) else { continue }
        let p = s.properties
        if p.isEmoji || p.isEmojiPresentation || p.isEmojiModifierBase {
            out.append(s)
        }
    }
    return out
}

/// Single codepoints that default to coloured-emoji presentation.
/// These should advance Terminal.app's cursor by 2; anything else is
/// the VS-16 under-advance class of bug applied to a default-emoji
/// codepoint (rare but possible).
func enumerateSingle() -> [String] {
    return emojiCandidates()
        .filter { $0.properties.isEmojiPresentation }
        .map { String($0) }
}

/// `<base> + U+FE0F` for every default-text-presentation emoji.
/// VS-16 is supposed to promote these to a coloured 2-cell glyph;
/// when Terminal.app advances the cursor by 1 anyway we have Bug A.
/// Default-emoji-presentation codepoints don't need VS-16 (it's a
/// no-op for them) so we skip them.
func enumerateVS16() -> [String] {
    return emojiCandidates()
        .filter { $0.properties.isEmoji && !$0.properties.isEmojiPresentation }
        .map { base in
            var s = ""
            s.unicodeScalars.append(base)
            s.unicodeScalars.append(vs16)
            return s
        }
}

/// `<base> + <Fitzpatrick>` for every codepoint that legitimately
/// accepts a skin-tone modifier (per Unicode's
/// `Emoji_Modifier_Base` property).  Filtering by this property
/// avoids the noise programmatic enumeration produced — Mahjong
/// tiles, dominos, food emoji etc. accept a Fitzpatrick byte at the
/// grapheme-cluster level but the result is meaningless and triggers
/// the over-advance only because Terminal.app sees a Fitzpatrick
/// scalar.
func enumerateSkinTone() -> [String] {
    return emojiCandidates()
        .filter { $0.properties.isEmojiModifierBase }
        .flatMap { base in
            fitzpatrick.map { tone in
                var s = ""
                s.unicodeScalars.append(base)
                s.unicodeScalars.append(tone)
                return s
            }
        }
}

/// Regional indicator pairs (U+1F1E6..1F1FF).  All 26×26 = 676 are
/// valid grapheme clusters per Unicode, of which ~270 are recognised
/// as real country flags.  We scan all of them.
func enumerateFlags() -> [String] {
    var out: [String] = []
    let ri: ClosedRange<UInt32> = 0x1F1E6...0x1F1FF
    for a in ri {
        for b in ri {
            guard let sa = Unicode.Scalar(a), let sb = Unicode.Scalar(b) else { continue }
            var s = ""
            s.unicodeScalars.append(sa)
            s.unicodeScalars.append(sb)
            out.append(s)
        }
    }
    return out
}

// MARK: - Output

func formatCodepoints(_ scalars: [Unicode.Scalar]) -> String {
    return scalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
}

func writeReport(_ results: [Result], to handle: FileHandle, format: OutputFormat) {
    switch format {
    case .tsv:
        // Header
        let header = "codepoints\tcluster\tclaimed\tactual\tverdict\n"
        handle.write(header.data(using: .utf8)!)
        for r in results {
            let line = "\(formatCodepoints(r.codepoints))\t\(r.cluster)\t\(r.claimedWidth)\t\(r.actualAdvance)\t\(r.verdict.rawValue)\n"
            handle.write(line.data(using: .utf8)!)
        }
    case .markdown:
        let header = "| codepoints | cluster | claimed | actual | verdict |\n|---|---|---|---|---|\n"
        handle.write(header.data(using: .utf8)!)
        for r in results {
            let line = "| `\(formatCodepoints(r.codepoints))` | \(r.cluster) | \(r.claimedWidth) | \(r.actualAdvance) | \(r.verdict.rawValue) |\n"
            handle.write(line.data(using: .utf8)!)
        }
    }
}

enum OutputFormat { case tsv, markdown }

// MARK: - Main

struct Options {
    var sets: Set<String> = ["all"]
    var outputPath: String? = nil
    var format: OutputFormat = .tsv
    var quiet: Bool = false
    var onlyDiscrepancies: Bool = true
}

func parseArgs() -> Options {
    var opts = Options()
    var sets: Set<String> = []
    var i = 1
    while i < CommandLine.arguments.count {
        let arg = CommandLine.arguments[i]
        switch arg {
        case "--single":     sets.insert("single")
        case "--vs16":       sets.insert("vs16")
        case "--skin-tone":  sets.insert("skin-tone")
        case "--flags":      sets.insert("flags")
        case "--all":        sets = ["single", "vs16", "skin-tone", "flags"]
        case "--output":
            i += 1
            opts.outputPath = CommandLine.arguments[i]
        case "--format":
            i += 1
            let f = CommandLine.arguments[i]
            opts.format = (f == "markdown") ? .markdown : .tsv
        case "--quiet":      opts.quiet = true
        case "--all-rows":   opts.onlyDiscrepancies = false
        case "--help":
            printUsage(); exit(0)
        default:
            FileHandle.standardError.write("unrecognised argument: \(arg)\n".data(using: .utf8)!)
            exit(2)
        }
        i += 1
    }
    if sets.isEmpty { sets = ["single", "vs16", "skin-tone", "flags"] }
    opts.sets = sets
    return opts
}

func printUsage() {
    let usage = """
    Usage: EmojiBugScanner [options]

    Sets:
      --single       Single-codepoint emoji in pictographic ranges
      --vs16         <base> + U+FE0F variation selector
      --skin-tone    <base> + Fitzpatrick modifiers U+1F3FB..1F3FF
      --flags        Regional-indicator pairs (RI×RI = 676 clusters)
      --all          All of the above (default)

    Output:
      --output FILE  Write report to FILE instead of stderr
      --format FMT   tsv (default) or markdown
      --all-rows     Include "normal" clusters too (default: discrepancies only)
      --quiet        Suppress progress line on stderr

    Must be run in Terminal.app — DSR replies require a real TTY.
    """
    print(usage)
}

func main() {
    let opts = parseArgs()

    // Build the corpus.
    var corpus: [String] = []
    if opts.sets.contains("single")    { corpus += enumerateSingle()   }
    if opts.sets.contains("vs16")      { corpus += enumerateVS16()     }
    if opts.sets.contains("skin-tone") { corpus += enumerateSkinTone() }
    if opts.sets.contains("flags")     { corpus += enumerateFlags()    }

    // De-duplicate while preserving order.
    var seen = Set<String>()
    corpus = corpus.filter { seen.insert($0).inserted }

    if !opts.quiet {
        FileHandle.standardError.write("scanning \(corpus.count) clusters\n".data(using: .utf8)!)
    }

    // Enable raw mode on the TTY so we can read DSR replies, and disable
    // autowrap so a 2-cell cluster near the right edge doesn't wrap
    // and skew the column reading.
    let raw = RawMode.enable()
    defer { raw.restore() }

    // Save terminal state.
    writeString("\u{1B}[?1049h")     // alternate screen buffer
    writeString("\u{1B}[?25l")        // hide cursor
    writeString("\u{1B}[?7l")         // autowrap off
    defer {
        writeString("\u{1B}[?7h")     // restore autowrap
        writeString("\u{1B}[?25h")    // show cursor
        writeString("\u{1B}[?1049l")  // leave alternate screen
    }

    // Run the scan.
    var results: [Result] = []
    results.reserveCapacity(corpus.count)
    let progressEvery = max(corpus.count / 20, 50)
    let startTime = Date()

    for (i, cluster) in corpus.enumerated() {
        let r = probe(cluster: cluster)
        results.append(r)
        if !opts.quiet && (i % progressEvery == 0 || i == corpus.count - 1) {
            let elapsed = Date().timeIntervalSince(startTime)
            let rate = Double(i + 1) / elapsed
            // Status on row 1 so it doesn't interfere with the test row.
            writeString("\u{1B}[1;1H\u{1B}[2K")
            writeString("[\(i + 1)/\(corpus.count)  \(String(format: "%.0f", rate))/s] ")
            writeString(cluster)
        }
    }

    // Restore the screen before printing the report.
    writeString("\u{1B}[?7h")
    writeString("\u{1B}[?25h")
    writeString("\u{1B}[?1049l")

    // Filter to discrepancies if requested.
    let filtered = opts.onlyDiscrepancies
        ? results.filter { $0.verdict != .normal }
        : results

    // Write the report.
    let outHandle: FileHandle
    if let path = opts.outputPath {
        FileManager.default.createFile(atPath: path, contents: nil)
        guard let h = FileHandle(forWritingAtPath: path) else {
            FileHandle.standardError.write("could not open \(path)\n".data(using: .utf8)!)
            exit(1)
        }
        outHandle = h
    } else {
        outHandle = FileHandle.standardOutput
    }
    writeReport(filtered, to: outHandle, format: opts.format)

    // Summary on stderr.
    let underAdvance = results.filter { $0.verdict == .underAdvance }.count
    let overAdvance  = results.filter { $0.verdict == .overAdvance  }.count
    let parseFail    = results.filter { $0.verdict == .parseFailure }.count
    let normal       = results.filter { $0.verdict == .normal       }.count
    let summary = """

    scanned: \(results.count)
      normal:        \(normal)
      under-advance: \(underAdvance)
      over-advance:  \(overAdvance)
      parse-failure: \(parseFail)
    elapsed: \(String(format: "%.2f", Date().timeIntervalSince(startTime)))s

    """
    FileHandle.standardError.write(summary.data(using: .utf8)!)
}

main()
