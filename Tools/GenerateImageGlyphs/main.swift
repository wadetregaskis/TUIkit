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
///
/// Every printable ASCII character: the matcher picks by measured 6-region
/// ink coverage, so a bigger vocabulary only ever improves the fit — a `y`
/// really is the best rendering of some cells (heavy centre, tail
/// lower-left), and the old hand-curated 29 left most of that shape space
/// unreachable. Redundant near-duplicates cost a few comparisons per cell
/// and nothing else.
let shapeGlyphs: [Character] = (0x20...0x7E).map { Character(UnicodeScalar($0)!) }

/// The additional glyphs of the WIDE Unicode set (`.unicodeDetailed`),
/// chosen for strong spatial signatures and near-universal terminal-font
/// coverage (Block Elements, Box Drawing, and the common Geometric Shapes —
/// all single-cell in terminal fonts; the width test in ImageTests pins
/// that against TUIkit's own width tables):
///
/// - shades for even tone, half blocks, quadrants, and the FULL horizontal
///   + vertical eighth-block ladders (including the often-forgotten upper
///   `▔` and right `▕` eighths) for fine partial coverage;
/// - box-drawing lines and corners in light, heavy, double and rounded
///   weights — thin strokes with exact placement, a register the blocks
///   can't express. Tees and crossings (`┼ ╬ ┳ …`) are deliberately
///   EXCLUDED: at the 6-circle sampling resolution their vectors are
///   indistinguishable from an even mid-tone, so they beat the shades for
///   flat regions and render smooth areas as lattice;
/// - box-drawing diagonals `╱ ╲ ╳`;
/// - filled/outline geometric shapes (triangles, corner triangles,
///   circles, squares, diamond) whose ink distributions cover curved and
///   diagonal features.
///
/// Combined with the ASCII shape glyphs above into
/// `generatedUnicodeShapeCoverage`, so the matcher can pick whichever
/// family fits a cell best. Characters the reference font lacks natively
/// are skipped at generation time (see `nativeGlyph`), so CoreText's
/// font-fallback can't calibrate glyphs end-user fonts likely miss —
/// except the `fallbackAllowedGlyphs`, measured through the fallback
/// deliberately.
let unicodeExtraGlyphs: [Character] = Array(
    "░▒▓█▀▄▌▐▔▕▁▂▃▅▆▇▉▊▋▍▎▏▘▝▖▗▚▞▛▜▙▟"
        + "─│┌┐└┘━┃┏┓┗┛═║╔╗╚╝╭╮╯╰╱╲╳"
        + "▲▼◀▶◤◥◣◢●○◦■□▪▫◆◇")

/// Glyphs measured even when the reference font lacks them natively: the
/// corner triangles are essential to the shape-aware BLOCKS repertoire
/// (diagonal edges the quadrants can't express), ship in the common
/// terminal fallback fonts (Menlo, Apple Symbols, DejaVu Sans Mono), and
/// render correctly in Terminal.app via CoreText's own fallback — the very
/// mechanism this raster path uses to measure them.
let fallbackAllowedGlyphs: Set<Character> = ["◢", "◣", "◤", "◥"]

// MARK: - Generate

/// Whether the reference font natively contains a glyph for `ch`.
/// `CTLineDraw` silently falls back to another font for missing characters,
/// which would calibrate a glyph most terminal fonts show as tofu (or with
/// non-monospace metrics) — those are skipped and reported instead.
func nativeGlyph(_ ch: Character) -> Bool {
    let utf16 = Array(String(ch).utf16)
    var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
    let mapped = CTFontGetGlyphsForCharacters(ctFont, utf16, &glyphs, utf16.count)
    return mapped && glyphs.allSatisfy { $0 != 0 }
}

var skippedGlyphs: [Character] = []

/// One calibrated row: the glyph, its TOTAL ink coverage over the whole
/// cell (for density-ramp selection), and its 6-region shape vector (for
/// shape matching and flatness scoring).
typealias CalibratedRow = (glyph: Character, total: Double, regions: [Double])

func calibrate(_ glyph: Character) -> CalibratedRow {
    let ink = rasterInk(glyph)
    return (glyph, totalCoverage(ink), shapeVector(ink))
}

var rows: [CalibratedRow] = []
for glyph in shapeGlyphs + unicodeExtraGlyphs {
    guard nativeGlyph(glyph) || fallbackAllowedGlyphs.contains(glyph) else {
        skippedGlyphs.append(glyph)
        continue
    }
    rows.append(calibrate(glyph))
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

/// Every calibrated glyph: its TOTAL ink coverage over the whole cell (0…1,
/// for density-ramp selection) and its raw 6-region coverage vector (for
/// shape matching and flatness scoring; normalised at load). The runtime
/// partitions this one table into the fundamental charsets by Unicode range
/// — see `GlyphRepertoire`.
let generatedGlyphCalibration: [(Character, Double, [Double])] = [

"""
for row in rows {
    let literal = escaped(row.glyph)
    let values = row.regions.map(fmt).joined(separator: ", ")
    out += "    (\(literal), \(fmt(row.total)), [\(values)]),\n"
}
out += """
]

"""

func escaped(_ ch: Character) -> String {
    switch ch {
    case "\\": return "\"\\\\\""
    case "\"": return "\"\\\"\""
    default: return "\"\(ch)\""
    }
}

let outputPath = "Sources/TUIkitImage/ImageGlyphCalibration.generated.swift"
try! out.write(toFile: outputPath, atomically: true, encoding: .utf8)

// Summary + sanity checks (T upper-heavy, _ lower-heavy; the quadrants and
// corner triangles must put their ink in their own corner).
func vec(_ ch: Character) -> [Double] { rows.first { $0.glyph == ch }?.regions ?? [] }
let tVec = vec("T")
let underscore = vec("_")
let upperLeft = vec("▘")
let lowerRight = vec("▗")
let lowerRightTriangle = vec("◢")
print("Reference font : \(resolvedName) \(Int(pointSize))pt  →  cell \(pxW)×\(pxH)px")
print("Glyphs         : \(rows.count) calibrated")
if !skippedGlyphs.isEmpty {
    print("Skipped (font) : \(String(skippedGlyphs)) — not native to the reference font")
}
print("sanity  'T'    : upper \(fmt(tVec[0]))/\(fmt(tVec[1]))  lower \(fmt(tVec[4]))/\(fmt(tVec[5]))")
print("sanity  '_'    : upper \(fmt(underscore[0]))/\(fmt(underscore[1]))  lower \(fmt(underscore[4]))/\(fmt(underscore[5]))")
print("sanity  '▘'    : upper-L \(fmt(upperLeft[0])) vs upper-R \(fmt(upperLeft[1]))  lower-L \(fmt(upperLeft[4])) lower-R \(fmt(upperLeft[5]))")
print("sanity  '◢'    : upper-L \(fmt(lowerRightTriangle[0])) vs lower-R \(fmt(lowerRightTriangle[5]))")
print("sanity  '▗'    : upper-L \(fmt(lowerRight[0])) vs lower-R \(fmt(lowerRight[5]))")
print("wrote \(outputPath)")
