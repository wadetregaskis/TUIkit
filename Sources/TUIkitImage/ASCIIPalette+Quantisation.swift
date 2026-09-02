//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ASCIIPalette+Quantisation.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitStyling

// MARK: - Answering the same question a million times

extension ASCIIPalette {

    /// Bits of each channel the table is keyed on. Five gives 32,768 cells —
    /// small enough to build in a fraction of what it saves, fine enough that
    /// the answer differs from the exact one only for colours sitting within
    /// a few units of a boundary between two entries.
    static let quantisationBits = 5

    /// The number of cells in a ``quantisationTable()``.
    static let quantisationCells = 1 << (3 * quantisationBits)

    /// Which of the 32 buckets each byte value falls in, and the byte that
    /// best represents each bucket.
    ///
    /// **Spaced by lightness, not by value.** Equal steps of an sRGB byte are
    /// not equal steps of anything a person sees: the transfer function is
    /// steep in the shadows, so the darkest eighth of the range holds a large
    /// part of the perceptual distance. A table cut into 32 equal byte-ranges
    /// is therefore far too coarse where the eye is most sensitive — measured,
    /// it disagreed with the exact search for 5.1% of colours and sometimes
    /// picked the fourth-nearest entry rather than the second.
    ///
    /// Cut into 32 equal steps of the cube root of linear light — the same
    /// curve OKLab's own `l` is built on — the cells are perceptually even and
    /// the disagreement collapses. See `PaletteTableFidelityTests` for the
    /// measured numbers on both.
    static let quantisationBucket: [UInt8] = {
        var buckets = [UInt8](repeating: 0, count: 256)
        for value in 0...255 {
            let perceptual = cbrt(Color.linearChannel(UInt8(value)))
            let bucket = Int(perceptual * Double(1 << quantisationBits))
            buckets[value] = UInt8(min((1 << quantisationBits) - 1, max(0, bucket)))
        }
        return buckets
    }()

    /// The byte in the middle of each bucket — what the table asks the exact
    /// search about when it builds a cell's answer.
    static let quantisationRepresentative: [UInt8] = {
        var first = [Int](repeating: -1, count: 1 << quantisationBits)
        var last = [Int](repeating: -1, count: 1 << quantisationBits)
        for value in 0...255 {
            let bucket = Int(quantisationBucket[value])
            if first[bucket] < 0 { first[bucket] = value }
            last[bucket] = value
        }
        return (0..<(1 << quantisationBits)).map { bucket in
            guard first[bucket] >= 0 else { return UInt8(0) }
            return UInt8((first[bucket] + last[bucket]) / 2)
        }
    }()

    /// This palette's answer to ``nearestIndex(to:)`` for every cell of a
    /// perceptually-spaced 5-bit-per-channel grid — or `nil` for a palette too
    /// large to index with a byte.
    ///
    /// ## Why a table, and why only here
    ///
    /// `nearestIndex(to:)` converts the pixel to OKLab and walks every entry.
    /// That is the right implementation for the character renderer, which asks
    /// it once per CELL — a 120×48 grid is 5,760 questions. The pixel renderer
    /// asks it once per PIXEL: about 1,050,000 for a realistic placement,
    /// nearly two hundred times more, and measured at 3.4 seconds for
    /// ``ansi16`` in a debug build.
    ///
    /// So this is not an optimisation of `nearestIndex(to:)` — that function is
    /// unchanged, and the character renderer's output with it. It is a
    /// different trade for a caller that needs the same answer a million times:
    /// pay 32,768 exact answers up front and then index.
    ///
    /// ## What it costs in accuracy
    ///
    /// The query is rounded down to its cell and sampled at a representative
    /// point inside it, so a colour lying very close to the boundary between
    /// two palette entries can be given the neighbouring one. Both are, by
    /// definition, among the closest entries to it. `PaletteTableFidelityTests`
    /// walks all 16,777,216 colours and pins how many disagree; the answer is
    /// on the order of a percent, and every one of those is a pixel that was
    /// already a coin toss between two neighbours — which dithering, where it
    /// is on, would have moved anyway.
    ///
    /// The character renderer never consults this.
    func quantisationTable() -> QuantisationTable? {
        guard entries.count <= 256 else { return nil }
        var answers = [UInt8](repeating: 0, count: Self.quantisationCells)
        let span = 1 << Self.quantisationBits
        for red in 0..<span {
            for green in 0..<span {
                for blue in 0..<span {
                    let pixel = RGBA(
                        r: Self.quantisationRepresentative[red],
                        g: Self.quantisationRepresentative[green],
                        b: Self.quantisationRepresentative[blue])
                    answers[Self.cell(red, green, blue)] = UInt8(nearestIndex(to: pixel))
                }
            }
        }

        // Which cells can be TRUSTED. A cell whose six face-neighbours all
        // answer as it does lies in the interior of one palette entry's
        // region, and every colour inside it takes that entry. A cell that
        // disagrees with a neighbour straddles a boundary, and a colour inside
        // it might fall either side — so those are looked up exactly.
        //
        // This is what makes the table honest rather than merely fast. The
        // plain table disagreed with the exact search for about 5% of colours
        // and occasionally chose the fourth-nearest entry; all of that error
        // lived in boundary cells, and boundary cells hold only a few percent
        // of the pixels. The neighbour test costs nothing — it reads answers
        // already computed — and buys back the accuracy the table gave away.
        var trusted = [Bool](repeating: false, count: Self.quantisationCells)
        for red in 0..<span {
            for green in 0..<span {
                for blue in 0..<span {
                    let cell = Self.cell(red, green, blue)
                    let answer = answers[cell]
                    var uniform = true
                    for (dRed, dGreen, dBlue) in Self.faceNeighbours {
                        let (r, g, b) = (red + dRed, green + dGreen, blue + dBlue)
                        guard r >= 0, r < span, g >= 0, g < span, b >= 0, b < span else { continue }
                        if answers[Self.cell(r, g, b)] != answer {
                            uniform = false
                            break
                        }
                    }
                    trusted[cell] = uniform
                }
            }
        }
        return QuantisationTable(answers: answers, trusted: trusted)
    }

    private static let faceNeighbours = [
        (-1, 0, 0), (1, 0, 0), (0, -1, 0), (0, 1, 0), (0, 0, -1), (0, 0, 1),
    ]

    private static func cell(_ red: Int, _ green: Int, _ blue: Int) -> Int {
        (red << (2 * quantisationBits)) | (green << quantisationBits) | blue
    }

    /// A palette's answers for a perceptually-spaced grid, and which of them
    /// can be used without checking.
    struct QuantisationTable {
        let answers: [UInt8]
        let trusted: [Bool]
    }

    /// Where `pixel` falls in a ``quantisationTable()``.
    static func quantisationCell(for pixel: RGBA) -> Int {
        (Int(quantisationBucket[Int(pixel.r)]) << (2 * quantisationBits))
            | (Int(quantisationBucket[Int(pixel.g)]) << quantisationBits)
            | Int(quantisationBucket[Int(pixel.b)])
    }
}

// MARK: - Which modes search a palette at all

extension ASCIIColorMode {

    /// The palette this mode searches for every pixel, or `nil` for one that
    /// answers by arithmetic.
    ///
    /// ``ansi256`` is absent deliberately: it indexes a colour cube by
    /// division rather than searching, which is why it costs a fifth of what
    /// ``ansi16`` costs despite naming sixteen times as many colours.
    var searchedPalette: ASCIIPalette? {
        switch self {
        case .ansi16: ASCIIPalette.ansi16
        case .palette(let palette): palette
        case .trueColor, .grayscale, .mono, .ansi256: nil
        }
    }
}
