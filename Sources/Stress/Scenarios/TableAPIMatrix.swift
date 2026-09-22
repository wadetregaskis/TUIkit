//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableAPIMatrix.swift
//
//  Every way an app can build a `Table`, as one scenario with many variants.
//
//  The catalogue had five Table scenarios and between them they covered one
//  point in the API's space: closure columns, `.flexible` widths, no selection
//  binding, no sort binding, single-line rows, data built once and never
//  changed. Everything learned about `Table` performance this month came from
//  shapes that were NOT in it — `.fit`'s O(rows) scan, the wrapped estimator's
//  256-row cliff, the difference a key-path column makes to what can be kept
//  across frames — and each of those had to have a scenario written for it
//  before it could be measured at all.
//
//  This file is the space itself: the ways a column gets its value, the four
//  width modes, the truncation modes, the alignments, the line limits, the
//  selection bindings, sorting, the chrome, the update patterns, the row-type
//  shapes, and cell costs from an interpolated integer to a formatted byte
//  count. Each is a named variant of ONE registered scenario, so adding the
//  next one costs a struct literal rather than an id and seven translations.
//
//      Stress --variants                        list them
//      Stress --bench --scenario table-api --variant width-fit
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkit

// MARK: - The rows

/// A row with enough shape to exercise a table: things to sort by, things to
/// format, things to truncate, and things that are wide.
///
/// Every property is a pure function of `(id, generation)` — which is what a
/// key-path column's premise requires, and what an app's own row properties
/// normally are. The pair is the whole of a frame's data, so rebuilding the
/// array costs two `Int`s per row and everything measured downstream is the
/// table's own work.
struct APIRow: Identifiable, Sendable, Equatable {
    let id: Int
    let generation: Int

    var hash: UInt64 { mix(UInt64(bitPattern: Int64(id)), generation) }

    /// Cheap — an interpolated integer, which is what every earlier fixture's
    /// cells were.
    var index: String { "\(id)" }
    /// The ordinary display string: two synthesised words.
    var name: String { Synth.name(hash) }
    var slug: String { Synth.slug(hash >> 8) }
    /// Styled, so the byte-wise clip has to decline it and the emitter has SGR
    /// to carry across a column boundary.
    var status: String { "\u{1B}[3\(hash % 6 + 1)m\(Synth.status(hash))\u{1B}[0m" }
    /// Wide: CJK and emoji, so every width question goes through the per-cluster
    /// path rather than the ASCII one.
    var glyphs: String { Self.wide[Int(hash % UInt64(Self.wide.count))] }
    /// Long enough that every column truncates it.
    var summary: String { Synth.sentence(hash >> 16, words: 14) }
    /// Genuinely expensive, and not a stand-in for it: `.formatted` is what an
    /// app calls to show a size or a date, and it costs what it costs.
    var size: String { Int(hash % 9_000_000).formatted(.byteCount(style: .file)) }
    var stamp: String {
        Self.epoch.addingTimeInterval(Double(hash % 31_536_000))
            .formatted(date: .abbreviated, time: .shortened)
    }
    var bar: String { Synth.bar(Double(hash % 100) / 100, width: 10) }

    /// Sortable, for the columns that sort by one property and display another.
    var score: Int { Int(hash % 10_000) }
    var bytes: Int { Int(hash % 9_000_000) }

    private static let wide = ["日本語テキスト", "한국어 텍스트", "👋🏽 waves", "👨‍👩‍👧‍👦 family", "❤️ love"]
    /// Fixed rather than `.now`, so a formatted date is deterministic and the
    /// bench's content checksum is stable across runs.
    private static let epoch = Date(timeIntervalSince1970: 1_600_000_000)
}

/// The same row with no `Equatable` conformance, which `Table` does not require
/// and an app's model type often lacks.
struct APIOpaqueRow: Identifiable, Sendable {
    let id: Int
    let generation: Int
    var hash: UInt64 { mix(UInt64(bitPattern: Int64(id)), generation) }
    var index: String { "\(id)" }
    var name: String { Synth.name(hash) }
    var summary: String { Synth.sentence(hash >> 16, words: 14) }
}

/// A reference-type row, which an app driving a table from model objects has.
/// Identity is the `id` as ever, but equality — if anything reaches for it —
/// is the class's, so a fresh object per frame is never equal to last frame's.
final class APIClassRow: Identifiable, @unchecked Sendable {
    let id: Int
    let generation: Int
    init(id: Int, generation: Int) {
        self.id = id
        self.generation = generation
    }
    var hash: UInt64 { mix(UInt64(bitPattern: Int64(id)), generation) }
    var index: String { "\(id)" }
    var name: String { Synth.name(hash) }
    var summary: String { Synth.sentence(hash >> 16, words: 14) }
}

// MARK: - How the data moves between frames

/// What happens to the rows from one frame to the next — the axis that decides
/// what any cross-frame memo can serve.
enum APIChurn: Sendable {
    /// Built once and never changed: a table nothing is updating.
    case still
    /// Replaced every frame; one row in `period` actually differs.
    case fraction(Int)
    /// Replaced every frame; every row differs.
    case all
    /// A window over a growing sequence: content and identity move up together.
    case tail

    /// Whether a variant on this churn must OBSERVE the clock.
    ///
    /// Load-bearing, not a micro-optimisation: reading `clock.tick` in a body
    /// is what subscribes that subtree to the tick, so a `.still` variant that
    /// read it would be re-rendered every frame by an `@Observable` change and
    /// would measure the invalidation rather than the static table it is for.
    var observesClock: Bool {
        if case .still = self { false } else { true }
    }

    func rows(count: Int, tick: Int) -> [APIRow] {
        switch self {
        case .still:
            return (0..<count).map { APIRow(id: $0, generation: 0) }
        case .fraction(let period):
            // A row's generation only advances on the frames its slot comes up,
            // so most rows hand back a value equal to last frame's.
            return (0..<count).map {
                APIRow(id: $0, generation: (tick &+ period &- 1 &- $0 % period) / period)
            }
        case .all:
            return (0..<count).map { APIRow(id: $0, generation: tick) }
        case .tail:
            // The id TRAVELS with the content, which is what makes this a shift
            // rather than a churn: nothing changes what it says, everything
            // changes where it says it.
            return (0..<count).map { APIRow(id: tick &+ $0, generation: 0) }
        }
    }
}

/// The default churn: one row in 64, so ~2% of the table and about two of the
/// ~35 rows on screen differ per frame. The shape a live table actually has.
let apiChurnPeriod = 64

// MARK: - The frame every variant wears

/// Supplies rows from the clock and frames whatever a variant builds from them.
///
/// Generic over the row type as well as the content, because three of the
/// variants exist precisely to ask what a non-`Equatable` struct or a class
/// costs, and a frame hard-wired to ``APIRow`` could not host them.
struct APIFrame<Row, Content: View>: View {
    let variant: String
    let count: Int
    let observesClock: Bool
    /// Tick → rows.
    let rows: (Int) -> [Row]
    let content: ([Row]) -> Content

    @Environment(StressClock.self) private var clock

    var body: some View {
        // See `APIChurn.observesClock` for why this is a branch and not a read.
        let tick = observesClock ? clock.tick : 0
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.table-api.heading", variant, count)).bold()
            Divider()
            content(rows(tick))
        }
    }
}

// MARK: - The matrix

@MainActor
enum TableAPIMatrix {
    static let scenarioID = "table-api"

    static let descriptor = Scenario(
        id: scenarioID,
        title: "Table API Matrix",
        blurb: "One Table built every way the API allows — pick a point with --variant.",
        stresses: "column value kinds · width modes · truncation · selection · sorting · update patterns",
        make: { config in
            ScenarioVariants.resolve(config, in: scenarioID)?.make(config)
                ?? AnyView(Text(Lf("stress.scenario.table-api.heading", "?", 0)))
        }
    )

    /// The whole space, in axis order. The FIRST is the default, so
    /// `--bench --scenario table-api` with no `--variant` is the baseline the
    /// others are read against.
    static let variants: [ScenarioVariant] =
        dataVariants + widthVariants + textVariants
        + layoutVariants + interactionVariants + churnVariants + shapeVariants

    // MARK: Shared scaffolding

    /// One variant, named and grouped by the axis it varies.
    static func variant(
        _ id: String, axis: String, _ summary: String,
        _ make: @escaping @MainActor (StressConfig) -> AnyView
    ) -> ScenarioVariant {
        ScenarioVariant(id: id, summary: summary, axis: axis, make: make)
    }

    /// The default row count: big enough that the window is a small slice of it,
    /// small enough that the variants which walk every row still run.
    static func count(_ config: StressConfig) -> Int { config.sized(5_000) }

    /// The common case — ``APIRow`` rows under the default churn — framed.
    static func table<Content: View>(
        _ id: String, _ config: StressConfig, churn: APIChurn = .fraction(apiChurnPeriod),
        count: Int? = nil, content: @escaping ([APIRow]) -> Content
    ) -> AnyView {
        let rows = count ?? self.count(config)
        return AnyView(
            APIFrame(
                variant: id, count: rows, observesClock: churn.observesClock,
                rows: { churn.rows(count: rows, tick: $0) }, content: content))
    }

    /// A table whose rows are built ONCE, at make time, and never rebuilt.
    ///
    /// Built here rather than in the frame's body for the reason every static
    /// scenario in the catalogue builds its data in `init`: a body that
    /// synthesises its rows each frame measures the harness's array building
    /// alongside the table's work, and at 100,000 rows the harness wins.
    static func stillTable<Content: View>(
        _ id: String, _ config: StressConfig, count: Int? = nil,
        content: @escaping ([APIRow]) -> Content
    ) -> AnyView {
        let n = count ?? self.count(config)
        let rows = APIChurn.still.rows(count: n, tick: 0)
        return AnyView(
            APIFrame(
                variant: id, count: n, observesClock: false,
                rows: { _ in rows }, content: content))
    }
}
