//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FrameBuffer+ClaimsUnderALayer.swift
//
//  A compositor inside the tree carries up the claims of a layer that lands on
//  nothing (`FrameBuffer+ClaimsOverNothing.swift`), so the canvas it folds its
//  layers into holds them: a translucent colour at the bottom of a `ZStack` is
//  its opaque spelling in the canvas, with its claim over it. A later layer laid
//  over those cells replaces them, and the composite punches every claim under
//  its footprint (`FrameBuffer.opacityRegionsPunched`). Punched, the claim went
//  and its field stayed: a label over `Color.blue.opacity(0.5)` in a `ZStack`
//  was drawn on the blue at full strength in a row of the blue at one half. And
//  a faded layer laid there was blended over the earlier one unfaded. So a base
//  settles its claims under a layer before the layer lands on it
//  (`Opacity as composition.md` §108.1).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension FrameBuffer {

    /// This buffer — a base about to have `layer` composited onto it at `position` —
    /// with its own claims under the layer's cells settled, the claims it keeps there,
    /// which the composite punches with the rest of the layer's footprint and the
    /// caller puts back, and the layer less the claims of its own that go up with them.
    ///
    /// Under a cell of the layer, read as the composite reads it — a cell that names no
    /// colour in its background slot, a stated `ESC[49m` included, takes the base's
    /// field there (`String.paintedOver(background:)`):
    /// - where the layer's cell leaves its field to the base's and fades nothing on
    ///   what is behind it, it shows the base's field under the layer's own glyph, and
    ///   the base's claims there are kept, about that field alone
    ///   (``FieldUnderContent/shown``): the content's claims on its field folded into
    ///   one, as the resolution folds them (the layer from the first, the fields'
    ///   alphas multiplied), and a painter's on its field as they are. So a label over
    ///   a translucent colour is on the colour as it shows beside the label, wherever
    ///   that is resolved, a painter's fill further out included. A claim of the
    ///   layer's own there that scales only its INK goes up with them: it is paint on
    ///   the field the cell ends up with, which is not known here.
    /// - where the layer's drawn cell states a field of its own but a run of the layer
    ///   has frames that leave it to the base, the base's claims are kept BENEATH that
    ///   field (``FieldUnderContent/beneath(_:)``, in the base's colour), so each frame
    ///   takes the field it shows as the blend reads a run's frames (§105).
    /// - where the layer FADES, it is blended over the base's cell here, and that cell
    ///   is not what shows until its own claims are spent: they are spent first, over
    ///   nothing but what is known here (the surface, left unsaid where the blend
    ///   leaves no field), as a compositor spent every layer before it carried any.
    ///   Two translucent layers in one cell cannot both travel in one line.
    /// - where the layer's cell is reversed with nothing named in its background slot,
    ///   the composite fills that slot with the base's field, which the reversal shows
    ///   as the glyph's INK, and a claim on a field cannot reach an ink: spent first
    ///   too.
    /// - where the base's cell is reversed on the terminal's own ink, which no
    ///   background code spells, or under a run stating its alpha frame by frame, spent
    ///   first too: a layer laid on the terminal's own foreground is drawn reversed
    ///   itself, which a claim on the field it shows cannot reach; and a run's alpha is
    ///   in no claim to keep. A reversal of any other ink shows that ink as a field the
    ///   composite spells, and its claims are kept like any other.
    /// - where the layer's cell hides the base's field, or the base shows none, the
    ///   claims go with the cell, as they always did.
    ///
    /// A base with no claim under the layer — nearly every one — comes back as it is.
    ///
    /// - Parameters:
    ///   - layer: What is about to land: its cells, and the claims it keeps to be
    ///     resolved against this buffer (``splittingClaims(overNothingIn:at:)``'s
    ///     `here`).
    ///   - position: Where it lands, in this buffer's cells.
    ///   - palette: Resolves the surface and SGR 39 for a claim spent first.
    /// - Returns: This buffer, its claims under the layer's fades spent; the claims it
    ///   keeps under the layer's cells, each about the field alone; and the layer, less
    ///   the claims of its own that go up with those (`carried`, in its coordinates).
    func settlingClaims(
        under layer: Self, at position: (x: Int, y: Int), palette: any Palette
    ) -> (base: Self, kept: [OpacityRegion], layer: Self, carried: [OpacityRegion]) {
        guard !opacityRegions.isEmpty || animatedCells.contains(where: { $0.alpha?.isTranslucent == true }),
            var settling = ClaimsUnderALayer(base: self, layer: layer, at: position)
        else { return (self, [], layer, []) }
        let (spentFirst, kept) = settling.sortedClaims()
        let spentRuns = settling.spentRuns()
        let (layer, carried) = settling.layerClaimsGoingUp(with: kept)
        guard !spentFirst.isEmpty || !spentRuns.isEmpty else { return (self, kept, layer, carried) }
        var spending = self
        spending.opacityRegions = spentFirst
        spending.animatedCells = spentRuns
        let spent = spending.resolvingOpacity(
            over: Self(), at: (x: 0, y: 0), surface: palette.background, palette: palette, statingTheSurface: false,
            fillingStatedTerminalField: false, buildingRuns: false)
        // The same cells, re-spelled: every line keeps its width.
        let base = replacingLines(spent.lines, width: width, uniformWidth: linesAreUniformWidth, lineWidths: lineWidths)
        return (base, kept, layer, carried)
    }

    /// How many of a base's cells ``settlingClaims(under:at:palette:)`` asked the fate
    /// of, for a test that bounds that by the cells the layer covers
    /// (`CompositorOverNothingTests`); `nil`, and nothing counted, everywhere else.
    @TaskLocal package static var settleWork: SettleWork?

    /// A count ``settleWork`` accumulates into, read by the one task that binds it.
    package final class SettleWork: @unchecked Sendable {
        /// Cells asked about, summed over every settle while bound.
        package var cellsAsked = 0

        package init() {}
    }
}

/// A base's claims under the cells of a layer about to land on it, and what becomes
/// of each (``FrameBuffer/settlingClaims(under:at:palette:)``).
private struct ClaimsUnderALayer {

    /// What becomes of the base's claims under one of the layer's cells.
    enum Fate {
        /// The layer's cell hides what the base shows there, or the base shows no
        /// field there: the claims go with the cell, as the composite punches them.
        case punched
        /// The layer fades there, and is blended over the base's cell, or the cell
        /// shows the base's field as something no claim on a field can reach: the
        /// base's claims are spent first.
        case spentFirst
        /// The layer's cell leaves its field to the base's and fades nothing: the
        /// claims are kept, about that field alone.
        case fieldAlone
        /// The layer's drawn cell states a field of its own, and a run of the layer
        /// has frames that leave it to the base's: the claims are kept beneath it.
        case beneathField
    }

    /// What becomes of one of the base's claims under one of the layer's cells.
    private enum ClaimFate: Hashable {
        /// Not under the layer: the composite leaves it as it is.
        case outside
        case punched
        case spentFirst
        /// A painter's claim on its field (`OpacityRegion.fieldUnderContent`), under
        /// a cell showing that field: already about the field alone.
        case kept
        /// A painter's claim on the field the base's cell shows, under a layer cell
        /// whose drawn frame states its own over it: beneath that, in `escape`.
        case painterBeneath(escape: String)
        /// The first of the content's own claims on the field the cell shows, which
        /// all of them together let `fieldOpacity` of through.
        case shown(fieldOpacity: Double)
        /// The first of the content's own claims on the base's field, under a layer
        /// cell whose drawn frame states its own over it: beneath that, in `escape`.
        case beneath(fieldOpacity: Double, escape: String)
    }

    /// Under a cell whose field is kept: which claim is the first of the content's
    /// own, what all of the content's let through of the field, and whether the field
    /// the cell shows is a painter's — under which the content's claims were about a
    /// glyph the layer has replaced.
    private struct ContentClaims {
        var first: Int?
        var field = 1.0
        var painterShown = false
    }

    let base: FrameBuffer
    let layer: FrameBuffer
    let position: (x: Int, y: Int)
    /// The cells the layer replaces, row by row, in the base's coordinates.
    let footprint: [Int: Range<Int>]
    /// The rows and columns `footprint` spans, which bound every cell asked about.
    let bounds: (rows: Range<Int>, columns: Range<Int>)
    /// The base's claims under the layer, by index.
    let claims: [Int]
    /// The base's runs stating their alpha frame by frame, under the layer.
    let spoken: [AnimatedCellRun]
    /// Each footprint row's fates, read the first time a cell of it is asked about.
    private var fates: [Int: [Fate]] = [:]
    /// The escape stating the base's field under each column of a row, read the first
    /// time a claim there is kept beneath a field.
    private var escapes: [Int: [String]] = [:]

    /// The base's claims and spoken runs under `layer`'s cells, or `nil` where none is.
    init?(base: FrameBuffer, layer: FrameBuffer, at position: (x: Int, y: Int)) {
        // Inside the layer's bounding box first, which its width already knows: a base
        // whose claims all lie beside the layer — a `Layout` folding subviews that do
        // not overlap, each carrying a fade up past the ones before it — is answered
        // without measuring a line of the layer, once per subview.
        let rows = position.y..<(position.y + layer.lines.count)
        let columns = position.x..<(position.x + layer.width)
        guard
            base.opacityRegions.contains(where: {
                rows.overlaps($0.offsetY..<($0.offsetY + $0.height))
                    && columns.overlaps($0.offsetX..<($0.offsetX + $0.width))
            })
                || base.animatedCells.contains(where: {
                    $0.alpha?.isTranslucent == true && rows.contains($0.offsetY)
                        && columns.overlaps($0.offsetX..<($0.offsetX + $0.width))
                })
        else { return nil }
        var footprint: [Int: Range<Int>] = [:]
        var covered: (rows: Range<Int>, right: Int)?
        for (index, line) in layer.lines.enumerated() {
            let visible = line.strippedLength
            guard visible > 0 else { continue }
            let row = position.y + index
            footprint[row] = position.x..<(position.x + visible)
            covered = (
                (covered?.rows.lowerBound ?? row)..<(row + 1), max(covered?.right ?? 0, position.x + visible)
            )
        }
        guard let covered else { return nil }
        let bounds = (rows: covered.rows, columns: position.x..<covered.right)
        func meets(_ rows: Range<Int>, _ columns: Range<Int>) -> Bool {
            rows.clamped(to: bounds.rows).contains { footprint[$0]?.overlaps(columns) == true }
        }
        claims = base.opacityRegions.indices.filter { index in
            let claim = base.opacityRegions[index]
            return meets(claim.offsetY..<(claim.offsetY + claim.height), claim.offsetX..<(claim.offsetX + claim.width))
        }
        spoken = base.animatedCells.filter {
            $0.alpha?.isTranslucent == true && meets($0.offsetY..<($0.offsetY + 1), $0.offsetX..<($0.offsetX + $0.width))
        }
        guard !claims.isEmpty || !spoken.isEmpty else { return nil }
        (self.base, self.layer, self.position, self.footprint, self.bounds) = (base, layer, position, footprint, bounds)
    }

    /// The base's claims under the layer that are spent first, and the ones kept —
    /// each about the field alone, the content's folded claim ahead of the painters'
    /// under it, the order the resolution reads fields in (topmost first).
    ///
    /// Each claim is cut only where it meets the footprint's bounds: every cell outside
    /// them is under no cell of the layer, and the composite leaves it as it is. Cut
    /// whole, a translucent backdrop filling a `Layout`'s 80 × 24 canvas was asked about
    /// every cell of the piece each subview landed in: 27,780 cells for a hundred
    /// one-cell labels, where they cover 100.
    mutating func sortedClaims() -> (spentFirst: [OpacityRegion], kept: [OpacityRegion]) {
        var spentFirst: [OpacityRegion] = []
        var content: [OpacityRegion] = []
        var painters: [OpacityRegion] = []
        var asked = 0
        defer { FrameBuffer.settleWork?.cellsAsked += asked }
        for index in claims {
            guard
                let claim = base.opacityRegions[index].clipped(toColumns: bounds.columns, rows: bounds.rows)
            else { continue }
            let pieces = FrameBuffer.cutting(claim) { row, column in
                asked += 1
                return fate(of: index, row, column)
            }
            for (piece, kind) in pieces {
                switch kind {
                case .outside, .punched: break
                case .spentFirst: spentFirst.append(piece)
                case .kept: painters.append(piece)
                case .painterBeneath(let escape):
                    var beneath = piece
                    beneath.fieldUnderContent = .beneath(escape)
                    painters.append(beneath)
                case .shown(let field):
                    if let alone = Self.aboutTheField(piece, .shown, fieldOpacity: field) { content.append(alone) }
                case .beneath(let field, let escape):
                    if let alone = Self.aboutTheField(piece, .beneath(escape), fieldOpacity: field) {
                        content.append(alone)
                    }
                }
            }
        }
        return (spentFirst, content + painters)
    }

    /// `piece` — the first of the content's claims over its cells — as the one claim
    /// all of them make on the field there, in `place`, letting `fieldOpacity` of it
    /// through; `nil` at full strength, where the field is the identity and the claim
    /// says nothing.
    private static func aboutTheField(
        _ piece: OpacityRegion, _ place: FieldUnderContent, fieldOpacity: Double
    ) -> OpacityRegion? {
        var alone = piece
        alone.fieldUnderContent = place
        alone.fieldOpacity = fieldOpacity
        alone.inkOpacity = 1
        return alone.isTranslucent || alone.cycle != nil ? alone : nil
    }

    /// The pieces of the base's spoken runs under cells spent first, whose drawn
    /// frame's alpha the lines take there.
    mutating func spentRuns() -> [AnimatedCellRun] {
        var pieces: [AnimatedCellRun] = []
        for run in spoken {
            let end = run.offsetX + run.width
            var column = run.offsetX
            while column < end {
                guard case .spentFirst = fate(run.offsetY, column) else {
                    column += 1
                    continue
                }
                let start = column
                while column < end, case .spentFirst = fate(run.offsetY, column) { column += 1 }
                if let piece = run.clipped(toColumns: start..<column) { pieces.append(piece) }
            }
        }
        return pieces
    }

    /// The layer, less its claims that scale only its INK over cells where the base's
    /// claims are `kept`; those go up with the kept ones, in the layer's coordinates.
    ///
    /// Such a claim is paint on the field its cell ends up with, and under a kept
    /// claim that is not the base's opaque spelling this buffer holds but the field the
    /// kept claim resolves to further out. Resolved here, a label in a translucent ink
    /// over `Color.blue.opacity(0.5)` had its ink mixed toward the blue at full
    /// strength.
    func layerClaimsGoingUp(with kept: [OpacityRegion]) -> (layer: FrameBuffer, carried: [OpacityRegion]) {
        guard !kept.isEmpty, layer.opacityRegions.contains(where: Self.scalesOnlyInk) else { return (layer, []) }
        var here: [OpacityRegion] = []
        var carried: [OpacityRegion] = []
        for claim in layer.opacityRegions {
            guard Self.scalesOnlyInk(claim) else {
                here.append(claim)
                continue
            }
            let pieces = FrameBuffer.cutting(claim) { row, column in
                let (baseRow, baseColumn) = (row + position.y, column + position.x)
                return kept.contains { $0.contains(column: baseColumn, row: baseRow) }
            }
            for (piece, underKept) in pieces {
                if underKept { carried.append(piece) } else { here.append(piece) }
            }
        }
        guard !carried.isEmpty else { return (layer, []) }
        var remaining = layer
        remaining.opacityRegions = here
        return (remaining, carried)
    }

    /// Whether `claim` is the content's own and scales only its ink: no fade on what
    /// is behind it (``FrameBuffer/fadesOnWhatIsBehind(_:runAlphas:)``).
    private static func scalesOnlyInk(_ claim: OpacityRegion) -> Bool {
        claim.fieldUnderContent == nil && claim.inkOpacity < 1 && claim.opacity >= 1 && claim.fieldOpacity >= 1
            && claim.cycle == nil
    }

    /// What becomes of claim `index` under the base's cell `(row, column)`.
    private mutating func fate(of index: Int, _ row: Int, _ column: Int) -> ClaimFate {
        guard let fate = fate(row, column) else { return .outside }
        let place = base.opacityRegions[index].fieldUnderContent
        switch fate {
        case .punched: return .punched
        case .spentFirst: return .spentFirst
        case .fieldAlone:
            guard place == nil else { return .kept }
            let content = contentClaims(row, column)
            guard !content.painterShown, content.first == index else { return .punched }
            return .shown(fieldOpacity: content.field)
        case .beneathField:
            switch place {
            case .shown: return .painterBeneath(escape: baseEscape(row, column))
            case .beneath: return .kept
            case nil:
                let content = contentClaims(row, column)
                guard !content.painterShown, content.first == index else { return .punched }
                return .beneath(fieldOpacity: content.field, escape: baseEscape(row, column))
            }
        }
    }

    /// The escape stating the base's field under its cell `(row, column)`.
    private mutating func baseEscape(_ row: Int, _ column: Int) -> String {
        let read: [String]
        if let known = escapes[row] {
            read = known
        } else {
            let line = base.lines.indices.contains(row) ? base.lines[row] : ""
            read = line.columnsBackgroundEscapes(width: max(0, footprint[row]?.upperBound ?? 0))
            escapes[row] = read
        }
        return read.indices.contains(column) ? read[column] : ""
    }

    /// What becomes of the base's claims under its cell `(row, column)`, or `nil` for
    /// a cell the layer does not cover.
    private mutating func fate(_ row: Int, _ column: Int) -> Fate? {
        guard let span = footprint[row], span.contains(column) else { return nil }
        if let known = fates[row] { return known[column - span.lowerBound] }
        let read = fates(onRow: row, span: span)
        fates[row] = read
        return read[column - span.lowerBound]
    }

    /// What becomes of the base's claims under each of `span`, the columns the layer
    /// covers on `row`.
    private func fates(onRow row: Int, span: Range<Int>) -> [Fate] {
        let layerRow = row - position.y
        let layerLine = layer.lines[layerRow]
        // As the composite reads the layer's cells: a stated 49 is filled as none.
        let layerLeaves = layerLine.columnsLeavingFieldToPainter(width: span.count, fillingStatedTerminalField: true)
        let layerInkLeft = layerLine.columnsReversedOverNoNamedField(width: span.count)
        let reach = max(0, span.upperBound)
        let line = base.lines.indices.contains(row) ? base.lines[row] : ""
        let baseLeaves = line.columnsLeavingFieldToPainter(width: reach)
        let baseReversed = line.columnsReversingVideo(width: reach)
        // A reversal of the terminal's own ink has no spelling as a field until the
        // terminal reports that ink, and the composite draws a cell laid on it
        // reversed itself.
        let baseUnspelled =
            FrameBuffer.reportedTerminalForegroundField == nil
            ? line.columnsShowingTerminalInkAsField(width: reach) : nil
        let framesLeave = layerRunsLeavingTheField(onRow: layerRow, width: span.count)
        return span.map { column in
            let layerColumn = column - position.x
            if layerFades(at: layerColumn, layerRow) { return .spentFirst }
            guard column >= 0, !baseLeaves[column] else { return .punched }
            let showsField = layerLeaves[layerColumn]
            let showsFieldInAFrame = !showsField && framesLeave?[layerColumn] == true
            guard showsField || showsFieldInAFrame || layerInkLeft[layerColumn] else { return .punched }
            let underASpokenRun = spoken.contains {
                $0.offsetY == row && ($0.offsetX..<($0.offsetX + $0.width)).contains(column)
            }
            if underASpokenRun || layerInkLeft[layerColumn] || baseUnspelled?[column] == true { return .spentFirst }
            // Beneath a field a frame states, in the base's colour: a reversal's field
            // is its ink, in the other slot, and has no escape of its own there.
            if showsFieldInAFrame { return baseReversed[column] ? .spentFirst : .beneathField }
            return .fieldAlone
        }
    }

    /// For each of `width` columns of the layer's row `row`, whether a frame of one of
    /// the layer's runs there leaves the cell's field to the base, as the composite
    /// reads it; `nil` for a row no run of the layer sits on.
    private func layerRunsLeavingTheField(onRow row: Int, width: Int) -> [Bool]? {
        let runs = layer.animatedCells.filter { $0.offsetY == row && $0.width > 0 && $0.offsetX < width }
        guard !runs.isEmpty else { return nil }
        var leaves = [Bool](repeating: false, count: max(0, width))
        for run in runs {
            for frame in run.frames {
                let read = frame.columnsLeavingFieldToPainter(width: run.width, fillingStatedTerminalField: true)
                for (cell, left) in read.enumerated() where left {
                    let column = run.offsetX + cell
                    if leaves.indices.contains(column) { leaves[column] = true }
                }
            }
        }
        return leaves
    }

    /// Whether the layer fades its cell `(column, row)` on what is behind it: a claim
    /// of its own there with a layer or field alpha, or cycling, or a run stating its
    /// alpha there. A claim on the INK alone is not one: it is paint on the cell's own
    /// field, contests no glyph, and blends nothing over the base's cell
    /// (``FrameBuffer/hasFadeOnWhatIsBehind``). Taken for one, the base's claims under
    /// a label in a translucent ink were spent over the page, and inside a painter the
    /// label sat on a patch of the colour mixed toward the page, beside the colour
    /// mixed toward the painter.
    private func layerFades(at column: Int, _ row: Int) -> Bool {
        layer.opacityRegions.contains {
            ($0.opacity < 1 || $0.fieldOpacity < 1 || $0.cycle != nil) && $0.contains(column: column, row: row)
        }
            || layer.animatedCells.contains {
                $0.alpha?.isTranslucent == true && $0.offsetY == row
                    && ($0.offsetX..<($0.offsetX + $0.width)).contains(column)
            }
    }

    /// The base's claims on the field under its cell `(row, column)`.
    private func contentClaims(_ row: Int, _ column: Int) -> ContentClaims {
        var read = ContentClaims()
        for index in claims where base.opacityRegions[index].contains(column: column, row: row) {
            let claim = base.opacityRegions[index]
            switch claim.fieldUnderContent {
            case nil:
                if read.first == nil { read.first = index }
                read.field *= claim.fieldOpacity
            case .shown: read.painterShown = true
            case .beneath: break
            }
        }
        return read
    }
}
