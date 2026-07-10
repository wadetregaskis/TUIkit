//  🖥️ TUIKit — Terminal UI Kit for Swift
//  main.swift  —  GenerateImageGlyphs
//
//  Created by Wade Tregaskis
//  License: MIT
//
//  (Named `main.swift` because it is compiled together with the framework's
//  ShapeSampling.swift — Swift only allows top-level code in a file so named
//  when more than one file is compiled at once.)
//
//  Font-rasterisation calibration for the Image renderer. Rasterises each
//  candidate glyph in a reference monospace font (SF Mono Regular 11 by
//  default — the font macOS Terminal.app uses) via CoreText, measures its ink
//  coverage, and emits two calibrated tables into
//  `Sources/TUIkitImage/ImageGlyphCalibration.generated.swift`:
//
//    • `generatedShapeCoverage` — per-glyph raw 6-region coverage vectors for
//      the shape renderer, sampled at the SAME six staggered circles the
//      runtime uses (so they drop straight into `computeShapeTable`, which
//      normalises them). Replaces the hand-drawn 5×10 bitmaps with values
//      measured from the real font.
//    • `generatedAsciiDetailedRamp` — a coverage-ordered, gap-free pure-ASCII
//      ramp for `.asciiDetailed`, replacing the hand-picked Bourke ordering
//      with one calibrated to the reference font's actual ink coverage.
//
//  The sampling geometry (`ShapeRegion`) is not duplicated here: generate.sh
//  compiles the framework's own `Sources/TUIkitImage/ShapeSampling.swift` into
//  this tool, so the circles and spiral are the exact same source the runtime
//  samples the image with.
//
//  macOS-only developer tooling (CoreText). End users consume the committed
//  generated file; nothing here ships in the package.

import AppKit
import CoreText
import Foundation

// MARK: - Reference font

let pointSize: CGFloat = 11
// SF Mono isn't always registered under its display name; fall back to the
// system monospaced font (which is SF Mono) so this resolves everywhere.
let font: NSFont =
    NSFont(name: "SF Mono", size: pointSize)
    ?? .monospacedSystemFont(ofSize: pointSize, weight: .regular)
let ctFont = font as CTFont
let resolvedName = CTFontCopyPostScriptName(ctFont) as String

// MARK: - Cell metrics (define the rasterisation box, from the font itself)

let ascent = CTFontGetAscent(ctFont)
let descent = CTFontGetDescent(ctFont)
let leading = CTFontGetLeading(ctFont)
let cellHeightPt = ascent + descent + leading

/// The advance of a representative monospace glyph — the cell width.
func advanceWidth() -> CGFloat {
    var glyph = CGGlyph(0)
    var ch: UniChar = 0x4D  // 'M'
    CTFontGetGlyphsForCharacters(ctFont, &ch, &glyph, 1)
    var advance = CGSize.zero
    CTFontGetAdvancesForGlyphs(ctFont, .horizontal, &glyph, &advance, 1)
    return advance.width
}
let cellWidthPt = advanceWidth()

/// Supersample: rasterise well above the 11pt cell so anti-aliased coverage is
/// measured cleanly. Coverage ratios are ~scale-invariant, so the point size
/// sets the *aspect*, the scale sets the *resolution*.
let scale: CGFloat = 8
let pxW = max(1, Int((cellWidthPt * scale).rounded()))
let pxH = max(1, Int((cellHeightPt * scale).rounded()))

// The shape sampling geometry (`ShapeRegion`) is NOT redefined here: this tool
// compiles the framework's own `ShapeSampling.swift` (see generate.sh), so the
// circle centres, radius, sample count, and spiral are literally the same
// source the runtime renders with — they cannot drift.

// MARK: - Rasterisation

/// Renders `ch` into the cell and returns per-pixel ink in `[0, 1]`
/// (`1 − luminance/255`, matching the runtime's darkness measure), row 0 = top.
func rasterInk(_ ch: Character) -> [Double] {
    var pixels = [UInt8](repeating: 255, count: pxW * pxH)  // white background
    pixels.withUnsafeMutableBytes { raw in
        guard
            let ctx = CGContext(
                data: raw.baseAddress, width: pxW, height: pxH, bitsPerComponent: 8,
                bytesPerRow: pxW, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return }
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.scaleBy(x: scale, y: scale)  // draw the 11pt font up to fill the buffer
        let attributed = NSAttributedString(
            string: String(ch),
            attributes: [.font: font, .foregroundColor: NSColor.black])
        let line = CTLineCreateWithAttributedString(attributed)
        // Baseline sits `descent` above the cell bottom (so the ascent fits above).
        ctx.textPosition = CGPoint(x: 0, y: descent)
        CTLineDraw(line, ctx)
    }
    // CGBitmapContext memory is top-row-first, so index r == top-down already.
    return pixels.map { 1.0 - Double($0) / 255.0 }
}

/// The mean ink over the whole cell (total coverage), for the ramp ordering.
func totalCoverage(_ ink: [Double]) -> Double {
    ink.reduce(0, +) / Double(ink.count)
}

/// The 6-region coverage vector. Samples at exactly the points the runtime
/// uses (`ShapeRegion.normalizedSamplePoints()`) and maps them with the same
/// `ShapeRegion.pixel(for:width:height:)` — both shared source — into the
/// supersampled glyph raster, reading fractional ink rather than a source-image
/// pixel. Geometry and mapping match the runtime by construction, not by
/// hand-kept parallel copies.
func shapeVector(_ ink: [Double]) -> [Double] {
    let points = ShapeRegion.normalizedSamplePoints()
    let samples = ShapeRegion.samplesPerCircle
    return (0..<ShapeRegion.centres.count).map { centreIndex in
        var sum = 0.0
        for sampleIndex in 0..<samples {
            let point = points[centreIndex * samples + sampleIndex]
            let (px, py) = ShapeRegion.pixel(for: point, width: pxW, height: pxH)
            sum += ink[py * pxW + px]
        }
        return sum / Double(samples)
    }
}

// MARK: - Candidate glyph sets

/// The shape renderer's glyph set. This tool is the single author of it: the
/// glyphs here become the keys of `generatedShapeCoverage`, which the runtime
/// reads back — so there is no separate copy in the framework to keep in sync.
let shapeGlyphs: [Character] = Array(" .,'`\":;-_~^|/\\+*=<>LJTVIO#%@")

/// The additional glyphs of the WIDE Unicode set (`.unicodeDetailed`): block
/// elements with strong spatial signatures — shades for even tone, half
/// blocks, quadrants (a corner's worth of ink exactly where the image has
/// it), and the vertical/horizontal eighth-block ladders for fine partial
/// coverage. Combined with the ASCII shape glyphs above into
/// `generatedUnicodeShapeCoverage`, so the matcher can pick whichever family
/// fits a cell best.
let unicodeExtraGlyphs: [Character] = Array("░▒▓█▀▄▌▐▁▂▃▅▆▇▉▊▋▍▎▏▘▝▖▗▚▞▛▜▙▟")

// MARK: - Generate

var shapeRows: [(Character, [Double])] = []
for glyph in shapeGlyphs {
    shapeRows.append((glyph, shapeVector(rasterInk(glyph))))
}

var unicodeRows: [(Character, [Double])] = shapeRows
for glyph in unicodeExtraGlyphs {
    unicodeRows.append((glyph, shapeVector(rasterInk(glyph))))
}

// Coverage-ordered ASCII ramp: measure every printable ASCII glyph, sort by
// coverage, drop near-duplicate coverages (they add banding, not levels), and
// anchor with a leading space (zero ink).
let epsilon = 0.010
var ramp: [(Character, Double)] = []
for code in 0x21...0x7E {  // '!'…'~'
    let ch = Character(UnicodeScalar(code)!)
    ramp.append((ch, totalCoverage(rasterInk(ch))))
}
ramp.sort { $0.1 < $1.1 }
var rampGlyphs: [Character] = [" "]
var lastCoverage = 0.0
for (ch, coverage) in ramp where coverage - lastCoverage >= epsilon {
    rampGlyphs.append(ch)
    lastCoverage = coverage
}

// MARK: - Emit

func fmt(_ value: Double) -> String { String(format: "%.4f", value) }

var out = """
//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ImageGlyphCalibration.generated.swift
//
//  Created by Wade Tregaskis
//  License: MIT

//  GENERATED — do not edit by hand.
//
//  Produced by `Tools/GenerateImageGlyphs/generate.sh` by rasterising
//  \(resolvedName) at \(Int(pointSize))pt (cell \(pxW)×\(pxH)px supersampled)
//  and measuring ink coverage. See that tool for how and why.

/// Per-glyph raw 6-region ink-coverage vectors for the shape renderer, measured
/// from the reference font. Normalised at load by `computeShapeTable`.
let generatedShapeCoverage: [(Character, [Double])] = [

"""
for (ch, vector) in shapeRows {
    let literal = escaped(ch)
    let values = vector.map(fmt).joined(separator: ", ")
    out += "    (\(literal), [\(values)]),\n"
}
out += """
]

/// Like `generatedShapeCoverage` but over the WIDE Unicode set backing
/// `.unicodeDetailed`: the ASCII shape glyphs plus shades, half blocks,
/// quadrants, and the eighth-block ladders.
let generatedUnicodeShapeCoverage: [(Character, [Double])] = [

"""
for (ch, vector) in unicodeRows {
    let literal = escaped(ch)
    let values = vector.map(fmt).joined(separator: ", ")
    out += "    (\(literal), [\(values)]),\n"
}
out += """
]

/// A coverage-ordered, gap-free pure-ASCII ramp (light → dense) calibrated to
/// the reference font, backing `.asciiDetailed`.
let generatedAsciiDetailedRamp: [Character] = Array(\(swiftStringLiteral(rampGlyphs)))

"""

func escaped(_ ch: Character) -> String {
    switch ch {
    case "\\": return "\"\\\\\""
    case "\"": return "\"\\\"\""
    default: return "\"\(ch)\""
    }
}

func swiftStringLiteral(_ chars: [Character]) -> String {
    var s = "\""
    for ch in chars {
        switch ch {
        case "\\": s += "\\\\"
        case "\"": s += "\\\""
        default: s += String(ch)
        }
    }
    return s + "\""
}

let outputPath = "Sources/TUIkitImage/ImageGlyphCalibration.generated.swift"
try! out.write(toFile: outputPath, atomically: true, encoding: .utf8)

// Summary + sanity checks (T upper-heavy, _ lower-heavy; the quadrants must
// put their ink in their own corner).
func vec(_ ch: Character) -> [Double] { unicodeRows.first { $0.0 == ch }?.1 ?? [] }
let tVec = vec("T")
let underscore = vec("_")
let upperLeft = vec("▘")
let lowerRight = vec("▗")
print("Reference font : \(resolvedName) \(Int(pointSize))pt  →  cell \(pxW)×\(pxH)px")
print("Shape glyphs   : \(shapeRows.count) ascii, \(unicodeRows.count) unicode")
print("ASCII ramp     : \(rampGlyphs.count) levels  '\(String(rampGlyphs))'")
print("sanity  'T'    : upper \(fmt(tVec[0]))/\(fmt(tVec[1]))  lower \(fmt(tVec[4]))/\(fmt(tVec[5]))")
print("sanity  '_'    : upper \(fmt(underscore[0]))/\(fmt(underscore[1]))  lower \(fmt(underscore[4]))/\(fmt(underscore[5]))")
print("sanity  '▘'    : upper-L \(fmt(upperLeft[0])) vs upper-R \(fmt(upperLeft[1]))  lower-L \(fmt(upperLeft[4])) lower-R \(fmt(upperLeft[5]))")
print("sanity  '▗'    : upper-L \(fmt(lowerRight[0])) vs lower-R \(fmt(lowerRight[5]))")
print("wrote \(outputPath)")
