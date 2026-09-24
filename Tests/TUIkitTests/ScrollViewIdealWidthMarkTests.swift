//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollViewIdealWidthMarkTests.swift
//
//  A scroll view's ideal-size measure clears an inherited whole-content-width
//  mark on a view that does not scroll horizontally, and never SETS one. Set,
//  on a horizontally scrolling view, a lazy stack answers that question only
//  from a kept width record and answers the prefix until one is filed — so a
//  horizontally scrolling list of filling rows in a `TabView`, which sizes a
//  tab to its content's ideal width, was drawn across the panel for two frames
//  and then shrank to eleven columns, its rows' numbers cut off. Found by
//  review of the change that made the ideal-size measure clear the mark.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// How the list of filling rows scrolls, and what it sits in.
enum IdealWidthMarkShape: CaseIterable, Sendable, CustomTestStringConvertible {
    case bothAxes
    case horizontal
    case vertical
    case bothAxesMaxWidthRows
    case bothAxesFixedBesideText

    var testDescription: String {
        switch self {
        case .bothAxes: "both axes"
        case .horizontal: "horizontal"
        case .vertical: "vertical"
        case .bothAxesMaxWidthRows: "both axes, rows framed to fill"
        case .bothAxesFixedBesideText: "both axes, fixed-size beside a text"
        }
    }
}

private struct IdealWidthMarkApp: App {
    let shape: IdealWidthMarkShape
    init() { shape = .bothAxes }
    init(shape: IdealWidthMarkShape) { self.shape = shape }
    var body: some Scene { WindowGroup { IdealWidthMarkPage(shape: shape) } }
}

/// Forty-eight rows that fill: a note, a spacer, its number.
private struct FillingNoteRows: View {
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<48, id: \.self) { index in
                HStack(spacing: 1) {
                    Text(verbatim: "note \(index)")
                    Spacer()
                    Text(verbatim: "#\(index)")
                }
            }
        }
    }
}

private struct IdealWidthMarkPage: View {
    let shape: IdealWidthMarkShape

    var body: some View {
        TabView(selection: .constant(0)) {
            Tab("Notes", value: 0) {
                switch shape {
                case .bothAxes: ScrollView([.horizontal, .vertical]) { FillingNoteRows() }
                case .horizontal: ScrollView(.horizontal) { FillingNoteRows() }
                case .vertical: ScrollView { FillingNoteRows() }
                case .bothAxesMaxWidthRows:
                    ScrollView([.horizontal, .vertical]) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(0..<48, id: \.self) { index in
                                Text(verbatim: "line \(index) #\(index)")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                case .bothAxesFixedBesideText:
                    HStack(spacing: 1) {
                        ScrollView([.horizontal, .vertical]) { FillingNoteRows() }
                            .fixedSize(horizontal: true, vertical: false)
                        Text(verbatim: "side")
                    }
                }
            }
            Tab("Archive", value: 1) { Text(verbatim: "nothing archived") }
        }
    }
}

@MainActor
@Suite("A scroll view's ideal-size measure and the whole-content-width mark")
struct ScrollViewIdealWidthMarkTests {
    @Test("A list of filling rows keeps its width frame after frame", arguments: IdealWidthMarkShape.allCases)
    func steadyFrames(shape: IdealWidthMarkShape) {
        let verified = RenderCache.verifiesMeasureMemo
        RenderCache.verifiesMeasureMemo = true
        defer { RenderCache.verifiesMeasureMemo = verified }
        let app = HeadlessApp(IdealWidthMarkApp(shape: shape), width: 60, height: 12)
        var now: Int64 = 0
        var frames: [[String]] = []
        for _ in 0..<5 {
            now += 16_666_667
            app.frame(atNanos: now)
            frames.append(app.screen.map(\.stripped))
        }
        for index in 1..<frames.count {
            #expect(frames[index] == frames[0], "frame \(index) differs from frame 0: \(frames[index])")
        }
        #expect(
            frames[4].contains { $0.contains("#1") && !$0.contains("#10") && !$0.contains("#11") },
            "row 1's number is not on screen: \(frames[4])")
        let mismatches = app.renderCache.measureMemoMismatches
        #expect(mismatches.isEmpty, "\(mismatches.count) served sizes differed: \(mismatches.first ?? "")")
    }
}
