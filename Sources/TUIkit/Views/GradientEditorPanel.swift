//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GradientEditorPanel.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitStyling

// MARK: - Gradient Editor Panel

/// A modal gradient editor — ``ColorPickerPanel``'s sibling for the
/// ``Gradient``s TUIkit paints with (``TrackConfiguration``'s `fillGradient`,
/// `.threeSegment`'s ``SegmentColoring/gradient(_:)``, the indeterminate
/// `IndeterminateStyle.gradient(_:)` sweep, and anything given to
/// ``View/foregroundStyle(_:)-(S)``).
///
/// A gradient is colours at positions, interpolated piecewise; the editor
/// shows that exact interpolation live in its preview strip, positions
/// included. Below it, the stop strip selects a stop (click
/// its swatch) and reorders them (drag a swatch — the stop moves through the
/// strip live, following the cursor), the action row
/// inserts / removes / reorders stops, preset and
/// recently-applied gradients offer one-click starting points, and an embedded
/// colour panel — the same preview-plus-tabs body ``ColorPickerPanel`` wraps —
/// edits the selected stop in place, rather than nesting a second dialog.
///
/// Every change writes straight through `gradient`, so a live consumer updates
/// as you edit. **Done** keeps the result (and records it in the recents);
/// **Cancel** — or any other dismissal, `Esc` included — restores the stops the
/// dialog opened with.
///
/// Present it like the colour panel (TUIkit modals are page-hosted):
///
/// ```swift
/// @State private var ramp = Gradient(colors: [.rgb(255, 80, 80), .rgb(80, 160, 255)])
/// @State private var editing = false
///
/// PageRoot {
///     Button("Edit gradient…") { editing = true }
/// }
/// .modal(isPresented: $editing) {
///     GradientEditorPanel(gradient: $ramp, isPresented: $editing)
/// }
/// ```
///
/// ## Positions are preserved
///
/// Editing a colour, or reordering the stops, moves colours between positions
/// and leaves the positions where they were — so a gradient handed to the
/// editor with deliberate spacing comes back with it. Adding a stop lands the
/// copy in the gap beside the selected one, moving nothing else, which is what
/// every gradient editor does and what "split here" has to mean once a stop
/// has a position at all.
///
/// ## It edits a solid colour too
///
/// A ``Gradient`` of one stop IS a colour — every consumer paints it flat —
/// so this dialog is the union surface: the **Gradient** switch collapses the
/// ramp to the selected stop or expands that stop back into two, and in solid
/// mode the stop strip, the action row and the gradient library are simply not
/// there, because there is one stop and nothing to order it against.
///
/// That is why ``ColorPickerPanel`` gains no gradient affordance in return:
/// its callers include palette slots that can only store a colour, so widening
/// it would offer an edit half its callers cannot accept. Present whichever
/// dialog matches what the binding can hold, and the binding type makes the
/// wrong choice fail to compile.
public struct GradientEditorPanel: View {
    private let title: String
    private let gradient: Binding<Gradient>
    private let isPresented: Binding<Bool>

    /// The index of the stop the embedded colour panel is editing. Clamped on
    /// every read, so external shrinking of `stops` can't strand it.
    @State private var selectedStop = 0

    /// Per-presentation bookkeeping for Cancel semantics. A REFERENCE type:
    /// the dismissal callback must read the values as they are when it fires,
    /// not as they were when the closure's frame was rendered (a value capture
    /// would miss "Done" setting `applied` in the same action that dismisses).
    @State private var session = Session()

    /// The last ``recentLimit`` gradients *applied* (Done), most recent first,
    /// persisted app-wide — see ``encodeRecents(_:)`` for the format.
    @AppStorage("tuikit.gradientEditor.recents") private var recentsRaw = ""

    private final class Session {
        var original: Gradient?
        var applied = false
    }

    /// The preview strip's width in cells — also the wrap budget for the stop
    /// and gradient chips, so no row grows the dialog past the preview.
    private static let previewWidth = 36

    /// ``previewWidth``, for the test that asserts the strip IS the quantised
    /// ramp — which has to know how long the ramp is to look for it.
    static var previewWidthForTesting: Int { previewWidth }

    /// Creates a gradient-editor panel with a localized title.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``. The title is not defaulted in this overload, or
    /// the two would be ambiguous where it is omitted.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the dialog title.
    ///   - gradient: The gradient being edited. Rewritten live on every
    ///     change; restored to the opening value on Cancel / `Esc`.
    ///   - isPresented: Bound to the presenting `.modal`; Done and Cancel set
    ///     it false.
    public init(
        _ titleKey: LocalizedStringKey,
        gradient: Binding<Gradient>,
        isPresented: Binding<Bool>
    ) {
        self.init(titleKey.localized, gradient: gradient, isPresented: isPresented)
    }

    /// Creates a gradient-editor panel titled as written.
    ///
    /// Generic over `StringProtocol`, which is both SwiftUI's own spelling and
    /// what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey`` for why the concrete-`String` spelling does not.
    /// A generic parameter cannot carry a default, so the defaulted title lives
    /// in ``init(gradient:isPresented:)`` instead of here.
    ///
    /// - Parameters:
    ///   - title: The dialog title.
    ///   - gradient: The gradient being edited. Rewritten live on every
    ///     change; restored to the opening value on Cancel / `Esc`.
    ///   - isPresented: Bound to the presenting `.modal`; Done and Cancel set
    ///     it false.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S,
        gradient: Binding<Gradient>,
        isPresented: Binding<Bool>
    ) {
        self.title = String(title)
        self.gradient = gradient
        self.isPresented = isPresented
    }

    /// Creates a gradient-editor panel titled `"Gradient"`.
    ///
    /// The title's default lives here rather than on either titled overload:
    /// neither of those can carry it — a generic parameter cannot have a
    /// default, and defaulting the ``LocalizedStringKey`` one would make the
    /// two ambiguous wherever the title is omitted. The forwarded default is
    /// written `as String` so it stays on the disfavoured side: a bare literal
    /// would bind to the key overload and go looking for a `"Gradient"` key
    /// that is in no table.
    ///
    /// - Parameters:
    ///   - gradient: The gradient being edited. Rewritten live on every
    ///     change; restored to the opening value on Cancel / `Esc`.
    ///   - isPresented: Bound to the presenting `.modal`; Done and Cancel set
    ///     it false.
    public init(
        gradient: Binding<Gradient>,
        isPresented: Binding<Bool>
    ) {
        self.init("Gradient" as String, gradient: gradient, isPresented: isPresented)
    }

    public var body: some View {
        let recents = Self.decodeRecents(recentsRaw)
        Dialog(title: title, titleColor: .palette.accent, footerAlignment: .center) {
            VStack(alignment: .center, spacing: 1) {
                modeSwitch
                previewStrip
                if isGradient {
                    stopStrip
                    actionRow
                    gradientChips(recents: recents)
                }
                // A rule between the gradient LIBRARY above (stops, actions,
                // presets, recents) and the colour-editing panel below —
                // without it the recents chips read as part of the editor.
                // Fixed at the library column's width: an unconstrained
                // Divider is width-flexible, which would stretch this
                // content-hugging dialog to the whole screen (same reason the
                // footer avoids a leading Spacer).
                Divider().frame(width: Self.previewWidth)
                _ColorPickerBody(selection: selectedStopBinding)
            }
            .onAppear { session.original = gradient.wrappedValue }
            .onDisappear {
                // ANY dismissal that isn't "Done" — Cancel, Esc, the page
                // going away — restores what the dialog opened with. Live
                // edits already wrote through `stops`, so this is the undo.
                if !session.applied, let original = session.original {
                    gradient.wrappedValue = original
                }
            }
        } footer: {
            // No leading Spacer (it is width-flexible and would stretch the
            // dialog); the footer sizes to the buttons, the dialog to its tabs.
            HStack(spacing: 2) {
                Button("Cancel") { isPresented.wrappedValue = false }
                Button("Done") {
                    session.applied = true
                    recentsRaw = Self.encodeRecents(
                        Self.recordingRecent(
                            gradient.wrappedValue, in: Self.decodeRecents(recentsRaw)))
                    isPresented.wrappedValue = false
                }
                .buttonStyle(.primary)
            }
        }
    }

    // MARK: Mode

    /// Whether this is a ramp at all. One stop is a solid colour, and the
    /// dialog shows the colour editor alone for it.
    private var isGradient: Bool { gradient.wrappedValue.stops.count > 1 }

    /// Solid ⇄ gradient, which is collapsing to or expanding from one stop —
    /// the same two edits `−` and `+` make at the floor, so there is one
    /// mechanism (the stop count) reachable two ways rather than a mode flag
    /// that could disagree with the stops.
    private var modeSwitch: some View {
        Toggle(
            LocalizedStringKey(LocalizationKey.Label.gradient.rawValue),
            isOn: Binding(
                get: { isGradient },
                set: { wantsGradient in
                    guard wantsGradient != isGradient else { return }
                    if wantsGradient {
                        let (updated, selected) = Self.duplicatingStop(
                            gradient.wrappedValue, at: clampedSelection)
                        gradient.wrappedValue = updated
                        selectedStop = selected
                    } else {
                        gradient.wrappedValue = Self.collapsedToSolid(
                            gradient.wrappedValue, at: clampedSelection)
                        selectedStop = 0
                    }
                }))
    }

    // MARK: Preview

    /// The gradient rendered across a fixed strip with the SAME interpolation
    /// every gradient consumer uses, one cell per sample, two rows tall.
    ///
    /// Built WITHOUT a `ForEach` over row numbers: an `Equatable` element
    /// (like a row index) would wrap each row in the element-keyed render
    /// memo, which cannot see the stop colours the row captures — the preview
    /// froze until something else invalidated the cache.
    private var previewStrip: some View {
        let ramp = gradient.wrappedValue
        // Through the RAMP overload, which quantises the whole strip at once
        // and repairs it into a monotone one. Per cell — which this was — a
        // nearest match has no memory of its neighbours, so the editor's own
        // preview banded on a 256-colour terminal while the track it was
        // configuring did not. See `Color.quantisedRamp(_:count:depth:)`.
        let cells = (0..<Self.previewWidth).map { index in
            TrackRenderer.gradientColor(
                ramp, index: index, span: Self.previewWidth,
                fallback: ramp.stops.first?.color ?? .palette.accent, depth: ColorDepth.current)
        }
        return VStack(spacing: 0) {
            colorCellRow(cells)
            colorCellRow(cells)
        }
    }

    /// One row of per-cell coloured blocks. Glyph AND background in the
    /// colour, like the colour panel's swatch: solid in terminals that don't
    /// paint behind spaces, gap-free where the font leaves hairlines.
    private func colorCellRow(_ cells: [Color]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, color in
                Text("█").foregroundStyle(color).background(color)
            }
        }
    }

    // MARK: Stop strip

    /// One bare 3-cell swatch per stop, in gradient order, wrapped onto as
    /// many rows as the preview width allows (one row until it can't be).
    ///
    /// The stops aren't options to enumerate — the swatch colour IS the
    /// label — so the chips carry no numbering and no chrome beside them.
    /// The CENTRE cell doubles as the state indicator: a readable-contrast
    /// bullet marks the stop the panel below is editing, pulsing while the
    /// chip holds keyboard focus, dim as a hover or drop-target hint
    /// (``_ColorSwatchButtonStyle``). Every state re-colours that one cell in place,
    /// so nothing ever shifts.
    ///
    /// Chips also reorder LIVE: dragging one moves its stop through the
    /// strip immediately, following the cursor — X picks the nearest slot,
    /// Y the nearest row when the strip wraps (`dragSlot(forX:y:count:)`) —
    /// an alternative to the ◀ ▶ single-step buttons. Click-to-select
    /// survives the drag handle because a press released without movement
    /// forwards to the button as an ordinary click.
    private var stopStrip: some View {
        let list = gradient.wrappedValue.stops
        let selection = clampedSelection
        let rows = Self.chipRows(count: list.count)
        return VStack(alignment: .center, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 1) {
                    ForEach(row, id: \.self) { index in
                        stopChip(
                            index: index, color: list[index].color, isSelected: index == selection)
                    }
                }
            }
        }
    }

    private func stopChip(index: Int, color: Color, isSelected: Bool) -> some View {
        _StopChipDragHandle(
            content: Button("") { selectedStop = index }
                .buttonStyle(_ColorSwatchButtonStyle(color: color, isSelected: isSelected)),
            index: index,
            stopCount: gradient.wrappedValue.stops.count,
            grab: { selectedStop = index },
            moveStop: { from, to in
                let (updated, selected) = Self.movingStop(
                    gradient.wrappedValue, from: from, to: to)
                gradient.wrappedValue = updated
                selectedStop = selected
            })
    }

    /// The cell width of every stop chip — the shared swatch width, so the
    /// strip's drag geometry cannot drift from what the chips actually draw.
    static let stopChipWidth = _ColorSwatchButtonStyle.width

    /// Insert / remove / reorder controls for the selected stop.
    private var actionRow: some View {
        let ramp = gradient.wrappedValue
        let selection = clampedSelection
        return HStack(spacing: 1) {
            Button("+") {
                let (updated, selected) = Self.duplicatingStop(ramp, at: selection)
                gradient.wrappedValue = updated
                selectedStop = selected
            }
            Button("−") {
                let (updated, selected) = Self.removingStop(ramp, at: selection)
                gradient.wrappedValue = updated
                selectedStop = selected
            }
            .disabled(ramp.stops.count <= 2)
            Button("◀") {
                let (updated, selected) = Self.movingStop(ramp, at: selection, by: -1)
                gradient.wrappedValue = updated
                selectedStop = selected
            }
            .disabled(selection == 0)
            Button("▶") {
                let (updated, selected) = Self.movingStop(ramp, at: selection, by: 1)
                gradient.wrappedValue = updated
                selectedStop = selected
            }
            .disabled(selection >= ramp.stops.count - 1)
        }
    }

    // MARK: Presets & recents

    /// One-click gradients: the built-in ``presets``, then — under a rule —
    /// the recently *applied* gradients (most recent first), each drawn as a
    /// small strip button. Selecting one replaces the stops (live, and
    /// revertable by Cancel like any other edit).
    @ViewBuilder private func gradientChips(recents: [Gradient]) -> some View {
        chipRows(for: Self.presets)
        if !recents.isEmpty {
            // Dashed: a SUB-division within the library, deliberately
            // lighter than the solid rule that closes the whole library
            // section below.
            Text(String(repeating: "┄", count: Self.previewWidth))
                .foregroundStyle(.palette.border)
            chipRows(for: recents)
        }
    }

    /// `gradients` as wrapped rows of strip buttons.
    private func chipRows(for gradients: [Gradient]) -> some View {
        let widths = gradients.map { _ in 2 + Self.chipStripWidth }  // focus prefix + strip
        let rows = Self.wrappedRows(
            itemWidths: widths, spacing: 1, budget: Self.previewWidth)
        return VStack(alignment: .center, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 1) {
                    ForEach(row, id: \.self) { index in
                        gradientChip(gradients[index])
                    }
                }
            }
        }
    }

    /// The width of one gradient chip's strip, in cells.
    private static let chipStripWidth = 8

    private func gradientChip(_ ramp: Gradient) -> some View {
        let cells = (0..<Self.chipStripWidth).map { index in
            TrackRenderer.gradientColor(
                ramp, index: index, span: Self.chipStripWidth,
                fallback: ramp.stops.first?.color ?? .palette.accent, depth: ColorDepth.current)
        }
        return Button {
            gradient.wrappedValue = Self.applying(ramp, to: gradient.wrappedValue)
            selectedStop = 0
        } label: {
            colorCellRow(cells)
        }
        .buttonStyle(.plain)
    }

    // MARK: Selection plumbing

    /// `selectedStop` clamped into the current stop list.
    private var clampedSelection: Int {
        max(0, min(selectedStop, gradient.wrappedValue.stops.count - 1))
    }

    /// A colour binding onto the selected stop. The embedded panel re-seeds
    /// itself whenever this reads a different colour (its channel editors
    /// watch the selection), so switching stops refreshes it in place.
    private var selectedStopBinding: Binding<Color> {
        Binding(
            get: {
                let list = gradient.wrappedValue.stops
                guard !list.isEmpty else { return .rgb(0, 0, 0) }
                return list[max(0, min(selectedStop, list.count - 1))].color
            },
            set: { newValue in
                var list = gradient.wrappedValue.stops
                guard !list.isEmpty else { return }
                // The colour changes; the POSITION does not. That is the whole
                // of "editing a stop" once a stop has a position.
                list[max(0, min(selectedStop, list.count - 1))].color = newValue
                // The STOPS are replaced, not the gradient — see `withStops`.
                gradient.wrappedValue = gradient.wrappedValue.withStops(list)
            })
    }
}

// MARK: - Stop mutations (pure; unit-tested)

extension GradientEditorPanel {
    /// Inserts a copy of the stop at `index` in the gap beside it and selects
    /// the copy — duplicating reads as "split here", and editing the copy
    /// diverges it.
    ///
    /// **Nothing else moves.** The copy lands midway between the stop and its
    /// neighbour, which is what every gradient editor does and the only thing
    /// "split here" can mean once a stop has a position. For the LAST stop
    /// there is no gap after it, so the copy goes in the gap before it — a
    /// stop stacked exactly on another would be invisible until edited and
    /// then a hard edge, which is not what the button says.
    static func duplicatingStop(_ gradient: Gradient, at index: Int) -> (Gradient, selected: Int) {
        let list = gradient.stops
        guard list.indices.contains(index) else { return (gradient, max(0, list.count - 1)) }
        guard list.count > 1 else {
            // One stop is a solid colour; splitting it is how it becomes a
            // gradient, and a gradient of one colour spans the whole ramp.
            return (
                gradient.withStops([
                    Gradient.Stop(color: list[0].color, location: 0),
                    Gradient.Stop(color: list[0].color, location: 1),
                ]), 1
            )
        }
        var updated = list
        let insertion: Int
        let location: Double
        if index < list.count - 1 {
            insertion = index + 1
            location = (list[index].location + list[index + 1].location) / 2
        } else {
            insertion = index
            location = (list[index - 1].location + list[index].location) / 2
        }
        updated.insert(Gradient.Stop(color: list[index].color, location: location), at: insertion)
        return (gradient.withStops(updated), insertion)
    }

    /// The gradient reduced to the stop at `index` alone — a solid colour.
    ///
    /// The survivor moves to 0: a lone stop's position cannot be seen, and
    /// leaving it where it happened to be would make expanding again start
    /// from an arbitrary place.
    static func collapsedToSolid(_ gradient: Gradient, at index: Int) -> Gradient {
        let list = gradient.stops
        guard let stop = list.indices.contains(index) ? list[index] : list.first else {
            return gradient
        }
        return gradient.withStops([Gradient.Stop(color: stop.color, location: 0)])
    }

    /// Removes the stop at `index`, refusing to empty the gradient. The
    /// selection stays at the same position, clamped.
    ///
    /// The floor is ONE, not two: a one-stop gradient is a solid colour, which
    /// this dialog can express and every consumer paints. Taking the last of
    /// two stops is therefore the same edit the **Gradient** switch makes, and
    /// the switch is where it is spelled out.
    static func removingStop(_ gradient: Gradient, at index: Int) -> (Gradient, selected: Int) {
        let list = gradient.stops
        guard list.count > 1, list.indices.contains(index) else {
            return (gradient, max(0, min(index, list.count - 1)))
        }
        var updated = list
        updated.remove(at: index)
        return (gradient.withStops(updated), min(index, updated.count - 1))
    }

    /// Swaps the stop at `index` with its neighbour `offset` (−1 left, +1
    /// right) and follows it with the selection. Out-of-range moves are no-ops.
    ///
    /// The COLOURS swap and the positions stay: the stops are where they are,
    /// and what "move this stop left" means on screen is that its colour is
    /// now the one further left.
    static func movingStop(
        _ gradient: Gradient, at index: Int, by offset: Int
    ) -> (Gradient, selected: Int) {
        let list = gradient.stops
        let destination = index + offset
        guard list.indices.contains(index), list.indices.contains(destination) else {
            return (gradient, max(0, min(index, list.count - 1)))
        }
        var colours = list.map(\.color)
        colours.swapAt(index, destination)
        return (gradient.withStops(recoloured(list, with: colours)), destination)
    }

    /// Moves the stop at `source` to `destination` (remove + insert — the
    /// stops between them shift one place, drag-to-reorder semantics, unlike
    /// the neighbour SWAP of `movingStop(_:at:by:)`) and follows it with the
    /// selection. Out-of-range or same-place moves are no-ops.
    ///
    /// Colours again, for the same reason: dragging a chip through the strip
    /// carries its colour past the others, and the ramp keeps its shape.
    static func movingStop(
        _ gradient: Gradient, from source: Int, to destination: Int
    ) -> (Gradient, selected: Int) {
        let list = gradient.stops
        guard list.indices.contains(source), list.indices.contains(destination),
            source != destination
        else {
            return (gradient, max(0, min(source, list.count - 1)))
        }
        var colours = list.map(\.color)
        colours.insert(colours.remove(at: source), at: destination)
        return (gradient.withStops(recoloured(list, with: colours)), destination)
    }

    /// `stops` with `colours` laid back onto their positions, in order.
    private static func recoloured(_ stops: [Gradient.Stop], with colours: [Color])
        -> [Gradient.Stop]
    {
        zip(stops, colours).map { Gradient.Stop(color: $1, location: $0.location) }
    }
}

// MARK: - Chip wrapping (pure; unit-tested)

extension GradientEditorPanel {
    /// The stop strip's row layout for `count` chips — `wrappedRows` over
    /// uniform ``stopChipWidth`` items with 1-cell gaps in the preview-width
    /// budget. Shared by rendering and the live-drag geometry, so the two
    /// can never disagree about where a chip sits.
    static func chipRows(count: Int) -> [[Int]] {
        wrappedRows(
            itemWidths: Array(repeating: stopChipWidth, count: count),
            spacing: 1, budget: previewWidth)
    }

    /// The cell width of one strip row: its chips plus the gaps between them.
    private static func chipRowWidth(_ row: [Int]) -> Int {
        row.count * stopChipWidth + max(0, row.count - 1)
    }

    /// The (x, y) cell origin of the chip at `index` within the rendered
    /// strip (rows are one cell tall and centred in the strip's width). The
    /// live drag anchors its coordinate math here.
    static func chipStripOrigin(of index: Int, count: Int) -> (x: Int, y: Int) {
        let rows = chipRows(count: count)
        let stripWidth = rows.map(chipRowWidth).max() ?? 0
        for (rowIndex, row) in rows.enumerated() {
            if let column = row.firstIndex(of: index) {
                let rowOffset = (stripWidth - chipRowWidth(row)) / 2
                return (rowOffset + column * (stopChipWidth + 1), rowIndex)
            }
        }
        return (0, 0)
    }

    /// The stop index whose chip slot is NEAREST the given strip-relative
    /// point — the live-drag mapping. Deliberately tolerant: with a single
    /// row the Y coordinate is irrelevant (anything clamps to it), with
    /// wrapped rows Y picks the nearest row, and within the row X picks the
    /// nearest chip centre — dragging past either end holds the end slot.
    static func dragSlot(forX x: Int, y: Int, count: Int) -> Int {
        let rows = chipRows(count: count)
        guard let firstRow = rows.first else { return 0 }
        let stripWidth = rows.map(chipRowWidth).max() ?? 0
        let row = rows[min(max(y, 0), rows.count - 1)]
        guard !row.isEmpty else { return firstRow.first ?? 0 }
        let rowOffset = (stripWidth - chipRowWidth(row)) / 2
        var best = row[0]
        var bestDistance = Int.max
        for (column, index) in row.enumerated() {
            let centre = rowOffset + column * (stopChipWidth + 1) + stopChipWidth / 2
            let distance = abs(x - centre)
            if distance < bestDistance {
                best = index
                bestDistance = distance
            }
        }
        return best
    }

    /// Greedily packs items into rows no wider than `budget` cells (each row's
    /// items plus `spacing` between them). Every row holds at least one item,
    /// so an over-budget single item still shows rather than vanishing.
    static func wrappedRows(itemWidths: [Int], spacing: Int, budget: Int) -> [[Int]] {
        var rows: [[Int]] = []
        var row: [Int] = []
        var rowWidth = 0
        for (index, width) in itemWidths.enumerated() {
            let added = row.isEmpty ? width : spacing + width
            if !row.isEmpty && rowWidth + added > budget {
                rows.append(row)
                row = [index]
                rowWidth = width
            } else {
                row.append(index)
                rowWidth += added
            }
        }
        if !row.isEmpty { rows.append(row) }
        return rows
    }
}

// MARK: - Presets & recents (pure; unit-tested)

extension GradientEditorPanel {
    /// The built-in gradients, offered as one-click chips.
    static let presets: [Gradient] = [
        // Rainbow
        Gradient(colors: [
            .rgb(255, 64, 64), .rgb(255, 200, 0), .rgb(64, 192, 64),
            .rgb(64, 200, 255), .rgb(64, 64, 255), .rgb(192, 64, 255),
        ]),
        // Heat
        Gradient(colors: [.rgb(120, 0, 0), .rgb(255, 80, 0), .rgb(255, 200, 0), .rgb(255, 255, 220)]),
        // Ocean
        Gradient(colors: [.rgb(0, 40, 120), .rgb(0, 140, 200), .rgb(120, 230, 255)]),
        // Sunset
        Gradient(colors: [.rgb(255, 120, 60), .rgb(230, 80, 140), .rgb(90, 40, 140)]),
        // Forest
        Gradient(colors: [.rgb(20, 90, 50), .rgb(90, 180, 80), .rgb(210, 230, 120)]),
        // Greyscale
        Gradient(colors: [.rgb(40, 40, 40), .rgb(230, 230, 230)]),
    ]

    /// A library chip applied to `gradient` — the chip's STOPS, laid onto the
    /// ramp the app bound.
    ///
    /// A preset and a stored recent are colours and positions and nothing
    /// else: neither is a gradient the app configured, and neither format has
    /// anywhere to put a colour space. So picking one changes which colours
    /// are painted and leaves how they are blended alone — the same rule every
    /// edit in this panel follows.
    ///
    /// - Parameters:
    ///   - chip: The library gradient that was picked.
    ///   - gradient: The gradient being edited.
    /// - Returns: `gradient` wearing `chip`'s stops.
    static func applying(_ chip: Gradient, to gradient: Gradient) -> Gradient {
        gradient.withStops(chip.stops)
    }

    /// How many applied gradients the recents keep.
    static let recentLimit = 10

    /// Records an applied gradient at the front of `recents`: duplicates are
    /// removed (re-applying moves a gradient to the front, so the list stays
    /// in descending recency and evicts least-recently-used), the built-in
    /// ``presets`` are never recorded (they already have a home above the
    /// rule), and the list caps at ``recentLimit``.
    static func recordingRecent(_ gradient: Gradient, in recents: [Gradient]) -> [Gradient] {
        guard gradient.stops.count >= 2, !presets.contains(gradient) else { return recents }
        var updated = recents.filter { $0 != gradient }
        updated.insert(gradient, at: 0)
        return Array(updated.prefix(recentLimit))
    }

    /// Decodes the persisted recents. Entries that don't decode to at least
    /// two stops drop.
    ///
    /// **A stop written without a position is read as evenly spaced**, which is
    /// exactly what the previous format — bare `RRGGBB` stops, from when a
    /// gradient WAS an even `[Color]` — meant. So an app's stored recents
    /// migrate by being read, with no version flag and nothing to convert.
    static func decodeRecents(_ raw: String) -> [Gradient] {
        raw.split(separator: ";").compactMap { entry in
            let fields = entry.split(separator: ",")
            guard fields.count >= 2 else { return nil }
            var stops: [Gradient.Stop] = []
            for (index, field) in fields.enumerated() {
                let parts = field.split(separator: "@", maxSplits: 1)
                guard let colour = Color.hex(String(parts[0])) else { continue }
                let even = Double(index) / Double(fields.count - 1)
                let location = parts.count > 1 ? Double(parts[1]) ?? even : even
                stops.append(Gradient.Stop(color: colour, location: location))
            }
            // `Gradient(stops:)` is right HERE and nowhere else in this file:
            // a recent is built from stored text, so there is no incoming
            // gradient whose colour space could be carried — the chip that
            // applies it lays these stops onto the bound gradient, which has
            // one. Everything that EDITS a gradient goes through `withStops`.
            return stops.count >= 2 ? Gradient(stops: stops) : nil
        }
    }

    /// Encodes recents for persistence — the inverse of ``decodeRecents(_:)``.
    ///
    /// `;`-separated gradients of `,`-separated `RRGGBB@position` stops, the
    /// position to three decimals. Positions are always written, even when
    /// even: a reader cannot tell an evenly-spaced gradient from one whose
    /// spacing happens to look even, and the round trip has to be exact.
    static func encodeRecents(_ recents: [Gradient]) -> String {
        recents.map { gradient in
            gradient.stops.map { stop in
                let hex: String
                if let components = stop.color.rgbComponents {
                    hex = String(
                        format: "%02X%02X%02X", components.red, components.green, components.blue)
                } else {
                    hex = "000000"
                }
                return hex + String(format: "@%.3f", stop.location)
            }.joined(separator: ",")
        }.joined(separator: ";")
    }
}
