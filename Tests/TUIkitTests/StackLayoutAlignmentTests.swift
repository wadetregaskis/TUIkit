//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StackLayoutAlignmentTests.swift
//
//  The `Layout`-protocol stacks resolve alignment through the guide rather than
//  through a switch over the three named cases. A switch cannot express a
//  CUSTOM guide — the one kind of alignment whose entire purpose is to sit
//  where those cases cannot — and each of the three had a `default` that sent
//  every unnamed alignment to the centre.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// A guide a quarter of the way across, which no named case can reach.
private struct QuarterH: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> Double {
        Double(context.width) / 4
    }
}

/// A guide a quarter of the way down.
private struct QuarterV: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> Double {
        Double(context.height) / 4
    }
}

extension HorizontalAlignment {
    fileprivate static let quarter = HorizontalAlignment(QuarterH.self)
}

extension VerticalAlignment {
    fileprivate static let quarter = VerticalAlignment(QuarterV.self)
}

@MainActor
@Suite("Layout-protocol stacks honour custom alignment guides")
struct StackLayoutAlignmentTests {

    @Test("A custom horizontal guide is not rounded off to centre")
    func vstackHonoursCustomGuide() {
        // A 40-wide stack placing a 4-wide child: the guide puts the stack's
        // point at 10 and the child's at 1, so the child starts at 9. Centre
        // would be 18, which is what the switch's `default` produced.
        #expect(HorizontalAlignment.quarter.childOffset(childWidth: 4, in: 40) == 9)
        #expect(HorizontalAlignment.center.childOffset(childWidth: 4, in: 40) == 18)
    }

    @Test("A custom vertical guide is not rounded off to centre")
    func hstackHonoursCustomGuide() {
        #expect(VerticalAlignment.quarter.childOffset(childHeight: 4, in: 40) == 9)
        #expect(VerticalAlignment.center.childOffset(childHeight: 4, in: 40) == 18)
    }

    @Test("The named cases still land where they always did")
    func namedCasesUnchanged() {
        // The switch these replaced was right about its three cases, so the
        // replacement has to agree with it exactly — including the clamp for a
        // child wider than the space it is being placed in.
        #expect(HorizontalAlignment.leading.childOffset(childWidth: 4, in: 40) == 0)
        #expect(HorizontalAlignment.trailing.childOffset(childWidth: 4, in: 40) == 36)
        #expect(HorizontalAlignment.leading.childOffset(childWidth: 50, in: 40) == 0)
        #expect(HorizontalAlignment.trailing.childOffset(childWidth: 50, in: 40) == 0)
        #expect(HorizontalAlignment.center.childOffset(childWidth: 50, in: 40) == 0)
        #expect(VerticalAlignment.top.childOffset(childHeight: 4, in: 40) == 0)
        #expect(VerticalAlignment.bottom.childOffset(childHeight: 4, in: 40) == 36)
        #expect(VerticalAlignment.bottom.childOffset(childHeight: 50, in: 40) == 0)
    }

    @Test("The stacks themselves place through the guides, not just the helper")
    func stacksUseTheGuides() {
        // Driven through the real `Layout` call, because agreeing in the helper
        // and not using it in the stack is exactly the state this was in.
        let context = makeRenderContext(width: 44, height: 4)
        // A wide first row makes the stack 40 columns; the short second row is
        // the one the alignment has anything to say about. Sizing the layout
        // from OUTSIDE (a .frame) would not work — a Layout sizes to its
        // content, so a lone child leaves nothing to distribute.
        func secondRowColumn(alignment: HorizontalAlignment) -> Int? {
            let view = VStackLayout(alignment: alignment, spacing: 0) {
                Text(String(repeating: "-", count: 40))
                Text("abcd")
            }
            let line = renderToBuffer(view, context: context).lines.dropFirst().first?.stripped
            return line.flatMap { rendered in
                rendered.firstIndex(where: { $0 != " " })
                    .map { rendered.distance(from: rendered.startIndex, to: $0) }
            }
        }
        let quarter = secondRowColumn(alignment: .quarter)
        let centred = secondRowColumn(alignment: .center)
        #expect(quarter == 9, "custom guide placed at \(String(describing: quarter))")
        #expect(centred == 18, "centre placed at \(String(describing: centred))")
    }
}
