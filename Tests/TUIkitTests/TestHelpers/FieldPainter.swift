//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FieldPainter.swift
//
//  Every kind of container that paints a field under content it did not draw,
//  as one list a suite can walk: a `.background` (flat, around padding and a
//  border, nested, a ramp), compositing (a `ZStack`, an `.overlay`, each over
//  one colour and over stripes of several), a `List`
//  row's fill and a tab's surface. They do not all agree about what is under a
//  cell — a stated `ESC[49m` is the case they split on — so a property that has
//  to hold "inside any container" is held inside each of these.
//
//  Created by Wade Tregaskis
//  License: MIT

@testable import TUIkit

/// Alternating rows, so a list paints a still fill of its own under a row that is
/// neither selected nor under the cursor.
private struct ZebraListStyle: ListStyle {
    var alternatingRowColors: Bool { true }
    var showsBorder: Bool { false }
    var rowPadding: EdgeInsets { EdgeInsets(all: 0) }
}

/// Every kind of painter a view can sit inside.
enum FieldPainter: String, CaseIterable, Sendable {
    /// Nothing but the page.
    case none
    /// A flat `.background`.
    case background
    /// A `.background` outside padding and a border: what is under the probe
    /// is the fill, however far out it was painted.
    case backgroundAroundPadding
    /// Two backgrounds: the inner one is what the probe sits on.
    case nestedBackgrounds
    /// A ramp across the row, a different entry under each cell.
    case horizontalRamp
    /// A `ZStack` over a colour: compositing paints the overlay over it.
    case zStackOverColour
    /// An `.overlay` on a view with a background.
    case overlayOnFill
    /// A `ZStack` over stripes — a colour, another, and no field, in turn — so
    /// no two neighbouring cells of the probe sit on one field: compositing
    /// paints each over the field under its own column.
    case zStackOverStripes
    /// An `.overlay` on the same stripes.
    case overlayOnStripes
    /// A row of a `List` that paints a fill of its own.
    case listRowFill
    /// A tab's surface, from `TabView`.
    case tabSurface

    /// `probe` inside this painter.
    @MainActor @ViewBuilder
    func view(_ probe: some View) -> some View {
        switch self {
        case .none:
            probe
        case .background:
            probe.background(Color.rgb(200, 40, 40))
        case .backgroundAroundPadding:
            probe.padding(1).border().background(Color.rgb(40, 40, 200))
        case .nestedBackgrounds:
            HStack(spacing: 0) {
                probe
                Text(" ")
                probe.background(Color.rgb(200, 40, 40))
            }
            .background(Color.rgb(40, 40, 200))
        case .horizontalRamp:
            HStack(spacing: 0) { Text("    "); probe; Text("    ") }
                .background(
                    LinearGradient(
                        colors: [Color.rgb(200, 40, 40), Color.rgb(40, 40, 200)],
                        startPoint: .leading, endPoint: .trailing))
        case .zStackOverColour:
            ZStack { Color.rgb(40, 160, 40).frame(width: 6, height: 1); probe }
        case .overlayOnFill:
            Text("      ").background(Color.rgb(40, 160, 40)).overlay { probe }
        case .zStackOverStripes:
            ZStack { Self.stripes; probe }
        case .overlayOnStripes:
            Self.stripes.overlay { probe }
        case .listRowFill:
            List(selection: .constant(Int?.none)) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 0) { Text("row \(row) "); probe }
                }
            }
            .listStyle(ZebraListStyle())
            .frame(height: 3)
        case .tabSurface:
            TabView(selection: .constant(0)) {
                Tab("One", value: 0) { probe }
                Tab("Two", value: 1) { Text("two") }
            }
            .tabViewStyle(.bordered)
        }
    }

    /// Twelve cells in one row: red, blue and no field, four times over.
    @MainActor
    private static var stripes: some View {
        HStack(spacing: 0) {
            ForEach(0..<12, id: \.self) { column in stripe(column) }
        }
    }

    /// The stripe at `column`.
    @MainActor @ViewBuilder
    private static func stripe(_ column: Int) -> some View {
        switch column % 3 {
        case 0: Color.rgb(200, 40, 40).frame(width: 1, height: 1)
        case 1: Color.rgb(40, 40, 200).frame(width: 1, height: 1)
        default: Text(" ")
        }
    }
}
