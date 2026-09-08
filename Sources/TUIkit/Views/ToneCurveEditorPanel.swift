//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToneCurveEditorPanel.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitImage
import TUIkitStyling

// MARK: - Tone Curve Editor Panel

/// A modal editor for an ``ASCIIToneCurve`` — the "this tone becomes that
/// colour" mapping ``View/imageToneCurve(_:)`` applies to an ``Image``.
///
/// ```
///  in  ████████████████████████████████████
///        ▲          ▲                  ▲
///  out ████████████████████████████████████
///      ████████████████████████████████████
/// ```
///
/// The two strips are the whole design, and they are read **column by
/// column**: the top one is the tone arriving at that column, the bottom one
/// is the colour leaving it. The markers between them are the curve's stops —
/// the tones you have named a colour for — and everything between two of them
/// is interpolated, which is what the strip below shows you.
///
/// That is what distinguishes this from ``GradientEditorPanel``, which is the
/// nearer-looking of the two. A gradient is a list of colours at even
/// intervals; a curve is a list of colours at tones you choose, and moving a
/// stop is the edit a gradient cannot express. Two stops make a duotone; more
/// make a gradient map.
///
/// - The **stop strip** selects a stop; so do **◀** and **▶**.
/// - **Position** moves the selected stop along the tone axis. The list stays
///   sorted, so dragging one stop past another reorders them and the selection
///   follows the stop rather than the slot.
/// - **+** adds a stop halfway to the next one, coloured with what the curve
///   already produces there — so adding a stop changes nothing until you edit
///   it, which is the only behaviour that lets you refine a curve rather than
///   restart it.
/// - **−** removes the selected stop, down to a floor of two: fewer cannot
///   define a mapping, and ``ASCIIToneCurve`` treats such a curve as inert.
/// - The embedded colour panel edits what the selected stop becomes.
///
/// With a pointer, the diagram itself is the tone axis: pressing on any of its
/// four rows grabs the stop under the pointer, or adds one there — coloured
/// with what the curve already produces at that tone, exactly as **+** does, so
/// the press changes nothing and the drag that follows is the whole edit.
/// Dragging moves the stop along the axis, past its neighbours if you take it
/// that far. All four rows, because they are four readings of the same axis and
/// a marker is a single cell to aim at.
///
/// Every change writes straight through `stops`, so a live consumer updates as
/// you edit. **Done** keeps the result; **Cancel** — or any other dismissal,
/// `Esc` included — restores the stops the dialog opened with.
///
/// Present it like the other panels (TUIkit modals are page-hosted):
///
/// ```swift
/// @State private var stops: [ASCIIToneCurve.Stop] = [
///     .init(at: 0, to: .rgb(10, 10, 40)),
///     .init(at: 1, to: .rgb(255, 250, 220)),
/// ]
/// @State private var editing = false
///
/// PageRoot {
///     Button("Edit curve…") { editing = true }
/// }
/// .modal(isPresented: $editing) {
///     ToneCurveEditorPanel(stops: $stops, isPresented: $editing)
/// }
/// ```
///
/// - Note: A stop's `from` is written as the GREY of its position. That is not
///   a loss — a curve is a function of luminance alone, so only the tone of
///   `from` was ever read — and it is the one spelling that says so. See
///   ``ASCIIToneCurve/Stop/position``.
public struct ToneCurveEditorPanel: View {
    private let title: String
    private let stops: Binding<[ASCIIToneCurve.Stop]>
    private let isPresented: Binding<Bool>

    /// The index of the stop being edited, in position order. Clamped on every
    /// read, so external shrinking of `stops` can't strand it.
    @State private var selectedStop = 0

    /// The strips' width in cells. ``GradientEditorPanel``'s, deliberately:
    /// the stop strip is laid out by that panel's own row-wrapping helper, and
    /// two budgets would let the chips and their preview disagree.
    static let stripWidth = 36

    /// The gutter the `in` / `out` captions sit in, left of the strips.
    private static let gutter = 4

    /// Creates a tone-curve editor with a localized title.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``. The title is not defaulted in this overload, or
    /// the two would be ambiguous where it is omitted.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the dialog title.
    ///   - stops: The curve's stops. Rewritten live on every change — always
    ///     in position order — and restored on Cancel / `Esc`.
    ///   - isPresented: Bound to the presenting `.modal`; Done and Cancel set
    ///     it false.
    public init(
        _ titleKey: LocalizedStringKey,
        stops: Binding<[ASCIIToneCurve.Stop]>,
        isPresented: Binding<Bool>
    ) {
        self.init(titleKey.localized, stops: stops, isPresented: isPresented)
    }

    /// Creates a tone-curve editor titled as written.
    ///
    /// Generic over `StringProtocol`, which is both SwiftUI's own spelling and
    /// what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey`` for why the concrete-`String` spelling does not.
    /// A generic parameter cannot carry a default, so the defaulted title lives
    /// in ``init(stops:isPresented:)`` instead of here.
    ///
    /// - Parameters:
    ///   - title: The dialog title.
    ///   - stops: The curve's stops. Rewritten live on every change — always
    ///     in position order — and restored on Cancel / `Esc`.
    ///   - isPresented: Bound to the presenting `.modal`; Done and Cancel set
    ///     it false.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S,
        stops: Binding<[ASCIIToneCurve.Stop]>,
        isPresented: Binding<Bool>
    ) {
        self.title = String(title)
        self.stops = stops
        self.isPresented = isPresented
    }

    /// Creates a tone-curve editor titled `"Tone curve"`.
    ///
    /// The title's default lives here rather than on either titled overload:
    /// neither of those can carry it — a generic parameter cannot have a
    /// default, and defaulting the ``LocalizedStringKey`` one would make the
    /// two ambiguous wherever the title is omitted. The forwarded default is
    /// written `as String` so it stays on the disfavoured side: a bare literal
    /// would bind to the key overload and go looking for a `"Tone curve"` key
    /// that is in no table.
    ///
    /// - Parameters:
    ///   - stops: The curve's stops. Rewritten live on every change — always
    ///     in position order — and restored on Cancel / `Esc`.
    ///   - isPresented: Bound to the presenting `.modal`; Done and Cancel set
    ///     it false.
    public init(
        stops: Binding<[ASCIIToneCurve.Stop]>,
        isPresented: Binding<Bool>
    ) {
        self.init("Tone curve" as String, stops: stops, isPresented: isPresented)
    }

    public var body: some View {
        _EditorPanelChrome(title: title, edited: stops, isPresented: isPresented) {
            VStack(alignment: .center, spacing: 0) {
                mappingDiagram
                Text(verbatim: "")
                stopStrip
                actionRow
                positionRow
                // A rule between the curve above and the colour editor below,
                // fixed at the strip's width: an unconstrained Divider is
                // width-flexible, which would stretch this content-hugging
                // dialog to the whole screen.
                Divider().frame(width: Self.stripWidth + Self.gutter)
                _ColorPickerBody(selection: selectedColorBinding)
            }
        }
    }

    // MARK: The mapping

    /// The tones going in, where the stops sit, and the colours coming out.
    private var mappingDiagram: some View {
        let curve = ASCIIToneCurve(ordered)
        let inputs = (0..<Self.stripWidth).map { column -> Color in
            let level = UInt8(clamping: Int((Self.tone(atColumn: column) * 255).rounded()))
            return .rgb(level, level, level)
        }
        // Straight through the curve, cell by cell, WITHOUT the monotone
        // repair `Color.quantisedRamp` does for gradients: a curve's output is
        // not required to be monotone (a stop list may run bright, dark,
        // bright), and a preview that banded differently from the picture
        // beside it would be worse than one that bands with it.
        let outputs = (0..<Self.stripWidth).map { curve.color(atTone: Self.tone(atColumn: $0)) }
        // One per render, and the drag holds the one from the render it
        // started on: the dispatcher keeps calling the closure it captured at
        // the press until the release, so this box is exactly the gesture's
        // lifetime.
        let grab = Grab()
        return VStack(alignment: .leading, spacing: 0) {
            strip(caption: "in", cells: inputs)
            markerRow
            strip(caption: "out", cells: outputs)
            strip(caption: "", cells: outputs)
        }
        .onDragGesture { event in
            // The whole diagram is the tone axis — all four rows, because
            // they are four readings of the same one and a marker is a single
            // cell to aim at. The gutter is not: `in` and `out` are captions.
            let column = min(Self.stripWidth - 1, max(0, event.x - Self.gutter))
            guard event.x >= Self.gutter else { return }
            if event.phase == .began {
                // Grab the stop under the pointer, or put one there — coloured
                // with what the curve already produces at that tone, exactly as
                // "+" does, so a press adds a stop without changing the
                // picture and the drag that follows is the whole edit.
                grab.stop =
                    Self.stop(in: ordered, near: column) ?? addingStop(atColumn: column)
            }
            guard let held = grab.stop else { return }
            grab.stop = moving(held, toTone: Self.tone(atColumn: column))
        }
    }

    /// One captioned row of per-cell coloured blocks. Glyph AND background in
    /// the colour, like the colour panel's swatch: solid in terminals that
    /// don't paint behind spaces, gap-free where the font leaves hairlines.
    private func strip(caption: String, cells: [Color]) -> some View {
        HStack(spacing: 0) {
            Text(verbatim: caption)
                .dim()
                .frame(width: Self.gutter, alignment: .leading)
            ForEach(Array(cells.enumerated()), id: \.offset) { _, color in
                Text(verbatim: "█").foregroundStyle(color).background(color)
            }
        }
    }

    /// A marker under each stop's position, the selected one in the accent.
    ///
    /// Over the CELLS rather than over `0..<stripWidth`, and each cell carries
    /// the colour it draws: an `Equatable` element — a bare column index —
    /// wraps every cell in the element-keyed render memo, which cannot see
    /// which stops the loop captured from outside itself, so the row freezes
    /// at whatever it drew first. `GradientEditorPanel`'s preview shipped that
    /// bug once; this one had it for the length of one commit.
    private var markerRow: some View {
        let list = ordered
        let selection = clampedSelection
        var owner: [Int: Int] = [:]
        for (index, stop) in list.enumerated() {
            // Later stops win a shared cell, which is only reachable when two
            // sit within one cell of each other; the ◀ ▶ buttons still select
            // the one the marker is hiding.
            owner[Self.column(forTone: Self.position(of: stop))] = index
        }
        let cells: [Color?] = (0..<Self.stripWidth).map { column in
            guard let index = owner[column] else { return nil }
            return index == selection ? .palette.accent : .palette.foregroundTertiary
        }
        return HStack(spacing: 0) {
            Text(verbatim: "").frame(width: Self.gutter, alignment: .leading)
            ForEach(Array(cells.enumerated()), id: \.offset) { _, color in
                if let color {
                    Text(verbatim: TerminalSymbols.toneCurveStop).foregroundStyle(color)
                } else {
                    Text(verbatim: " ")
                }
            }
        }
    }

    // MARK: Stops

    /// One bare 3-cell swatch per stop, in position order, wrapped onto as many
    /// rows as the strip width allows.
    private var stopStrip: some View {
        let list = ordered
        let selection = clampedSelection
        let rows = GradientEditorPanel.chipRows(count: list.count)
        return VStack(alignment: .center, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 1) {
                    ForEach(row, id: \.self) { index in
                        Button("") { selectedStop = index }
                            .buttonStyle(
                                _ColorSwatchButtonStyle(
                                    color: list[index].to, isSelected: index == selection))
                    }
                }
            }
        }
    }

    /// Add / remove / select-previous / select-next.
    private var actionRow: some View {
        let list = ordered
        let selection = clampedSelection
        return HStack(spacing: 1) {
            Button("+") {
                let (updated, selected) = Self.adding(to: list, after: selection)
                stops.wrappedValue = updated
                selectedStop = selected
            }
            Button("−") {
                var updated = list
                updated.remove(at: selection)
                stops.wrappedValue = updated
                selectedStop = max(0, selection - 1)
            }
            .disabled(list.count <= 2)
            Button("◀") { selectedStop = selection - 1 }
                .disabled(selection == 0)
            Button("▶") { selectedStop = selection + 1 }
                .disabled(selection >= list.count - 1)
        }
    }

    /// Where the selected stop sits on the tone axis.
    private var positionRow: some View {
        let percent = Int((Self.position(of: ordered[clampedSelection]) * 100).rounded())
        return HStack(spacing: 1) {
            Text(LocalizationService.shared.string(for: LocalizationKey.Label.position)).dim()
            // No `.frame(maxWidth: .infinity)`: this dialog hugs its content,
            // and a width-flexible child would stretch it to the screen.
            Slider(value: positionBinding, in: 0...1, step: 0.01)
                .sliderShowsValue(false)
                .frame(width: 20)
            Text(verbatim: "\(percent)%").dim()
        }
    }

    // MARK: The pointer

    /// The stop a drag is holding, from the press to the release.
    ///
    /// A reference box rather than `@State` because it is the GESTURE's state,
    /// not the view's: the closure the dispatcher captured at the press keeps
    /// being called until the release, so the box it captured is alive for
    /// exactly as long as the drag and is gone afterwards.
    private final class Grab {
        var stop: ASCIIToneCurve.Stop?
    }

    /// How far from a stop a press still counts as grabbing it.
    ///
    /// Two cells either side. A marker is one cell wide and a terminal pointer
    /// lands on whole cells, so the target has to be bigger than the mark or
    /// the only way to grab a stop is to hit it exactly.
    static let grabRadius = 2

    /// The stop nearest `column`, if any is within ``grabRadius`` of it.
    static func stop(in list: [ASCIIToneCurve.Stop], near column: Int) -> ASCIIToneCurve.Stop? {
        list
            .map { (stop: $0, distance: abs(Self.column(forTone: Self.position(of: $0)) - column)) }
            .filter { $0.distance <= grabRadius }
            .min { $0.distance < $1.distance }?
            .stop
    }

    /// Adds a stop where the pointer pressed and returns it, selected.
    private func addingStop(atColumn column: Int) -> ASCIIToneCurve.Stop {
        let list = ordered
        let tone = Self.tone(atColumn: column)
        let added = ASCIIToneCurve.Stop(at: tone, to: ASCIIToneCurve(list).color(atTone: tone))
        let updated = Self.sorted(list + [added])
        stops.wrappedValue = updated
        selectedStop = updated.firstIndex(of: added) ?? 0
        return added
    }

    /// Moves `stop` along the tone axis, and returns where it ended up.
    ///
    /// Found by VALUE and returned by value, because the list re-sorts: a drag
    /// past a neighbour changes the stop's index, and an index remembered
    /// across that would go on moving whichever stop had taken the slot.
    @discardableResult
    private func moving(_ stop: ASCIIToneCurve.Stop, toTone tone: Double) -> ASCIIToneCurve.Stop {
        var list = ordered
        guard let index = list.firstIndex(of: stop) else { return stop }
        let moved = ASCIIToneCurve.Stop(at: tone, to: list[index].to)
        list[index] = moved
        let sorted = Self.sorted(list)
        stops.wrappedValue = sorted
        selectedStop = sorted.firstIndex(of: moved) ?? index
        return moved
    }

    // MARK: Bindings

    /// The stops in position order — the order the curve evaluates them in, and
    /// the only order in which "the stop after this one" means anything.
    private var ordered: [ASCIIToneCurve.Stop] { Self.sorted(stops.wrappedValue) }

    private var clampedSelection: Int {
        min(max(0, selectedStop), max(0, stops.wrappedValue.count - 1))
    }

    /// The selected stop's OUTPUT colour, for the embedded colour panel.
    private var selectedColorBinding: Binding<Color> {
        Binding(
            get: { ordered[clampedSelection].to },
            set: { newColor in
                var list = ordered
                let index = clampedSelection
                list[index] = ASCIIToneCurve.Stop(from: list[index].from, to: newColor)
                stops.wrappedValue = list
            })
    }

    /// The selected stop's position, which re-sorts the list as it moves — so
    /// the selection follows the STOP past its neighbours rather than staying
    /// in the slot the stop left.
    private var positionBinding: Binding<Double> {
        Binding(
            get: { Self.position(of: ordered[clampedSelection]) },
            set: { newPosition in
                var list = ordered
                let index = clampedSelection
                let moved = ASCIIToneCurve.Stop(at: newPosition, to: list[index].to)
                list[index] = moved
                let sorted = Self.sorted(list)
                stops.wrappedValue = sorted
                // Identity by position AND colour: two stops of the same colour
                // at the same tone are indistinguishable, and either answer is
                // then correct.
                selectedStop = sorted.firstIndex(of: moved) ?? index
            })
    }

    // MARK: Internals

    /// The tone a strip column stands for: `0` at the left edge, `1` at the
    /// right, so the two strips and the markers all agree.
    static func tone(atColumn column: Int) -> Double {
        stripWidth > 1 ? Double(column) / Double(stripWidth - 1) : 0
    }

    /// The inverse of ``tone(atColumn:)``, clamped into the strip.
    static func column(forTone tone: Double) -> Int {
        min(stripWidth - 1, max(0, Int((tone * Double(stripWidth - 1)).rounded())))
    }

    /// A stop's position, reading an unresolved semantic `from` as black — it
    /// has no tone until a palette resolves it, and the editor has to draw
    /// something.
    static func position(of stop: ASCIIToneCurve.Stop) -> Double { stop.position ?? 0 }

    /// `list` in position order. A stable sort, so two stops at the same tone
    /// keep the order they were written in.
    static func sorted(_ list: [ASCIIToneCurve.Stop]) -> [ASCIIToneCurve.Stop] {
        list.enumerated()
            .sorted {
                let left = position(of: $0.element)
                let right = position(of: $1.element)
                return left == right ? $0.offset < $1.offset : left < right
            }
            .map(\.element)
    }

    /// `list` with a stop added beside the one at `index`, coloured with what
    /// the curve already produces where it lands.
    ///
    /// That colour is the whole point: a stop added this way changes nothing,
    /// so a curve can be refined rather than restarted.
    ///
    /// Halfway to the NEXT stop where there is room, and halfway back to the
    /// previous one where there is not — which is the case that matters,
    /// because the last stop is almost always at white and "+" on it would
    /// otherwise land a second stop on top of it and appear to do nothing.
    static func adding(to list: [ASCIIToneCurve.Stop], after index: Int) -> (
        list: [ASCIIToneCurve.Stop], index: Int
    ) {
        guard !list.isEmpty else {
            return ([ASCIIToneCurve.Stop(at: 0, to: .rgb(0, 0, 0))], 0)
        }
        let at = min(max(0, index), list.count - 1)
        let here = position(of: list[at])
        let next = at + 1 < list.count ? position(of: list[at + 1]) : 1
        let previous = at > 0 ? position(of: list[at - 1]) : 0
        let landing =
            if here < next {
                (here + next) / 2
            } else if previous < here {
                (previous + here) / 2
            } else {
                here / 2  // one stop, already at the top: halfway back to black
            }
        let added = ASCIIToneCurve.Stop(at: landing, to: ASCIIToneCurve(list).color(atTone: landing))
        let updated = sorted(list + [added])
        return (updated, updated.firstIndex(of: added) ?? at)
    }
}
