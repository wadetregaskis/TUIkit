//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FieldsUnderOverlay.swift
//
//  What a line has under each column an overlay covers, and the overlay painted
//  over it.
//
//  A cell has a glyph and a field, and an overlay cell that states no field of its
//  own keeps the field it lands on: `ZStack { Color.red; Text("hi") }` draws the
//  letters ON the red (590e71a4). The field it lands on is the one under THAT cell.
//  Compositing read one field for a whole overlay row — the base's under the
//  overlay's first column — and painted it under every cell, so
//  `ZStack(alignment: .leading)` over three red cells and three blue ones, with
//  `Text("abcdef")` on top, drew all six letters on red.
//
//  The split already walks the base up to the overlay's end and nets every escape
//  on the way (`String.ansiOverlaySplit(prefixColumns:suffixDropColumns:)`), so it
//  notes where the field changes inside the covered span for no more than a
//  comparison per escape there. A base that carries one field across the span —
//  nearly every one — has no change to note, and the overlay is painted exactly as
//  it was, in the same bytes.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - The fields

/// The field a base line shows under each column an overlay covers: the one under
/// its first column, and every column inside the span where it changes.
///
/// A field is `nil` where the line states none there — after a reset, where the
/// row builder puts the page back (`FrameDiffWriter.buildLine`) — and
/// ``SGRState/Colour/statedTerminalField`` where it states `ESC[49m`, the
/// terminal's own: in a row still to be written those are two fields, and on a
/// page with an RGB two colours. (Netted as one `nil`, as `SGRState` nets them, an
/// overlay over a stated 49 was drawn on the page.)
struct FieldsUnderOverlay: Sendable, Equatable {
    /// Where the field changes: from base column `column` on, `field`.
    struct Change: Sendable, Equatable {
        let column: Int
        let field: SGRState.Colour?
    }

    /// The base column the overlay's first cell lands on.
    let column: Int
    /// The field under that cell.
    let first: SGRState.Colour?
    /// Every change of field inside the covered span, one per column at most, in
    /// ascending order. Empty where one field is under the whole span.
    let changes: [Change]

    /// No field anywhere: what an overlay row that was never inserted lands on.
    static let none = Self(column: 0, first: nil, changes: [])

    /// Whether one field is under every column the overlay covers.
    var isUniform: Bool { changes.isEmpty }

    /// The escape that puts ``first`` in force, `""` for none: what the one field
    /// under a uniform span is painted with.
    var firstEscape: String { first.map { SGRState.backgroundEscape($0) } ?? "" }

    /// The field under each column of `columns`, base columns: ``first`` before the
    /// span, and the last one in force past it.
    func fields(over columns: Range<Int>) -> [SGRState.Colour?] {
        var fields: [SGRState.Colour?] = []
        fields.reserveCapacity(columns.count)
        var field = first
        var next = changes.startIndex
        for column in columns {
            while next < changes.endIndex, changes[next].column <= column {
                field = changes[next].field
                next += 1
            }
            fields.append(field)
        }
        return fields
    }
}

// MARK: - Noting them in the split's one scan

extension FieldsUnderOverlay {
    /// The changes of field inside a covered span, noted as the split's scan
    /// reaches each escape there.
    struct Recorder {
        private(set) var changes: [Change] = []

        /// Notes that from base column `column` on the field is `field`, given the
        /// field under the span's first column. Two escapes at one column — a reset
        /// and a colour restated after it — are one change, or none where they net
        /// to the field already in force.
        mutating func note(_ field: SGRState.Colour?, at column: Int, first: SGRState.Colour?) {
            if changes.last?.column == column { changes.removeLast() }
            let current = changes.isEmpty ? first : changes[changes.count - 1].field
            guard field != current else { return }
            changes.append(Change(column: column, field: field))
        }
    }
}

// MARK: - Painting an overlay over them

extension String {
    /// This overlay line — `width` cells from base column `column` — with every cell
    /// that states no field of its own, or states `ESC[49m`, drawn over the field
    /// under that cell's column: what compositing does to an overlay, cell by cell.
    ///
    /// Where one field is under the whole span, exactly ``paintedOver(background:)``
    /// with it, in the same bytes; see ``paintedOver(fieldsUnder:)`` for the rest.
    ///
    /// - Parameters:
    ///   - fields: What the base has under the overlay.
    ///   - column: The base column this line's first cell lands on.
    ///   - width: How many cells the line covers.
    /// - Returns: The line, painted.
    func paintedOver(_ fields: FieldsUnderOverlay, atColumn column: Int, width: Int) -> String {
        guard !fields.isUniform else { return paintedOver(background: fields.firstEscape) }
        // A line that names a colour of its own under every cell takes no field from
        // the base, whatever is under it — text over a ramp, over two painters, over a
        // reversed segment, where the fields change and every cell was painted
        // already. Asked in one walk that builds nothing, before a cell-by-cell
        // rebuild whose every restatement would come out empty.
        guard !namesAColourUnderEveryCell else { return self }
        return paintedOver(fieldsUnder: fields.fields(over: column..<(column + width)))
    }

    /// Whether every visible cell of this line has a colour of its own in the
    /// background slot — nothing unsaid there, and no `ESC[49m`, which compositing
    /// fills as it fills none.
    private var namesAColourUnderEveryCell: Bool {
        var state = SGRState()
        return forEachANSISegment { segment in
            switch segment {
            case .ansi(let sequence, let isSGR):
                if isSGR { state.apply(sequence) }
                return true
            case .visible(let character):
                // A zero-width scalar belongs to the cell before it.
                return character.terminalWidth == 0 || state.namesBackground
            }
        }
    }

    /// This overlay line with every cell that states no field of its own, or states
    /// `ESC[49m`, drawn over `under[k]` at its column `k` — as compositing reads a
    /// cell, one field per column.
    ///
    /// Where every entry is one field, exactly ``paintedOver(background:)`` with it.
    /// Otherwise each field is put in force before the first cell that needs it
    /// (``paintedOver(fields:absentFieldIsUnstated:)``), and a column with no field
    /// under it goes back to none: a reset, after which the row builder puts the
    /// page back, with the line's own styling restated behind it. A stated 49 over
    /// no field stays the terminal's own, as it did under one field.
    ///
    /// - Parameter under: The field under each of the line's columns, `nil` for none.
    /// - Returns: The line, painted.
    func paintedOver(fieldsUnder under: [SGRState.Colour?]) -> String {
        guard let first = under.first else { return self }
        guard under.contains(where: { $0 != first }) else {
            return paintedOver(background: first.map { SGRState.backgroundEscape($0) } ?? "")
        }
        return paintedOver(
            fields: AnimatedCellRun.GroundFields(bare: under, underStatedDefault: under),
            absentFieldIsUnstated: true)
    }
}

extension AnimatedCellRun {
    /// This run's records painted as compositing paints the overlay row it sits on,
    /// its first cell at base column `column`: each of its cells records the field
    /// under its own column (``String/paintedOver(fieldsUnder:)``).
    ///
    /// A run under no field at all is left unpainted, as it was when one field was
    /// read for the whole row and that one was none.
    func paintingGround(over fields: FieldsUnderOverlay, atColumn column: Int) -> Self {
        if fields.isUniform {
            guard fields.first != nil else { return self }
            let escape = fields.firstEscape
            return paintingGround { $0.paintedOver(background: escape) }
        }
        let under = fields.fields(over: column..<(column + width))
        guard under.contains(where: { $0 != nil }) else { return self }
        return paintingGround { $0.paintedOver(fieldsUnder: under) }
    }
}
