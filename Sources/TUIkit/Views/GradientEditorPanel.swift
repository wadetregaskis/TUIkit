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
/// its swatch), the action row inserts / removes / reorders stops, and an
/// embedded colour panel — the same preview-plus-tabs body ``ColorPickerPanel``
/// wraps — edits the selected stop in place, rather than nesting a second
/// dialog. Every change writes straight through `stops`, so a live consumer
/// updates as you edit. "Done" (or `Esc`) dismisses via `isPresented`.
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

    /// The preview strip's width in cells.
    private static let previewWidth = 36

    /// Creates a gradient-editor panel over a colour-stop binding.
    ///
    /// - Parameters:
    ///   - title: The dialog title (default `"Gradient"`).
    ///   - stops: The gradient's colour stops, evenly spaced. Rewritten live
    ///     on every change.
    ///   - isPresented: Bound to the presenting `.modal`; "Done" sets it false.
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
        Dialog(title: title, titleColor: .palette.accent, footerAlignment: .center) {
            VStack(alignment: .center, spacing: 1) {
                previewStrip
                stopStrip
                actionRow
                _ColorPickerBody(selection: selectedStopBinding)
            }
        } footer: {
            // No leading Spacer (it is width-flexible and would stretch the
            // dialog); the footer sizes to the button, the dialog to its tabs.
            Button("Done") { isPresented.wrappedValue = false }
                .buttonStyle(.primary)
        }
    }

    // MARK: Preview

    /// The gradient rendered across a fixed strip with the SAME interpolation
    /// every gradient consumer uses, one cell per sample, two rows tall.
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
            ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: 0) {
                    // Glyph AND background in the colour, like the colour
                    // panel's swatch: solid in terminals that don't paint
                    // behind spaces, gap-free where the font leaves hairlines.
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, color in
                        Text("█").foregroundStyle(color).background(color)
                    }
                }
            }
        }
    }

    // MARK: Stop strip

    /// One numbered swatch button per stop; the selected one is marked and
    /// uses the primary style (the same affordance as the semantic tab's rows).
    private var stopStrip: some View {
        HStack(spacing: 1) {
            ForEach(Array(stops.wrappedValue.enumerated()), id: \.offset) { index, color in
                HStack(spacing: 0) {
                    Text("██").foregroundStyle(color)
                    if index == clampedSelection {
                        Button("●\(index + 1)") { selectedStop = index }.buttonStyle(.primary)
                    } else {
                        Button(" \(index + 1)") { selectedStop = index }.buttonStyle(.plain)
                    }
                }
            }
        }
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
