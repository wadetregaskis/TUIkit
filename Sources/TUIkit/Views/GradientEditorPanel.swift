//  🖥️ TUIKit — Terminal UI Kit for Swift
//  GradientEditorPanel.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitStyling

// MARK: - Gradient Editor Panel

/// A modal gradient editor — ``ColorPickerPanel``'s sibling for the `[Color]`
/// stop lists TUIkit's gradients are made of (``TrackConfiguration``'s
/// `fillGradient`, `.threeSegment`'s ``SegmentColoring/gradient(_:)``, and the
/// indeterminate ``IndeterminateStyle/gradient(colors:period:)`` sweep).
///
/// TUIkit gradients are evenly-spaced colour stops interpolated piecewise
/// (`TrackRenderer.gradientColor`); the editor shows that exact interpolation
/// live in its preview strip. Below it, the stop strip selects a stop (click
/// its swatch), the action row inserts / removes / reorders stops, preset and
/// recently-applied gradients offer one-click starting points, and an embedded
/// colour panel — the same preview-plus-tabs body ``ColorPickerPanel`` wraps —
/// edits the selected stop in place, rather than nesting a second dialog.
///
/// Every change writes straight through `stops`, so a live consumer updates as
/// you edit. **Done** keeps the result (and records it in the recents);
/// **Cancel** — or any other dismissal, `Esc` included — restores the stops the
/// dialog opened with.
///
/// Present it like the colour panel (TUIkit modals are page-hosted):
///
/// ```swift
/// @State private var stops: [Color] = [.rgb(255, 80, 80), .rgb(80, 160, 255)]
/// @State private var editing = false
///
/// PageRoot {
///     Button("Edit gradient…") { editing = true }
/// }
/// .modal(isPresented: $editing) {
///     GradientEditorPanel(stops: $stops, isPresented: $editing)
/// }
/// ```
///
/// A gradient needs at least two stops (fewer render as the consumer's
/// fallback colour), so "Remove" disables at two.
public struct GradientEditorPanel: View {
    private let title: String
    private let stops: Binding<[Color]>
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
    /// persisted app-wide as `;`-separated stop lists of `,`-separated hex.
    @AppStorage("tuikit.gradientEditor.recents") private var recentsRaw = ""

    private final class Session {
        var original: [Color]?
        var applied = false
    }

    /// The preview strip's width in cells — also the wrap budget for the stop
    /// and gradient chips, so no row grows the dialog past the preview.
    private static let previewWidth = 36

    /// Creates a gradient-editor panel over a colour-stop binding.
    ///
    /// - Parameters:
    ///   - title: The dialog title (default `"Gradient"`).
    ///   - stops: The gradient's colour stops, evenly spaced. Rewritten live
    ///     on every change; restored to the opening value on Cancel / `Esc`.
    ///   - isPresented: Bound to the presenting `.modal`; Done and Cancel set
    ///     it false.
    public init(
        _ title: String = "Gradient",
        stops: Binding<[Color]>,
        isPresented: Binding<Bool>
    ) {
        self.title = title
        self.stops = stops
        self.isPresented = isPresented
    }

    public var body: some View {
        let recents = Self.decodeRecents(recentsRaw)
        Dialog(title: title, titleColor: .palette.accent, footerAlignment: .center) {
            VStack(alignment: .center, spacing: 1) {
                previewStrip
                stopStrip
                actionRow
                gradientChips(recents: recents)
                _ColorPickerBody(selection: selectedStopBinding)
            }
            .onAppear { session.original = stops.wrappedValue }
            .onDisappear {
                // ANY dismissal that isn't "Done" — Cancel, Esc, the page
                // going away — restores what the dialog opened with. Live
                // edits already wrote through `stops`, so this is the undo.
                if !session.applied, let original = session.original {
                    stops.wrappedValue = original
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
                        Self.recordingRecent(stops.wrappedValue, in: Self.decodeRecents(recentsRaw)))
                    isPresented.wrappedValue = false
                }
                .buttonStyle(.primary)
            }
        }
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
        let list = stops.wrappedValue
        let cells = (0..<Self.previewWidth).map { index in
            TrackRenderer.gradientColor(
                stops: list,
                parameter: Self.previewWidth > 1
                    ? Double(index) / Double(Self.previewWidth - 1) : 0,
                fallback: list.first ?? .palette.accent)
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

    /// One numbered swatch per stop — `● 3 ██` selected, `◯ 4 ██` otherwise —
    /// wrapped onto as many rows as the preview width allows.
    ///
    /// Picking one-of-N stops is radio-button semantics, so each row IS a
    /// horizontal ``RadioButtonGroup`` (all rows share the selection binding).
    /// That gives the chips ONE indicator cell carrying both states the way
    /// every radio button does — solid `●` when selected, pulsing when
    /// focused, dim `◯` otherwise — instead of a plain button's focus bullet
    /// sitting beside a separate selection marker. Chip geometry is
    /// selection-independent, so moving the selection never shifts a swatch,
    /// and each row is a single Tab stop with Left/Right moving inside it.
    private var stopStrip: some View {
        let list = stops.wrappedValue
        let selection = clampedSelection
        let widths = list.indices.map { Self.stopChipWidth(index: $0) }
        let rows = Self.wrappedRows(
            itemWidths: widths,
            spacing: RadioButtonGroupMetrics.horizontalSpacing,
            budget: Self.previewWidth)
        return VStack(alignment: .center, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                RadioButtonGroup(
                    selection: Binding(
                        get: { clampedSelection },
                        set: { selectedStop = $0 }),
                    orientation: .horizontal,
                    items: row.map { index in
                        RadioButtonItem(index) {
                            HStack(spacing: 1) {
                                Text("\(index + 1)")
                                    .foregroundStyle(
                                        index == selection
                                            ? Color.palette.accent
                                            : Color.palette.foregroundSecondary)
                                Text("██").foregroundStyle(list[index])
                            }
                        }
                    })
            }
        }
    }

    /// The cell width of the stop chip at `index`: the radio indicator + the
    /// 1-based number + a breathing space + the 2-cell swatch.
    static func stopChipWidth(index: Int) -> Int {
        RadioButtonGroupMetrics.indicatorWidth + String(index + 1).count + 1 + 2
    }

    /// Insert / remove / reorder controls for the selected stop.
    private var actionRow: some View {
        let list = stops.wrappedValue
        let selection = clampedSelection
        return HStack(spacing: 1) {
            Button("+") {
                let (updated, selected) = Self.duplicatingStop(list, at: selection)
                stops.wrappedValue = updated
                selectedStop = selected
            }
            Button("−") {
                let (updated, selected) = Self.removingStop(list, at: selection)
                stops.wrappedValue = updated
                selectedStop = selected
            }
            .disabled(list.count <= 2)
            Button("◀") {
                let (updated, selected) = Self.movingStop(list, at: selection, by: -1)
                stops.wrappedValue = updated
                selectedStop = selected
            }
            .disabled(selection == 0)
            Button("▶") {
                let (updated, selected) = Self.movingStop(list, at: selection, by: 1)
                stops.wrappedValue = updated
                selectedStop = selected
            }
            .disabled(selection >= list.count - 1)
        }
    }

    // MARK: Presets & recents

    /// One-click gradients: the built-in ``presets``, then — under a rule —
    /// the recently *applied* gradients (most recent first), each drawn as a
    /// small strip button. Selecting one replaces the stops (live, and
    /// revertable by Cancel like any other edit).
    @ViewBuilder private func gradientChips(recents: [[Color]]) -> some View {
        chipRows(for: Self.presets)
        if !recents.isEmpty {
            Text(String(repeating: "─", count: Self.previewWidth))
                .foregroundStyle(.palette.border)
            chipRows(for: recents)
        }
    }

    /// `gradients` as wrapped rows of strip buttons.
    private func chipRows(for gradients: [[Color]]) -> some View {
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

    private func gradientChip(_ gradient: [Color]) -> some View {
        let cells = (0..<Self.chipStripWidth).map { index in
            TrackRenderer.gradientColor(
                stops: gradient,
                parameter: Double(index) / Double(Self.chipStripWidth - 1),
                fallback: gradient.first ?? .palette.accent)
        }
        return Button {
            stops.wrappedValue = gradient
            selectedStop = 0
        } label: {
            colorCellRow(cells)
        }
        .buttonStyle(.plain)
    }

    // MARK: Selection plumbing

    /// `selectedStop` clamped into the current stop list.
    private var clampedSelection: Int {
        max(0, min(selectedStop, stops.wrappedValue.count - 1))
    }

    /// A colour binding onto the selected stop. The embedded panel re-seeds
    /// itself whenever this reads a different colour (its channel editors
    /// watch the selection), so switching stops refreshes it in place.
    private var selectedStopBinding: Binding<Color> {
        Binding(
            get: {
                let list = stops.wrappedValue
                guard !list.isEmpty else { return .rgb(0, 0, 0) }
                return list[max(0, min(selectedStop, list.count - 1))]
            },
            set: { newValue in
                var list = stops.wrappedValue
                guard !list.isEmpty else { return }
                list[max(0, min(selectedStop, list.count - 1))] = newValue
                stops.wrappedValue = list
            })
    }
}

// MARK: - Stop-list mutations (pure; unit-tested)

extension GradientEditorPanel {
    /// Inserts a copy of the stop at `index` immediately after it and selects
    /// the copy — duplicating reads as "split here", and editing the copy
    /// diverges it.
    static func duplicatingStop(_ stops: [Color], at index: Int) -> ([Color], selected: Int) {
        guard stops.indices.contains(index) else { return (stops, max(0, stops.count - 1)) }
        var updated = stops
        updated.insert(stops[index], at: index + 1)
        return (updated, index + 1)
    }

    /// Removes the stop at `index`, refusing to go below two stops (fewer is
    /// not a gradient). The selection stays at the same position, clamped.
    static func removingStop(_ stops: [Color], at index: Int) -> ([Color], selected: Int) {
        guard stops.count > 2, stops.indices.contains(index) else {
            return (stops, max(0, min(index, stops.count - 1)))
        }
        var updated = stops
        updated.remove(at: index)
        return (updated, min(index, updated.count - 1))
    }

    /// Swaps the stop at `index` with its neighbour `offset` (−1 left, +1
    /// right) and follows it with the selection. Out-of-range moves are no-ops.
    static func movingStop(_ stops: [Color], at index: Int, by offset: Int) -> ([Color], selected: Int) {
        let destination = index + offset
        guard stops.indices.contains(index), stops.indices.contains(destination) else {
            return (stops, max(0, min(index, stops.count - 1)))
        }
        var updated = stops
        updated.swapAt(index, destination)
        return (updated, destination)
    }
}

// MARK: - Chip wrapping (pure; unit-tested)

extension GradientEditorPanel {
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
    static let presets: [[Color]] = [
        // Rainbow
        [.rgb(255, 64, 64), .rgb(255, 200, 0), .rgb(64, 192, 64),
         .rgb(64, 200, 255), .rgb(64, 64, 255), .rgb(192, 64, 255)],
        // Heat
        [.rgb(120, 0, 0), .rgb(255, 80, 0), .rgb(255, 200, 0), .rgb(255, 255, 220)],
        // Ocean
        [.rgb(0, 40, 120), .rgb(0, 140, 200), .rgb(120, 230, 255)],
        // Sunset
        [.rgb(255, 120, 60), .rgb(230, 80, 140), .rgb(90, 40, 140)],
        // Forest
        [.rgb(20, 90, 50), .rgb(90, 180, 80), .rgb(210, 230, 120)],
        // Greyscale
        [.rgb(40, 40, 40), .rgb(230, 230, 230)],
    ]

    /// How many applied gradients the recents keep.
    static let recentLimit = 10

    /// Records an applied gradient at the front of `recents`: duplicates are
    /// removed (re-applying moves a gradient to the front, so the list stays
    /// in descending recency and evicts least-recently-used), the built-in
    /// ``presets`` are never recorded (they already have a home above the
    /// rule), and the list caps at ``recentLimit``.
    static func recordingRecent(_ gradient: [Color], in recents: [[Color]]) -> [[Color]] {
        guard gradient.count >= 2, !presets.contains(gradient) else { return recents }
        var updated = recents.filter { $0 != gradient }
        updated.insert(gradient, at: 0)
        return Array(updated.prefix(recentLimit))
    }

    /// Decodes the persisted recents: `;`-separated gradients of `,`-separated
    /// `RRGGBB` stops. Entries that don't decode to at least two stops drop.
    static func decodeRecents(_ raw: String) -> [[Color]] {
        raw.split(separator: ";").compactMap { entry in
            let stops = entry.split(separator: ",").compactMap { Color.hex(String($0)) }
            return stops.count >= 2 ? stops : nil
        }
    }

    /// Encodes recents for persistence — the inverse of ``decodeRecents(_:)``.
    static func encodeRecents(_ recents: [[Color]]) -> String {
        recents.map { gradient in
            gradient.map { color in
                guard let c = color.rgbComponents else { return "000000" }
                return String(format: "%02X%02X%02X", c.red, c.green, c.blue)
            }.joined(separator: ",")
        }.joined(separator: ";")
    }
}
