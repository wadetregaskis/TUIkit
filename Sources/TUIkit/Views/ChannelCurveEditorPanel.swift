//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ChannelCurveEditorPanel.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitImage
import TUIkitStyling

// MARK: - Channel Curve Editor Panel

/// A modal editor for ``ASCIIToneCurve/Channels`` — the three per-channel
/// transfer functions a photo editor calls its Curves tabs.
///
/// ```
///  ● R   ◯ G   ◯ B
///
///                                  ▂▄▆█
///                          ▂▄▆████████
///                  ▂▄▆██████████████
///          ▂▄▆██████████████████
///  ▂▄▆██████████████████████
///      ▲              ▲          ▲
/// ```
///
/// The plot is the editor. A channel's curve is a function of one variable, so
/// it is drawn as one: input runs left to right, output bottom to top, and the
/// filled height at a column is what that input becomes. Eight rows of block
/// glyphs give eight sub-levels each — 64 steps, which is more than the eye
/// reads off a terminal cell grid anyway.
///
/// It is a FILL rather than a line because a cell grid draws a fill honestly
/// and a line badly: a one-cell-thick diagonal through a 36×8 grid is a
/// staircase with gaps in it, and the eye reads the gaps as the data.
///
/// - The **channel** buttons pick which of the three is being edited.
/// - The markers under the plot are the curve's control points; **◀** and **▶**
///   select one.
/// - **Input** moves the selected point along the horizontal axis and
///   **Output** along the vertical. The points stay sorted, so dragging one
///   past another reorders them and the selection follows the POINT.
/// - **+** adds a point halfway to the next one, at the value the ramp already
///   has there — so adding a point changes nothing until you move it.
/// - **−** removes the selected point, down to a floor of two: fewer cannot
///   define a function, and ``ASCIIToneCurve/Ramp`` treats such a ramp as
///   inert.
///
/// ## With a pointer
///
/// The plot is the editor with a mouse too. Pressing on it grabs the control
/// point under the pointer, or adds one there if the chart is empty at that
/// column — so clicking the tone you want to change and dragging it up or down
/// is one gesture rather than a trip to **+** and back. Dragging moves the
/// point in both axes at once: the column is its input, the row its output.
/// Eight rows means eight levels; the sliders are still the fine control.
///
/// The marker row is a handle strip rather than a canvas: a press there grabs
/// the nearest marker and does nothing if there is none, and the drag moves the
/// point along the input axis ALONE — "same level, different tone", which the
/// plot cannot give you because every cell of it names both.
///
/// What this can say that ``ToneCurveEditorPanel`` cannot is anything that
/// depends on the channel rather than the tone: a colour cast, a
/// cross-process, a split tone, a negative. What neither can say is a hue
/// rotation — that needs a three-dimensional table, and a cube of 35,937
/// entries is not something a terminal edits.
///
/// Every change writes straight through `channels`, so a live consumer updates
/// as you edit. **Done** keeps the result; **Cancel** — or any other dismissal,
/// `Esc` included — restores what the dialog opened with.
public struct ChannelCurveEditorPanel: View {
    private let title: String
    private let channels: Binding<ASCIIToneCurve.Channels>
    private let isPresented: Binding<Bool>

    /// Which channel is being edited.
    @State private var channel = Channel.red

    /// The index of the point being edited, in input order. Clamped on every
    /// read, so switching to a channel with fewer points can't strand it.
    @State private var selectedPoint = 0

    /// Which of the three is on the plot.
    enum Channel: Int, CaseIterable {
        case red, green, blue

        var label: String {
            switch self {
            case .red: return "R"
            case .green: return "G"
            case .blue: return "B"
            }
        }

        /// The channel's own colour, stated rather than themed: it identifies
        /// which channel you are looking at, and a theme that recoloured it
        /// would be answering a different question.
        var color: Color {
            switch self {
            case .red: return .rgb(255, 90, 90)
            case .green: return .rgb(90, 220, 130)
            case .blue: return .rgb(110, 165, 255)
            }
        }
    }

    /// The plot's width in cells, and its height in rows.
    ///
    /// Twice what it was. A curve editor is read by eye and dragged by hand,
    /// and at 36×8 both were cramped: a control point moved one cell in `x`
    /// jumped nearly 3% of the input range, and eight rows of nine fill states
    /// resolve 72 levels of output where sixteen resolve 144.
    ///
    /// The dialog that results is 78×29 at its natural size, which fits an
    /// 80-column terminal — but only while it does not also have to scroll,
    /// since a vertical scrollbar takes a column from the content and the plot
    /// is then elided by one at the right edge. Wider or 29 rows tall, whichever
    /// it gets, and it draws in full.
    static let plotWidth = 72
    static let plotHeight = 16

    /// Eight sub-levels of fill plus empty — one cell resolves nine states, so
    /// the eight rows resolve 64.
    static let fillGlyphs = [" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

    /// Creates a channel-curve editor with a localized title.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``. The title is not defaulted in this overload, or
    /// the two would be ambiguous where it is omitted.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the dialog title.
    ///   - channels: The three curves. Rewritten live on every change;
    ///     restored on Cancel / `Esc`.
    ///   - isPresented: Bound to the presenting `.modal`; Done and Cancel set
    ///     it false.
    public init(
        _ titleKey: LocalizedStringKey,
        channels: Binding<ASCIIToneCurve.Channels>,
        isPresented: Binding<Bool>
    ) {
        self.init(titleKey.localized, channels: channels, isPresented: isPresented)
    }

    /// Creates a channel-curve editor titled as written.
    ///
    /// Generic over `StringProtocol`, which is both SwiftUI's own spelling and
    /// what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey`` for why the concrete-`String` spelling does not.
    /// A generic parameter cannot carry a default, so the defaulted title lives
    /// in ``init(channels:isPresented:)`` instead of here.
    ///
    /// - Parameters:
    ///   - title: The dialog title.
    ///   - channels: The three curves. Rewritten live on every change;
    ///     restored on Cancel / `Esc`.
    ///   - isPresented: Bound to the presenting `.modal`; Done and Cancel set
    ///     it false.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S,
        channels: Binding<ASCIIToneCurve.Channels>,
        isPresented: Binding<Bool>
    ) {
        self.title = String(title)
        self.channels = channels
        self.isPresented = isPresented
    }

    /// Creates a channel-curve editor titled `"Channel curves"`.
    ///
    /// The title's default lives here rather than on either titled overload:
    /// neither of those can carry it — a generic parameter cannot have a
    /// default, and defaulting the ``LocalizedStringKey`` one would make the
    /// two ambiguous wherever the title is omitted. The forwarded default is
    /// written `as String` so it stays on the disfavoured side: a bare literal
    /// would bind to the key overload and go looking for a `"Channel curves"`
    /// key that is in no table.
    ///
    /// - Parameters:
    ///   - channels: The three curves. Rewritten live on every change;
    ///     restored on Cancel / `Esc`.
    ///   - isPresented: Bound to the presenting `.modal`; Done and Cancel set
    ///     it false.
    public init(
        channels: Binding<ASCIIToneCurve.Channels>,
        isPresented: Binding<Bool>
    ) {
        self.init("Channel curves" as String, channels: channels, isPresented: isPresented)
    }

    public var body: some View {
        _EditorPanelChrome(title: title, edited: channels, isPresented: isPresented) {
            VStack(alignment: .center, spacing: 0) {
                channelPicker
                Text(verbatim: "")
                plot
                markerRow
                Text(verbatim: "")
                axisRow("in ", value: inputBinding)
                axisRow("out", value: outputBinding)
                actionRow
            }
        }
    }

    // MARK: The plot

    private var channelPicker: some View {
        RadioButtonGroup(selection: $channel, orientation: .horizontal) {
            RadioButtonItem(Channel.red, Channel.red.label)
            RadioButtonItem(Channel.green, Channel.green.label)
            RadioButtonItem(Channel.blue, Channel.blue.label)
        }
    }

    /// The selected channel's ramp, drawn as a filled area.
    ///
    /// Built from an array of ROW STRINGS and looped over those, not over
    /// `0..<plotHeight`: an `Equatable` element wraps every row in the
    /// element-keyed render memo, which cannot see the ramp the row captured,
    /// so the plot would freeze at whatever it drew first.
    private var plot: some View {
        let color = channel.color
        // One per render, and the drag holds the one from the render it
        // started on: the dispatcher keeps calling the closure it captured at
        // the press until the release, so this box is exactly the gesture's
        // lifetime. `@State` would be wrong here — it is not part of the
        // picture and it must not survive the drag.
        let grab = Grab()
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(Self.plotRows(for: ramp).enumerated()), id: \.offset) { _, row in
                Text(verbatim: row).foregroundStyle(color)
            }
        }
        .onDragGesture { event in
            let column = min(Self.plotWidth - 1, max(0, event.x))
            let row = min(Self.plotHeight - 1, max(0, event.y))
            if event.phase == .began {
                // Grab what is under the pointer, or put a point there. Adding
                // on a press into empty chart is what a curve editor does, and
                // it is what makes "click the tone you want to change and drag
                // it" one gesture rather than a trip to the `+` button first.
                grab.point =
                    Self.point(in: ramp.points, near: column)
                    ?? addingPoint(atColumn: column, row: row)
            }
            guard let held = grab.point else { return }
            grab.point = moving(
                held, toInput: Self.input(atColumn: column), output: Self.output(atRow: row))
        }
    }

    /// `ramp` as ``plotHeight`` rows of ``plotWidth`` fill glyphs, top row
    /// first.
    ///
    /// A function rather than inline, because it is the panel's whole claim —
    /// filled height equals the value the ramp gives at that column — and a
    /// test that had to find these rows inside a bordered, centred dialog would
    /// be testing its own substring arithmetic.
    static func plotRows(for ramp: ASCIIToneCurve.Ramp) -> [String] {
        let values = (0..<plotWidth).map { ramp.value(at: input(atColumn: $0)) }
        return (0..<plotHeight).map { row in
            // Row 0 is the TOP, so it stands for the highest slice of the range.
            let floorOfRow = Double(plotHeight - row - 1) / Double(plotHeight)
            return values.map { value in
                let within = (value - floorOfRow) * Double(plotHeight)
                // `Int(clamping:)`: the ramp's points are whatever the binding
                // holds, and a point at `1e308` (or NaN) must plot as full
                // (or empty), not kill the editor the frame it opens.
                return fillGlyphs[min(8, max(0, Int(clamping: (within * 8).rounded())))]
            }
            .joined()
        }
    }

    /// A marker under each control point, the selected one in the accent.
    ///
    /// Over the CELLS for the same reason ``plot`` is over the rows.
    private var markerRow: some View {
        let points = ramp.points
        let selection = clampedSelection
        var owner: [Int: Int] = [:]
        for (index, point) in points.enumerated() {
            owner[Self.column(forInput: point.input)] = index
        }
        let cells: [Color?] = (0..<Self.plotWidth).map { column in
            guard let index = owner[column] else { return nil }
            return index == selection ? .palette.accent : .palette.foregroundTertiary
        }
        let grab = Grab()
        return HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, color in
                if let color {
                    Text(verbatim: TerminalSymbols.toneCurveStop).foregroundStyle(color)
                } else {
                    Text(verbatim: " ")
                }
            }
        }
        .onDragGesture { event in
            let column = min(Self.plotWidth - 1, max(0, event.x))
            // The markers are handles, not a canvas: a press that lands on
            // nothing does nothing, where the same press on the plot would add
            // a point. And the drag moves the point along ONE axis, because
            // this row has only one — which is the gesture for "same level,
            // different tone" that the plot cannot give you.
            if event.phase == .began { grab.point = Self.point(in: ramp.points, near: column) }
            guard let held = grab.point else { return }
            grab.point = moving(held, toInput: Self.input(atColumn: column), output: nil)
        }
    }

    /// One labelled 0…100% slider — the two axes of the selected point.
    private func axisRow(_ caption: String, value: Binding<Double>) -> some View {
        HStack(spacing: 1) {
            Text(verbatim: caption).dim()
            // No `.frame(maxWidth: .infinity)`: this dialog hugs its content,
            // and a width-flexible child would stretch it to the screen.
            Slider(value: value, in: 0...1, step: 0.01)
                .sliderShowsValue(false)
                .frame(width: 22)
            Text(verbatim: "\(Int((value.wrappedValue * 100).rounded()))%").dim()
        }
    }

    private var actionRow: some View {
        let points = ramp.points
        let selection = clampedSelection
        return HStack(spacing: 1) {
            Button("+") {
                let (updated, index) = Self.adding(to: points, after: selection)
                write(ASCIIToneCurve.Ramp(updated))
                selectedPoint = index
            }
            Button("−") {
                var updated = points
                updated.remove(at: selection)
                write(ASCIIToneCurve.Ramp(updated))
                selectedPoint = max(0, selection - 1)
            }
            .disabled(points.count <= 2)
            Button("◀") { selectedPoint = selection - 1 }
                .disabled(selection == 0)
            Button("▶") { selectedPoint = selection + 1 }
                .disabled(selection >= points.count - 1)
        }
    }

    // MARK: The pointer

    /// The point a drag is holding, from the press to the release.
    ///
    /// A reference box rather than `@State` because it is the GESTURE's state,
    /// not the view's: the closure the dispatcher captured at the press keeps
    /// being called until the release, so the box it captured is alive for
    /// exactly as long as the drag and is gone afterwards.
    private final class Grab {
        var point: ASCIIToneCurve.Ramp.Point?
    }

    /// How far from a control point a press still counts as grabbing it.
    ///
    /// Two cells either side. A marker is one cell wide and a terminal pointer
    /// lands on whole cells, so the target has to be bigger than the mark or
    /// the only way to grab a point is to hit it exactly.
    static let grabRadius = 2

    /// The output a plot row stands for — the top row is `1`, the bottom `0`.
    ///
    /// Eight rows, so a drag resolves eight levels: this is the coarse control
    /// and the sliders underneath are the fine one. Mapping to each row's
    /// CENTRE instead would be finer in the middle and put both extremes out
    /// of reach, and a curve editor you cannot drag to black is not one.
    static func output(atRow row: Int) -> Double {
        plotHeight > 1 ? Double(plotHeight - 1 - row) / Double(plotHeight - 1) : 0
    }

    /// The point nearest `column`, if any is within ``grabRadius`` of it.
    static func point(in points: [ASCIIToneCurve.Ramp.Point], near column: Int)
        -> ASCIIToneCurve.Ramp.Point?
    {
        points
            .map { (point: $0, distance: abs(Self.column(forInput: $0.input) - column)) }
            .filter { $0.distance <= grabRadius }
            .min { $0.distance < $1.distance }?
            .point
    }

    /// Adds a point where the pointer pressed and returns it, selected.
    private func addingPoint(atColumn column: Int, row: Int) -> ASCIIToneCurve.Ramp.Point {
        let added = ASCIIToneCurve.Ramp.Point(
            input: Self.input(atColumn: column), output: Self.output(atRow: row))
        let updated = ASCIIToneCurve.Ramp(ramp.points + [added])
        write(updated)
        selectedPoint = updated.points.firstIndex(of: added) ?? 0
        return added
    }

    /// Moves `point`, and returns where it ended up.
    ///
    /// Found by VALUE and returned by value, because the ramp re-sorts: a drag
    /// past a neighbour changes the point's index, and an index remembered
    /// across that would go on moving whichever point had taken the slot. A
    /// `nil` output leaves the point's level alone, which is what the marker
    /// row's one-dimensional drag wants.
    @discardableResult
    private func moving(
        _ point: ASCIIToneCurve.Ramp.Point, toInput input: Double, output: Double?
    ) -> ASCIIToneCurve.Ramp.Point {
        var points = ramp.points
        guard let index = points.firstIndex(of: point) else { return point }
        let moved = ASCIIToneCurve.Ramp.Point(input: input, output: output ?? point.output)
        points[index] = moved
        let updated = ASCIIToneCurve.Ramp(points)
        write(updated)
        selectedPoint = updated.points.firstIndex(of: moved) ?? index
        return moved
    }

    // MARK: Bindings

    /// The ramp currently being edited.
    private var ramp: ASCIIToneCurve.Ramp {
        switch channel {
        case .red: return channels.wrappedValue.red
        case .green: return channels.wrappedValue.green
        case .blue: return channels.wrappedValue.blue
        }
    }

    /// Writes `ramp` back to the channel being edited, leaving the other two.
    private func write(_ ramp: ASCIIToneCurve.Ramp) {
        let current = channels.wrappedValue
        channels.wrappedValue =
            switch channel {
            case .red: .init(red: ramp, green: current.green, blue: current.blue)
            case .green: .init(red: current.red, green: ramp, blue: current.blue)
            case .blue: .init(red: current.red, green: current.green, blue: ramp)
            }
    }

    private var clampedSelection: Int {
        min(max(0, selectedPoint), max(0, ramp.points.count - 1))
    }

    /// The selected point's input, which re-sorts the ramp as it moves — so the
    /// selection follows the POINT past its neighbours rather than staying in
    /// the slot the point left.
    private var inputBinding: Binding<Double> {
        Binding(
            get: { ramp.points.isEmpty ? 0 : ramp.points[clampedSelection].input },
            set: { newInput in
                var points = ramp.points
                guard !points.isEmpty else { return }
                let index = clampedSelection
                let moved = ASCIIToneCurve.Ramp.Point(
                    input: newInput, output: points[index].output)
                points[index] = moved
                let updated = ASCIIToneCurve.Ramp(points)
                write(updated)
                selectedPoint = updated.points.firstIndex(of: moved) ?? index
            })
    }

    private var outputBinding: Binding<Double> {
        Binding(
            get: { ramp.points.isEmpty ? 0 : ramp.points[clampedSelection].output },
            set: { newOutput in
                var points = ramp.points
                guard !points.isEmpty else { return }
                let index = clampedSelection
                points[index] = ASCIIToneCurve.Ramp.Point(
                    input: points[index].input, output: newOutput)
                write(ASCIIToneCurve.Ramp(points))
            })
    }

    // MARK: Internals

    /// The input a plot column stands for: `0` at the left edge, `1` at the
    /// right, so the plot and the markers agree.
    static func input(atColumn column: Int) -> Double {
        plotWidth > 1 ? Double(column) / Double(plotWidth - 1) : 0
    }

    /// The inverse of ``input(atColumn:)``, clamped into the plot.
    static func column(forInput input: Double) -> Int {
        min(plotWidth - 1, max(0, Int((input * Double(plotWidth - 1)).rounded())))
    }

    /// `points` with one added beside the point at `index`, at the value the
    /// ramp already has where it lands — so adding one changes nothing until
    /// you move it, and a curve can be refined rather than restarted.
    ///
    /// Halfway to the next point where there is room, and halfway back to the
    /// previous one where there is not, for the reason
    /// ``ToneCurveEditorPanel/adding(to:after:)`` gives: the last point is
    /// almost always at the far end, and "+" there must not stack a second one
    /// on top of it.
    static func adding(to points: [ASCIIToneCurve.Ramp.Point], after index: Int) -> (
        points: [ASCIIToneCurve.Ramp.Point], index: Int
    ) {
        guard !points.isEmpty else {
            return ([ASCIIToneCurve.Ramp.Point(input: 0, output: 0)], 0)
        }
        let at = min(max(0, index), points.count - 1)
        let here = points[at].input
        let next = at + 1 < points.count ? points[at + 1].input : 1
        let previous = at > 0 ? points[at - 1].input : 0
        let landing =
            if here < next {
                (here + next) / 2
            } else if previous < here {
                (previous + here) / 2
            } else {
                here / 2
            }
        let added = ASCIIToneCurve.Ramp.Point(
            input: landing, output: ASCIIToneCurve.Ramp(points).value(at: landing))
        let updated = ASCIIToneCurve.Ramp(points + [added]).points
        return (updated, updated.firstIndex(of: added) ?? at)
    }
}
