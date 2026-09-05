//  🖥️ TUIkit — Terminal UI Kit for Swift
//  generate.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// Regenerates `Sources/TUIkitCore/Extensions/CombiningMarkRanges.generated.swift`
// from the Unicode Character Database.
//
//     swift Tools/GenerateCombiningMarks/generate.swift \
//         > Sources/TUIkitCore/Extensions/CombiningMarkRanges.generated.swift
//
// With no argument it reads the CURRENT Unicode release from unicode.org
// (`Public/UCD/latest/`). Pass a version — `17.0.0` — to read that release's
// `UnicodeData.txt` instead, or a path to a local copy of the file, in which
// case the version stamped into the output is "local".
//
// A mark of general category `Mn` (nonspacing) or `Me` (enclosing) occupies no
// terminal column; `Mc` (spacing combining) does, and is deliberately absent.
//
// The table exists because asking `Unicode.Scalar.Properties.generalCategory`
// on the width path cost a measured 2–3% on four Stress scenarios — it is a
// second stdlib property lookup for every non-ASCII scalar that is not
// box-drawing, which in a terminal UI is every arrow, bullet, ellipsis and
// braille cell. A binary search over a few hundred integer ranges is not.
//
// Why the database and not the standard library the tool runs on: the
// library's Unicode lags. On macOS the tables ship with the OS, so the same
// Xcode answers Unicode 16 on macOS 15 and 17 on macOS 26, and Swift 6.2 and
// 6.3 on Linux differ the same way. A table generated from whichever runtime
// happened to run this tool then disagrees with every newer one — which is
// exactly how CI went red: eight marks Unicode 17 added at U+1ACF were "not a
// mark" to a table generated on macOS 15, and every macOS 26 and Swift 6.3 lane
// measured them one cell wide. The terminal drawing the text is newer than the
// runtime as often as not, so the table follows the newest published data and
// `CombiningMarkRangeTests` checks it against the runtime in the only way that
// holds across versions: every mark the runtime knows is in the table, and
// anything the table has beyond that is a codepoint the runtime has not
// assigned at all.
import Foundation

let argument = CommandLine.arguments.dropFirst().first
let source: (data: URL, version: String)
if let argument, FileManager.default.fileExists(atPath: argument) {
    source = (URL(fileURLWithPath: argument), "local")
} else {
    let release = argument ?? "latest"
    let directory = release == "latest" ? "UCD/latest" : release
    guard let base = URL(string: "https://www.unicode.org/Public/\(directory)/") else {
        fatalError("not a release: \(release)")
    }
    // The database itself does not say which release it is; the directory's
    // ReadMe does ("for Version 17.0.0 of the Unicode Standard").
    let readme = (try? String(contentsOf: base.appendingPathComponent("ReadMe.txt"), encoding: .utf8)) ?? ""
    let version = readme.firstMatch(of: #/Version (\d+\.\d+\.\d+)/#).map { String($0.1) } ?? release
    source = (base.appendingPathComponent("ucd/UnicodeData.txt"), version)
}

guard let database = try? String(contentsOf: source.data, encoding: .utf8) else {
    fatalError("could not read \(source.data)")
}

// UnicodeData.txt is one scalar per line — `code;name;category;…` — except
// that large uniform blocks are written as a `<…, First>` / `<…, Last>` pair.
// No mark block is written that way, but the parser honours the form so a
// future one would be read rather than silently halved.
var marks: [UInt32] = []
var rangeStart: UInt32?
for line in database.split(separator: "\n") {
    let fields = line.split(separator: ";", omittingEmptySubsequences: false)
    guard fields.count > 2, let value = UInt32(fields[0], radix: 16) else { continue }
    let isMark = fields[2] == "Mn" || fields[2] == "Me"
    if fields[1].hasSuffix(", First>") {
        rangeStart = isMark ? value : nil
    } else if fields[1].hasSuffix(", Last>") {
        if let start = rangeStart { marks.append(contentsOf: start...value) }
        rangeStart = nil
    } else if isMark {
        marks.append(value)
    }
}

var ranges: [(UInt32, UInt32)] = []
for value in marks.sorted() {
    if let last = ranges.last, last.1 + 1 == value {
        ranges[ranges.count - 1].1 = value
    } else {
        ranges.append((value, value))
    }
}

print("""
//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CombiningMarkRanges.generated.swift
//
//  Created by Wade Tregaskis
//  License: MIT

//  GENERATED — do not edit by hand.
//
//  Produced by `Tools/GenerateCombiningMarks/generate.swift` from the Unicode
//  Character Database, release \(source.version). See that tool for why the
//  table exists rather than a property lookup, why it follows the database
//  rather than the standard library, and `CombiningMarkRangeTests` for what
//  keeps it honest.

/// The Unicode release the table below was generated from.
let combiningMarkUnicodeVersion = "\(source.version)"

/// Every codepoint range whose scalars are nonspacing (`Mn`) or enclosing
/// (`Me`) marks — the ones that occupy no terminal column. Sorted and
/// disjoint, so a binary search decides membership.
///
/// `Mc`, a spacing combining mark such as a Devanagari matra, is NOT here: it
/// advances, and treating it as zero would make a line of Devanagari measure
/// short.
let combiningMarkRanges: [(UInt32, UInt32)] = [
""")
var line = "   "
for (low, high) in ranges {
    let entry = String(format: " (0x%05X, 0x%05X),", low, high)
    if line.count + entry.count > 100 {
        print(line)
        line = "   "
    }
    line += entry
}
if line != "   " { print(line) }
print("]")
print("")
print("/// The first and last codepoints any mark occupies, so the overwhelmingly")
print("/// common answer — \"no\" — costs two comparisons rather than a search.")
print(String(format: "let combiningMarkFloor: UInt32 = 0x%05X", ranges.first?.0 ?? 0))
print(String(format: "let combiningMarkCeiling: UInt32 = 0x%05X", ranges.last?.1 ?? 0))
