// Regenerates `Sources/TUIkitCore/Extensions/CombiningMarkRanges.generated.swift`
// from the Unicode data the Swift standard library carries.
//
//     swift Tools/GenerateCombiningMarks/generate.swift \
//         > Sources/TUIkitCore/Extensions/CombiningMarkRanges.generated.swift
//
// A mark of general category `Mn` (nonspacing) or `Me` (enclosing) occupies no
// terminal column; `Mc` (spacing combining) does, and is deliberately absent.
//
// The table exists because asking `Unicode.Scalar.Properties.generalCategory`
// on the width path cost a measured 2–3% on four Stress scenarios — it is a
// second stdlib property lookup for every non-ASCII scalar that is not
// box-drawing, which in a terminal UI is every arrow, bullet, ellipsis and
// braille cell. A binary search over 354 integer ranges is not.
//
// `CombiningMarkRangeTests` re-derives this from the same source at test time
// and fails if the two disagree, so a toolchain that ships a newer Unicode
// than the one this was generated against is caught rather than silently
// mis-measuring a new script.
import Foundation

func isMark(_ value: UInt32) -> Bool {
    guard let scalar = Unicode.Scalar(value) else { return false }
    switch scalar.properties.generalCategory {
    case .nonspacingMark, .enclosingMark: return true
    default: return false
    }
}

var ranges: [(UInt32, UInt32)] = []
var start: UInt32?
var last: UInt32 = 0
for value in UInt32(0)...0x10FFFF {
    if isMark(value) {
        if start == nil { start = value }
        last = value
    } else if let open = start {
        ranges.append((open, last))
        start = nil
    }
}
if let open = start { ranges.append((open, last)) }

print("""
//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CombiningMarkRanges.generated.swift
//
//  Created by Wade Tregaskis
//  License: MIT

//  GENERATED — do not edit by hand.
//
//  Produced by `Tools/GenerateCombiningMarks/generate.swift` from the Unicode
//  data the Swift standard library carries. See that tool for why the table
//  exists rather than a property lookup, and `CombiningMarkRangeTests` for
//  what keeps it honest.

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
