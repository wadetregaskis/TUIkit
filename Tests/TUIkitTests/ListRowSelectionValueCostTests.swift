//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListRowSelectionValueCostTests.swift
//
//  What a `List` pays, per frame, to learn its rows' selection values — counted
//  in the work that dominates it, deterministically: row views BUILT by the
//  `ForEach` content closure (a `.tag(_:)` can only be read off a built row)
//  and reads of an element's `id`. A windowed loop — a `ForEach` that is the
//  list's whole content — resolves them for the rows the frame draws and the
//  handler asks about, and that is the reference every shape here is held to.
//
//  Every count is a DIFFERENCE between two lists that share everything but the
//  one thing being priced — tagged against untagged — so the rows' own
//  renders, measures and identity keys cancel, and what is left is the
//  selection-value work alone.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("A list resolves the selection values it is asked for", .rendersEnglishUI)
struct ListRowSelectionValueCostTests {

    /// Counts across frames. A class, not `@State`, so counting does not
    /// invalidate the rows being counted.
    final class Counter {
        var builds = 0
        var idReads = 0
    }

    /// A project whose `id` counts its reads — the key-path read an untagged
    /// looped row answers by. `Equatable` on the number alone, so the row memo
    /// serves it as it would an app's value type.
    struct Project: Identifiable, Equatable {
        let number: Int
        let counter: Counter
        var id: Int {
            counter.idReads += 1
            return number
        }
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.number == rhs.number }
    }

    /// What the tagged sidebar selects: everything, or one project.
    enum Pick: Hashable {
        case all
        case project(Int)
    }

    /// The looped row, counted as it is built. Named types rather than
    /// `some View`, so the row's static type is exactly what the list sees.
    static func taggedRow(_ project: Project) -> _TaggedView<Text> {
        project.counter.builds += 1
        return _TaggedView(
            tagValue: AnyHashable(Pick.project(project.number)), includeOptional: true,
            content: Text("project \(project.number)"))
    }

    static func untaggedRow(_ project: Project) -> Text {
        project.counter.builds += 1
        return Text("project \(project.number)")
    }

    /// Frames through one state store and one render cache, each bracketed in
    /// the pass lifecycle the run loop brackets it in, so the row memo serves
    /// a steady frame as it would in the app.
    @MainActor
    final class Frames {
        let tui = TUIContext()
        var env = EnvironmentValues()
        let counter: Counter

        init(counter: Counter) {
            self.counter = counter
            env.focusManager = FocusManager()
            env.applyRuntimeServices(from: tui)
        }

        /// Renders one frame and returns what it cost and how many project
        /// rows it drew.
        func frame(_ view: some View) -> (builds: Int, idReads: Int, drawn: Int) {
            let before = (counter.builds, counter.idReads)
            tui.stateStorage.beginRenderPass()
            env.focusManager?.beginRenderPass()
            let context = RenderContext(
                availableWidth: 60, availableHeight: 24, environment: env, tuiContext: tui)
            context.renderCache?.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            env.focusManager?.endRenderPass()
            tui.stateStorage.endRenderPass()
            context.renderCache?.removeInactive()
            let drawn = buffer.lines.filter { $0.stripped.contains("project ") }.count
            return (counter.builds - before.0, counter.idReads - before.1, drawn)
        }

        /// The third frame: the first two fill the caches and settle focus.
        func steadyFrame(_ view: some View) -> (builds: Int, idReads: Int, drawn: Int) {
            _ = frame(view)
            _ = frame(view)
            return frame(view)
        }
    }

    private static let rowCount = 300

    private static func projects(_ counter: Counter) -> [Project] {
        (0..<rowCount).map { Project(number: $0, counter: counter) }
    }

    // MARK: - The hug walk

    /// A hugging list — `.fixedSize(horizontal:)`, or a `NavigationSplitView`'s
    /// sidebar — walks EVERY row for its width on each frame the size memo
    /// cannot answer: the first, and every one after the data changes. The
    /// walk asked each row for its selection value too, and a tagged row can
    /// only answer that by being built: 300 builds for nothing the width looks
    /// at.
    @Test("A hugging list's width walk builds no row to read its tag")
    func hugWalkReadsNoTags() {
        func coldBuilds(tagged: Bool) -> (builds: Int, drawn: Int) {
            let counter = Counter()
            let projects = Self.projects(counter)
            let frames = Frames(counter: counter)
            let cost =
                tagged
                ? frames.frame(
                    List(selection: .constant(Pick?.none)) {
                        ForEach(projects) { Self.taggedRow($0) }
                    }
                    .fixedSize(horizontal: true))
                : frames.frame(
                    List(selection: .constant(Int?.none)) {
                        ForEach(projects) { Self.untaggedRow($0) }
                    }
                    .fixedSize(horizontal: true))
            return (cost.builds, cost.drawn)
        }
        let tagged = coldBuilds(tagged: true)
        let untagged = coldBuilds(tagged: false)
        let tagBuilds = tagged.builds - untagged.builds
        #expect(tagged.drawn > 0 && tagged.drawn == untagged.drawn, "both lists drew their rows")
        // A windowed loop reads the tag of each row it draws and of each row
        // the handler asks about — the O(visible) price of a tagged row.
        #expect(
            tagBuilds <= 2 * tagged.drawn + 2,
            "\(tagBuilds) tag builds for \(tagged.drawn) drawn rows of \(Self.rowCount)")
    }
}
