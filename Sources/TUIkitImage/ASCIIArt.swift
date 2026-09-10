//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ASCIIArt.swift
//
//  What a conversion produces: the styled lines, and what each cell's ink and
//  field were actually drawn at.
//
//  Created by Wade Tregaskis
//  License: MIT

/// One converted picture.
///
/// ``ASCIIConverter/convert(_:width:height:)`` returned `[String]` until the glyph
/// path started carrying alpha, and that was the whole reason it could not: a cell's
/// colours are chosen from pixels that may be partly or wholly transparent, and a
/// string has nowhere to say so. The renderers composited over BLACK instead — every
/// one of them read colour and never alpha — so a logo with a transparent surround
/// came out as an explicit black rectangle: invisible on a dark theme, glaring on a
/// light one.
///
/// See `Documentation/Opacity as composition.md` §42.
public struct ASCIIArt: Sendable, Equatable {
    /// The styled lines, one per cell row.
    public var lines: [String]

    /// The cells whose ink or field was drawn at less than full coverage.
    ///
    /// **Empty for a fully opaque picture**, which is nearly every picture — the
    /// same contract `Text.uniformAlphaClaims` states: "no claim" has to be cheaper
    /// than a list of claims that say nothing, and a photograph has no transparency
    /// at all.
    public var coverage: [CoverageRun]

    public init(lines: [String], coverage: [CoverageRun] = []) {
        self.lines = lines
        self.coverage = coverage
    }

    /// A run of adjacent cells on one line whose ink and field share a coverage.
    ///
    /// Runs rather than cells because an image's alpha is mostly large uniform areas:
    /// a logo's transparent surround is one run per line, and a photograph is none at
    /// all. The coalescing is the same rule `Array.appendCoalescing` applies to
    /// `OpacityRegion`s one module up, for the same reason — the resolver's cost is
    /// per region per covered row.
    public struct CoverageRun: Sendable, Equatable {
        /// The line, indexed into ``ASCIIArt/lines``.
        public var line: Int

        /// The cells, in that line's own columns.
        public var columns: Range<Int>

        /// What the glyph was drawn at. `.max` where the cell draws none.
        public var ink: UInt8

        /// What the cell's background was drawn at. `.max` where it paints none.
        public var field: UInt8

        public init(line: Int, columns: Range<Int>, ink: UInt8, field: UInt8) {
            self.line = line
            self.columns = columns
            self.ink = ink
            self.field = field
        }
    }
}

/// Collects a picture's coverage runs as its cells are emitted.
///
/// Every renderer walks cells left to right, top to bottom, so a run closes when the
/// next cell disagrees about either channel or skips a column. Fully opaque cells are
/// dropped rather than recorded, which is what keeps an opaque picture's list empty
/// without the caller testing for it.
struct CoverageMap {
    private(set) var runs: [ASCIIArt.CoverageRun] = []

    /// One cell, at `column` of `line`.
    ///
    /// The two channels are separate because a half-block cell paints them from
    /// DIFFERENT pixels — the top pixel is the field and the bottom one the ink — so a
    /// cell can be fully covered in one and not at all in the other. That is also the
    /// case that stops such a cell coalescing with its neighbours.
    mutating func note(line: Int, column: Int, ink: UInt8, field: UInt8) {
        guard ink != .max || field != .max else { return }
        if var last = runs.last, last.line == line, last.columns.upperBound == column,
            last.ink == ink, last.field == field
        {
            last.columns = last.columns.lowerBound..<(column + 1)
            runs[runs.count - 1] = last
            return
        }
        runs.append(
            ASCIIArt.CoverageRun(
                line: line, columns: column..<(column + 1), ink: ink, field: field))
    }
}
