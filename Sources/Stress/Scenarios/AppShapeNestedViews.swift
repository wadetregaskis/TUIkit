//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AppShapeNestedViews.swift
//
//  The application shapes whose lazy stacks are NOT their scroll view's direct
//  content: a feed of sections, each with its own stack of entries, and a log
//  under a header. Only the stack at the scroll content's origin is windowed;
//  a nested one is drawn whole, into the height it measured, so these price
//  what a nested stack costs — on the frames an app actually has, where the
//  data above the scroll view moves every tick.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// MARK: - Grouped feed

/// A feed of sections, each a heading over its own `LazyVStack` of entries —
/// lazy stacks nested in the rows of an outer one, the way a grouped timeline
/// or a sectioned log is built.
///
/// The outer stack is the scroll view's direct content and windows: only the
/// sections on screen are drawn. Each section's own stack is drawn whole
/// whenever its section is, into the height it measured, and every section is
/// measured whenever the outer stack places its rows. The page reads the
/// clock, so every tick is a write above the scroll view and every memo below
/// it is cleared: the frame an app pays on every change to its data.
struct GroupedFeedApp: View {
    let sections: Int
    let entries: Int
    let seed: UInt64
    /// Whether some entries carry a second line — as a real feed's do — or
    /// every entry is one line, where a sixteen-row sample prices each section
    /// exactly and measuring every entry buys nothing.
    let mixedHeights: Bool
    @Environment(StressClock.self) private var clock

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(
                Lf(
                    "stress.scenario.app-shapes.heading",
                    mixedHeights ? "grouped-feed" : "grouped-feed-uniform", sections * entries)
            )
            .bold()
            Text(clock.tick.formatted()).dim()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<sections, id: \.self) { section in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(Synth.slug(mix(seed, -1 - section))).bold()
                            LazyVStack(alignment: .leading, spacing: 0) {
                                // A few more per section, so no two are alike.
                                ForEach(0..<(entries + section), id: \.self) { entry in
                                    FeedEntry(
                                        seed: seed, section: section, entry: entry,
                                        mixedHeights: mixedHeights)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Headed log

/// A log under a header, both in one scroll view: `VStack { header;
/// LazyVStack { … } }` — the lazy stack is one sibling of two, not the scroll
/// view's direct content, so it is drawn whole, every entry, every frame. The
/// page reads the clock, as the feed's does.
struct HeadedLogApp: View {
    let entries: Int
    let seed: UInt64
    @Environment(StressClock.self) private var clock

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.app-shapes.heading", "headed-log", entries)).bold()
            Text(clock.tick.formatted()).dim()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Synth.sentence(seed, words: 12)).bold()
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<entries, id: \.self) { entry in
                            FeedEntry(seed: seed, section: 0, entry: entry, mixedHeights: true)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Shared pieces

/// One entry: a line, and for about a third of them a dimmed detail line
/// (`Equatable` so unchanged entries value-memoize, as an app's rows would).
private struct FeedEntry: View, Equatable {
    let seed: UInt64
    let section: Int
    let entry: Int
    let mixedHeights: Bool

    var body: some View {
        let h = mix(seed, section &* 100_003 &+ entry)
        VStack(alignment: .leading, spacing: 0) {
            Text("\(Synth.slug(h)) \(Synth.status(h))")
            if mixedHeights, h.isMultiple(of: 3) {
                Text(Synth.sentence(h >> 8, words: 4)).dim()
            }
        }
    }
}
