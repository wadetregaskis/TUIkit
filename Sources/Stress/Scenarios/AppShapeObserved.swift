//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AppShapeObserved.swift
//
//  Applications whose rows read an `@Observable` of their own — the shape a
//  change to what TUIkit observes (Option C's C3) is priced on — and one
//  whose rows each hold a timeline. The first two are DRIVEN: a model the
//  view reads is written between frames, as an app's is, through the advance
//  closure the bench calls before each frame (`DrivenScenario`).
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import TUIkit

// MARK: - A per-row model

/// A counter a row reads in its body. Compared by identity: a row holding one
/// is the same row for as long as it holds the same object.
@Observable
@MainActor
final class RowCounter: Identifiable {
    let id: Int
    var count: Int

    init(id: Int, count: Int) {
        self.id = id
        self.count = count
    }
}

extension RowCounter: Equatable {
    nonisolated static func == (lhs: RowCounter, rhs: RowCounter) -> Bool { lhs === rhs }
}

// MARK: - Outline

/// A section of the outline: a title over counters.
struct OutlineSection: Identifiable, Equatable {
    let id: Int
    let title: String
    let items: [RowCounter]
}

/// Nested `ForEach` sections in a lazy stack, every row reading its own
/// counter in its body; one counter moves a frame.
///
/// A drawn row's read is observed today; a row measured off the window is
/// not. Observing it is correct and costs a registration per reader, so this
/// is where that cost and the invalidations it brings are counted: one row's
/// counter moves, and every sibling should be served.
struct OutlineApp: View {
    let sections: [OutlineSection]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: section.title).bold()
                        ForEach(section.items) { item in OutlineRow(item: item) }
                    }
                }
            }
        }
    }

    /// `sections` sections of `rows` counters, and the advance that moves one
    /// counter a frame, wandering over all of them.
    static func driven(sections count: Int, rows: Int, seed: UInt64) -> DrivenScenario {
        let sections = (0..<count).map { index in
            OutlineSection(
                id: index, title: "\(index + 1). \(Synth.sentence(mix(seed, index), words: 3))",
                items: (0..<rows).map { RowCounter(id: index * rows + $0, count: Int(mix(seed ^ 0x0D7, index * rows + $0) % 9)) })
        }
        let counters = sections.flatMap(\.items)
        return DrivenScenario(view: AnyView(Self(sections: sections))) { tick in
            let counter = counters[Int(mix(seed, tick) % UInt64(counters.count))]
            counter.count = (counter.count + 1) % 12
        }
    }
}

/// One row: its number and its counter as a run of dots.
private struct OutlineRow: View, Equatable {
    let item: RowCounter

    var body: some View {
        HStack(spacing: 1) {
            Text(verbatim: "  #\(item.id)")
            Text(verbatim: String(repeating: "•", count: item.count)).foregroundStyle(Color.cyan)
        }
    }
}

// MARK: - Scroll follow, observed

/// `scrollfollow` with every row reading one of 64 notes in its body, and one
/// note moving a frame: a bottom-anchored follow whose drawn rows are
/// observed readers.
struct ObservedFollowApp: View {
    let seed: UInt64
    let base: Int
    let notes: [RowCounter]
    @Environment(StressClock.self) private var clock

    var body: some View {
        let count = base + clock.tick
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "\(count) lines").bold()
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<count, id: \.self) { index in
                        ObservedFollowRow(seed: seed, index: index, note: notes[index % notes.count])
                    }
                }
            }
            .defaultScrollAnchor(.bottom)
        }
    }

    /// `base` rows to start with, one more a frame, and the advance that moves
    /// one note a frame.
    static func driven(base: Int, seed: UInt64) -> DrivenScenario {
        let notes = (0..<64).map { RowCounter(id: $0, count: 0) }
        return DrivenScenario(view: AnyView(Self(seed: seed, base: base, notes: notes))) { tick in
            notes[tick % notes.count].count += 1
        }
    }
}

/// One synthesised log line, 1–3 cells tall, marked with its note's count.
private struct ObservedFollowRow: View, Equatable {
    let seed: UInt64
    let index: Int
    let note: RowCounter

    var body: some View {
        let h = mix(seed, index)
        Text(verbatim: "#\(index) \(Synth.slug(h)) \(Synth.status(h)) ·\(note.count % 10)")
            .foregroundStyle(statusColor(h))
            .frame(height: Int(h % 3) + 1)
    }
}

// MARK: - A timeline in every row

/// A two-axis windowed stack of 400 rows, each with a `TimelineView` on the
/// animation schedule: every row's entry moves every frame, beside a width
/// the stack keeps for its horizontal extent.
struct TimelineRowsApp: View {
    let rows: Int
    let seed: UInt64

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<rows, id: \.self) { index in
                    TimelineRow(index: index, text: Synth.sentence(mix(seed, index), words: 2 + index % 7))
                }
            }
        }
    }
}

/// A row whose trailing cell is its timeline's frame, cycling through four
/// glyphs.
private struct TimelineRow: View, Equatable {
    let index: Int
    let text: String

    var body: some View {
        HStack(spacing: 1) {
            Text(verbatim: "\(index) \(text)")
            TimelineView(.animation) { context in
                let phase = Int(context.date.timeIntervalSinceReferenceDate * 8) % 4
                Text(verbatim: ["◐", "◓", "◑", "◒"][phase])
            }
        }
    }
}
