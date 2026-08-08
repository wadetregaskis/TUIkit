//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LayoutProtocolTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Fixtures

/// Stacks its subviews diagonally: each starts one column right and one row
/// below where the previous one started. Exercises the whole contract —
/// measure, place, and a size that is neither the sum nor the max.
private struct Diagonal: Layout {
    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        var width = 0
        var height = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            width = max(width, index + size.width)
            height = max(height, index + size.height)
        }
        return ViewSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) {
        for (index, subview) in subviews.enumerated() {
            subview.place(at: (x: bounds.x + index, y: bounds.y + index), proposal: .unspecified)
        }
    }
}

/// Places every subview at one anchor of the bounds, so the caller can drive
/// the placement arithmetic directly.
private struct AnchorAt: Layout {
    let anchor: UnitPoint
    let width: Int
    let height: Int

    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        ViewSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) {
        for subview in subviews {
            subview.place(in: bounds, anchor: anchor, proposal: .unspecified)
        }
    }
}

/// Counts how many times its cache is built, to pin the documented per-pass
/// lifetime rather than leave it to chance.
private final class CacheLog: @unchecked Sendable {
    var made = 0
    var updated = 0
}

private struct Cached: Layout {
    let log: CacheLog

    func makeCache(subviews: Subviews) -> Int {
        log.made += 1
        return subviews.count
    }

    func updateCache(_ cache: inout Int, subviews: Subviews) {
        log.updated += 1
        cache = subviews.count
    }

    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout Int) -> ViewSize {
        ViewSize(width: cache, height: 1)
    }

    func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout Int
    ) {
        for subview in subviews {
            subview.place(at: (x: bounds.x, y: bounds.y), proposal: .unspecified)
        }
    }
}

private struct Span: LayoutValueKey {
    static let defaultValue = 1
}

/// Reports the total span its subviews asked for, so a test can prove the
/// value actually arrived.
private struct SumOfSpans: Layout {
    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        ViewSize(width: subviews.reduce(0) { $0 + $1[Span.self] }, height: 1)
    }

    func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) {
        for subview in subviews {
            subview.place(at: (x: bounds.x, y: bounds.y), proposal: .unspecified)
        }
    }
}

// MARK: - Suite

/// The `Layout` protocol in whole cells.
///
/// The design question this answers is not "does it work" but "does integer
/// geometry cost anything". It does, in exactly one place — an anchored
/// placement subtracts `anchor × size`, and doing that in two floored steps
/// instead of one moves the result by a cell in 210 of 861 (extent, size)
/// combinations. That is the same arithmetic `AlignmentID` documents, and the
/// cases below pin the single-floor behaviour on both `place` overloads.
@MainActor
@Suite("Layout protocol")
struct LayoutProtocolTests {

    private func indents(_ buffer: FrameBuffer) -> [Int] {
        buffer.lines.map { line in
            let stripped = line.stripped
            return stripped.count - stripped.drop(while: { $0 == " " }).count
        }
    }

    // MARK: - The basic contract

    @Test("A custom layout places its subviews where it says")
    func customLayoutPlaces() {
        let buffer = renderToBuffer(
            Diagonal {
                Text("a")
                Text("b")
                Text("c")
            },
            context: makeRenderContext(width: 20, height: 6))

        #expect(buffer.lines.count == 3)
        #expect(indents(buffer) == [0, 1, 2])
        #expect(buffer.width == 3)
    }

    @Test("The reported size is the size rendered")
    func measureMatchesRender() {
        // A layout reports its own size; if the measure and the render
        // disagreed, the parent would reserve the wrong space.
        let view = Diagonal {
            Text("one")
            Text("two")
        }
        let context = makeRenderContext(width: 20, height: 6)
        let measured = measureChild(view, proposal: .unspecified, context: context)
        let rendered = renderToBuffer(view, context: context)

        #expect(measured.width == rendered.width)
        #expect(measured.height == rendered.lines.count)
    }

    @Test("A subview that is never placed is not drawn")
    func unplacedSubviewsAreNotDrawn() {
        struct PlacesFirstOnly: Layout {
            func sizeThatFits(
                proposal: ProposedSize, subviews: Subviews, cache: inout ()
            ) -> ViewSize {
                ViewSize(width: 10, height: 1)
            }
            func placeSubviews(
                in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()
            ) {
                subviews.first?.place(at: (x: 0, y: 0), proposal: .unspecified)
            }
        }

        let buffer = renderToBuffer(
            PlacesFirstOnly {
                Text("kept")
                Text("dropped")
            },
            context: makeRenderContext(width: 20, height: 4))

        #expect(buffer.lines[0].stripped.contains("kept"))
        #expect(!buffer.lines[0].stripped.contains("dropped"))
    }

    // MARK: - The anchor arithmetic

    @Test("place(in:anchor:) centres with a single floor")
    func centringUsesOneFloor() {
        // The whole reason `CellRect` has no `midX`. Region 11 wide, subview 1
        // wide: one floor gives floor((11 - 1) / 2) == 5. Two floors — a
        // pre-floored midpoint minus a halved size — would give 5 - 0 == 5
        // here, so the discriminating case is an ODD region with an ODD
        // subview, below.
        let buffer = renderToBuffer(
            AnchorAt(anchor: .center, width: 11, height: 1) { Text("x") },
            context: makeRenderContext(width: 20, height: 4))
        #expect(indents(buffer) == [5])
    }

    @Test("The discriminating centring case lands on one floor, not two")
    func discriminatingCentringCase() {
        // Region 4, subview 3. One floor: floor((4 - 3) / 2) == 0.
        // Two floors: (4 / 2) - (3 / 2) == 2 - 1 == 1. The code must say 0.
        let buffer = renderToBuffer(
            AnchorAt(anchor: .center, width: 4, height: 1) { Text("abc") },
            context: makeRenderContext(width: 20, height: 4))
        #expect(indents(buffer) == [0])
    }

    @Test("A trailing anchor sits flush and never overflows")
    func trailingAnchorIsFlush() {
        let flush = renderToBuffer(
            AnchorAt(anchor: .trailing, width: 10, height: 1) { Text("abc") },
            context: makeRenderContext(width: 20, height: 4))
        #expect(indents(flush) == [7])

        // A subview wider than its region cannot be pushed off the leading edge.
        let oversized = renderToBuffer(
            AnchorAt(anchor: .trailing, width: 2, height: 1) { Text("abcdef") },
            context: makeRenderContext(width: 20, height: 4))
        #expect(indents(oversized) == [0])
    }

    @Test("place(at:anchor:) subtracts the anchor from the position")
    func placeAtHonoursTheAnchor() {
        struct AtColumn: Layout {
            let anchor: UnitPoint
            func sizeThatFits(
                proposal: ProposedSize, subviews: Subviews, cache: inout ()
            ) -> ViewSize {
                ViewSize(width: 12, height: 1)
            }
            func placeSubviews(
                in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()
            ) {
                for subview in subviews {
                    subview.place(at: (x: 6, y: 0), anchor: anchor, proposal: .unspecified)
                }
            }
        }

        // .topLeading needs no arithmetic: the subview's own leading edge lands
        // on column 6.
        #expect(
            indents(
                renderToBuffer(
                    AtColumn(anchor: .topLeading) { Text("abc") },
                    context: makeRenderContext(width: 20, height: 4))) == [6])
        // .top puts the subview's CENTRE there: floor(6 - 0.5 * 3) == 4.
        #expect(
            indents(
                renderToBuffer(
                    AtColumn(anchor: .top) { Text("abc") },
                    context: makeRenderContext(width: 20, height: 4))) == [4])
    }

    // MARK: - Cache, values, erasure

    @Test("The cache is built once per pass, then updated")
    func cacheLifetime() {
        // Documented deviation: TUIkit has no persistent layout graph, so the
        // cache lives for one pass. `updateCache` still runs right after
        // `makeCache`, so a conforming layout sees the sequence it expects.
        let log = CacheLog()
        let buffer = renderToBuffer(
            Cached(log: log) {
                Text("a")
                Text("b")
            },
            context: makeRenderContext(width: 20, height: 4))

        #expect(log.made == 1)
        #expect(log.updated == 1)
        // The cache carried the subview count into the reported size.
        #expect(buffer.width == 2)
    }

    @Test("A layout value reaches the layout")
    func layoutValueArrives() {
        let view = SumOfSpans {
            Text("a").layoutValue(key: Span.self, value: 3)
            Text("b")
        }
        let size = measureChild(
            view, proposal: .unspecified, context: makeRenderContext(width: 20, height: 4))
        // 3 from the first, the default 1 from the second.
        #expect(size.width == 4)
    }

    @Test("layoutPriority rides the same channel")
    func layoutPriorityIsALayoutValue() {
        struct MaxPriority: Layout {
            func sizeThatFits(
                proposal: ProposedSize, subviews: Subviews, cache: inout ()
            ) -> ViewSize {
                ViewSize(width: Int(subviews.map(\.priority).max() ?? 0), height: 1)
            }
            func placeSubviews(
                in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()
            ) {
                for subview in subviews {
                    subview.place(at: (x: 0, y: 0), proposal: .unspecified)
                }
            }
        }

        let size = measureChild(
            MaxPriority {
                Text("a")
                Text("b").layoutPriority(7)
            },
            proposal: .unspecified, context: makeRenderContext(width: 20, height: 4))
        #expect(size.width == 7)
    }

    @Test("A subview's explicit alignment guide reaches dimensions(in:)")
    func dimensionsCarryExplicitGuides() {
        // The join between §1 and §3: a guide set on a subview must be
        // readable by a custom layout, not just by a stack.
        struct ReadsGuide: Layout {
            func sizeThatFits(
                proposal: ProposedSize, subviews: Subviews, cache: inout ()
            ) -> ViewSize {
                let guide = subviews[0].dimensions(in: .unspecified)[HorizontalAlignment.leading]
                return ViewSize(width: Int(guide), height: 1)
            }
            func placeSubviews(
                in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()
            ) {
                for subview in subviews {
                    subview.place(at: (x: 0, y: 0), proposal: .unspecified)
                }
            }
        }

        let size = measureChild(
            ReadsGuide {
                Text("abcd").alignmentGuide(.leading) { $0[.trailing] }
            },
            proposal: .unspecified, context: makeRenderContext(width: 20, height: 4))
        // The guide was moved to the trailing edge — 4, not the default 0.
        #expect(size.width == 4)
    }

    @Test("AnyLayout forwards to the layout it wraps")
    func anyLayoutForwards() {
        for wide in [true, false] {
            let layout = wide ? AnyLayout(Diagonal()) : AnyLayout(AnchorAt(anchor: .center, width: 9, height: 1))
            let buffer = renderToBuffer(
                layout {
                    Text("a")
                    Text("b")
                },
                context: makeRenderContext(width: 20, height: 6))
            if wide {
                #expect(indents(buffer) == [0, 1])
            } else {
                #expect(buffer.width == 9)
            }
        }
    }

    @Test("An empty layout renders nothing and does not crash")
    func emptyLayout() {
        let buffer = renderToBuffer(
            Diagonal {},
            context: makeRenderContext(width: 20, height: 4))
        #expect(buffer.width == 0)
    }

    @Test("A zero-sized terminal does not produce negative geometry")
    func degenerateBounds() {
        // The negative-size class: every container has to survive chrome
        // subtractions reaching zero.
        let buffer = renderToBuffer(
            AnchorAt(anchor: .center, width: 0, height: 0) { Text("x") },
            context: makeRenderContext(width: 0, height: 0))
        #expect(buffer.width >= 0)
    }
}
