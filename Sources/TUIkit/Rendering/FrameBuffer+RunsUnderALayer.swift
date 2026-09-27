//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FrameBuffer+RunsUnderALayer.swift
//
//  A layer composited over a run of its base — a `ZStack`'s later child, an
//  `.overlay`, a `Layout`'s later subview — punches the run under its footprint
//  (`FrameBuffer.animatedCellsPunched`): the layer's cells replace the base's, and a
//  run replaying there would paint over them. But a layer's cell that names no field
//  shows the base's, which the composite fills in from the frame the render drew. A
//  run whose frames disagree about that field left the cell on the drawn frame's
//  field at every tick: a label over a breathing fill froze on the colour it was
//  drawn over. The layer's cell and the run's frame are two things one cell shows,
//  and a run carries one; so the compositor asks for a render at each of the run's
//  steps, which draws the cell as it is then, the way a breathing `List` row does
//  for the runs it drops (`Opacity as composition.md` §109).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension FrameBuffer {

    /// The runs of this buffer — a base about to have `layer` composited onto it at
    /// `position` — whose frames disagree about the field of a cell the layer covers
    /// and fills with the base's field (`String.columnsTakingBaseField(width:)`): in
    /// the line it draws, or in a frame of one of its own runs.
    ///
    /// A run whose frames change only their glyphs there, or state no field, shows
    /// the layer's cell on one field at every step, and is not one: a spinner under a
    /// label asks for nothing. Nearly every base has no run under a layer, and is
    /// answered from the runs' rows and columns alone.
    ///
    /// Read from the raw layer, which is right for a cell that does not fade. A
    /// layer that fades over the run, or names a translucent field there, is
    /// resolved over the run's drawn frame and loses its glyph to it, or mixes its
    /// ink and field toward it; the composite punches the run all the same, and this
    /// does not ask for it, so the cell holds the drawn frame between renders — a
    /// known gap (`Opacity as composition.md` §109).
    ///
    /// - Parameters:
    ///   - layer: What is about to land.
    ///   - position: Where it lands, in this buffer's cells.
    /// - Returns: The runs to ask a render at each step of.
    func runsShowingThrough(_ layer: Self, at position: (x: Int, y: Int)) -> [AnimatedCellRun] {
        guard !animatedCells.isEmpty, !layer.lines.isEmpty else { return [] }
        let rows = position.y..<(position.y + layer.lines.count)
        let columns = position.x..<(position.x + layer.width)
        var showing: [AnimatedCellRun] = []
        // What the layer fills with the base's field, per row of the layer, read once.
        var filled: [Int: [Bool]] = [:]
        // Where the run is first, whether it animates after: `isAnimating` compares
        // the frames' bytes, and a `ZStack` or a `Layout` asks this of every run
        // already on its canvas at every later layer.
        for run in animatedCells where rows.contains(run.offsetY) {
            let span = run.offsetX..<(run.offsetX + run.width)
            guard span.overlaps(columns), run.isAnimating else { continue }
            let layerRow = run.offsetY - position.y
            let mask: [Bool]
            if let known = filled[layerRow] {
                mask = known
            } else {
                mask = layer.columnsTakingBaseField(onRow: layerRow)
                filled[layerRow] = mask
            }
            let under = span.clamped(to: columns).filter { mask[$0 - position.x] }
            guard !under.isEmpty else { continue }
            let fields = run.frames.map { $0.columnsFieldShown(width: run.width) }
            let disagree = under.contains { column in
                let cell = column - run.offsetX
                return fields.contains { $0[cell] != fields[0][cell] }
            }
            if disagree { showing.append(run) }
        }
        return showing
    }

    /// For each column of this buffer's line `row`, whether a compositor laying it on
    /// a base fills that cell with the base's field — in the line, or in any frame of
    /// a run of this buffer's on that row.
    private func columnsTakingBaseField(onRow row: Int) -> [Bool] {
        var mask = lines[row].columnsTakingBaseField(width: width)
        for run in animatedCells where run.offsetY == row {
            for frame in run.frames {
                for (cell, taken) in frame.columnsTakingBaseField(width: run.width).enumerated() where taken {
                    let column = run.offsetX + cell
                    if mask.indices.contains(column) { mask[column] = true }
                }
            }
        }
        return mask
    }
}
