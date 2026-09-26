//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FrameBuffer+PainterFieldClaims.swift
//
//  A painter that puts a TRANSLUCENT field under content it did not draw — a
//  `.background` of a translucent colour or ramp, a translucent list row fill —
//  cannot spend the content's fades against it (it is not a backdrop yet, §22),
//  so both travel to where what is behind the painter is known. There they meet
//  in one cell, one above the other, and a line holds one field per cell: the
//  painter's where the content leaves the field to it, the content's own where it
//  states one. So the painter says which, cell by cell, and the resolution
//  composites its field first and the content over it
//  (`OpacityRegion.fieldUnderContent`, `Opacity as composition.md` §105).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension FrameBuffer {

    /// `claims` — a painter's own claims on the translucent field it painted under
    /// this buffer, its content, in the content's own coordinates — said of that
    /// field alone: ``FieldUnderContent/shown`` over the cells whose field the content
    /// leaves to the painter, and ``FieldUnderContent/beneath(_:)`` with the painter's
    /// colour where the content states a field of its own over it.
    ///
    /// Each claim keeps its alphas and its cycle; only its extent is cut, into
    /// rectangles of one kind, and rows cut alike are one rectangle again. Content that
    /// states no field of its own anywhere under a claim — nearly all of it — gets the
    /// claim back whole, marked shown.
    ///
    /// A painter that COMPOSITES its content over its fill rather than restating its
    /// colour after resets — a `.listRowBackground` — fills a stated `ESC[49m` in the
    /// content as it fills a cell that says nothing, so there a 49 leaves the field to
    /// it (`fillingStatedTerminalField`,
    /// ``String/columnsLeavingFieldToPainter(width:fillingStatedTerminalField:)``).
    ///
    /// - Parameters:
    ///   - claims: The painter's claims on its field, as it has always made them.
    ///   - fillingStatedTerminalField: Whether the painter fills a stated 49 in its
    ///     content, as a compositor does.
    ///   - fill: The background escape the painter painted at a cell of the content,
    ///     `(row, column)`: asked only under a field the content states itself.
    /// - Returns: The claims, told apart.
    func claimingPainterField(
        _ claims: [OpacityRegion], fillingStatedTerminalField: Bool = false,
        spelledAt fill: (_ row: Int, _ column: Int) -> String
    ) -> [OpacityRegion] {
        guard !claims.isEmpty else { return [] }
        let reach = claims.map { $0.offsetX + $0.width }.max() ?? 0
        // Which cells leave their field to the painter, one row at a time, read once
        // whichever claims cover the row. A row past the content's last is padding.
        var masks = [[Bool]?](repeating: nil, count: lines.count)
        func mask(_ row: Int) -> [Bool]? {
            guard lines.indices.contains(row) else { return nil }
            if let known = masks[row] { return known }
            let read = lines[row].columnsLeavingFieldToPainter(
                width: reach, fillingStatedTerminalField: fillingStatedTerminalField)
            masks[row] = read
            return read
        }
        func leavesAll(_ claim: OpacityRegion) -> Bool {
            (claim.offsetY..<(claim.offsetY + claim.height)).allSatisfy { row in
                guard let mask = mask(row) else { return true }
                return mask[max(0, claim.offsetX)..<(claim.offsetX + claim.width)].allSatisfy { $0 }
            }
        }
        var told: [OpacityRegion] = []
        for claim in claims {
            guard !leavesAll(claim) else {
                var shown = claim
                shown.fieldUnderContent = .shown
                told.append(shown)
                continue
            }
            told += cut(claim, mask: mask, fill: fill)
        }
        return told
    }

    /// ``claimingPainterField(_:fillingStatedTerminalField:spelledAt:)`` for a painter of
    /// one colour, spelled `escape` under every cell — asked only under a field the
    /// content states.
    func claimingPainterField(
        _ claims: [OpacityRegion], fillingStatedTerminalField: Bool = false,
        spelled escape: @autoclosure () -> String
    ) -> [OpacityRegion] {
        var spelled: String?
        return claimingPainterField(claims, fillingStatedTerminalField: fillingStatedTerminalField) { _, _ in
            if let spelled { return spelled }
            let made = escape()
            spelled = made
            return made
        }
    }

    /// `claim` cut into rectangles of one kind each, row by row, and rows cut alike
    /// joined again.
    private func cut(
        _ claim: OpacityRegion, mask: (Int) -> [Bool]?, fill: (Int, Int) -> String
    ) -> [OpacityRegion] {
        var pieces: [OpacityRegion] = []
        // The pieces the row above ended with, by extent and kind: a piece this row
        // repeats extends one of them instead of starting a rectangle of its own.
        var open: [PieceKey: Int] = [:]
        let left = max(0, claim.offsetX)
        let right = claim.offsetX + claim.width
        for row in claim.offsetY..<(claim.offsetY + claim.height) {
            let shows = mask(row)
            var extended: [PieceKey: Int] = [:]
            var column = left
            while column < right {
                let start = column
                let kind: FieldUnderContent
                if shows?[column] ?? true {
                    kind = .shown
                    while column < right, shows?[column] ?? true { column += 1 }
                } else {
                    let escape = fill(row, column)
                    kind = .beneath(escape)
                    while column < right, !(shows?[column] ?? true), fill(row, column) == escape { column += 1 }
                }
                let key = PieceKey(offsetX: start, width: column - start, kind: kind)
                if let index = open[key] {
                    pieces[index].height += 1
                    extended[key] = index
                } else {
                    var piece = claim
                    piece.offsetX = start
                    piece.offsetY = row
                    piece.width = column - start
                    piece.height = 1
                    piece.fieldUnderContent = kind
                    extended[key] = pieces.count
                    pieces.append(piece)
                }
            }
            open = extended
        }
        return pieces
    }

    /// A piece's extent across a row and what it is about.
    private struct PieceKey: Hashable {
        let offsetX: Int
        let width: Int
        let kind: FieldUnderContent
    }
}
