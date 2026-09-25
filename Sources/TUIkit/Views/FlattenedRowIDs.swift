//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FlattenedRowIDs.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - The rows of a flattened container

/// The selection value of each row of a container whose children arrive
/// FLATTENED — a `Section`'s or a `List`'s content that mixes a `ForEach` with
/// hand-written rows (or with a second `ForEach`, or wraps one in a modifier),
/// walked through `resolveChildViews`.
///
/// A hand-written row answers by the hand-written rule: its own `.tag(_:)`,
/// else its ordinal (see ``staticListRowID(of:ordinal:as:)``). A LOOPED row —
/// one the splice took from a `ForEach` — answers by its loop's rule instead,
/// the one the loop applies when it is the container's whole content: the
/// row's own tag, else its element's id.
///
/// The loop's rule has to be fetched from the loop, because the row cannot
/// carry it. A flattened row is a `ChildView`, which holds its element's id
/// only as the STRING its identity is keyed by — `identityKey(_:)`, a one-way
/// trip — and whose size is load-bearing, so a typed id cannot ride along on it
/// (see `ChildView.providerSlot`). The hand-written rule was applied in its
/// place, and it could not work: a looped row of an `Equatable` element
/// arrives wrapped in `_MemoizedRow`, which is opaque to the tag read, and an
/// ordinal casts into no `String`, `UUID` or `Set` of either. So under any such
/// selection every looped row was unselectable — the cursor stepped over it
/// and a click on it wrote nothing — and under an `Int` selection each was
/// numbered by its position in the container rather than by its element.
///
/// ## Which row is whose: by position
///
/// A flattened row does not say which provider made it, but its PLACE does.
/// `resolveChildViews` emits the children in the order the content declares
/// them — a tuple slot by slot, a `ForEach` element by element — and this walks
/// the content in that same order (``KeyedRowProvider``). Only a loop or an
/// outline makes a KEYED child; every other child is positional. So the keyed
/// children are dealt out to the providers that made them by count: a loop
/// owns exactly as many as it has elements, an outline owns the run of outline
/// rows in front of it. Each loop's first and last row are checked against the
/// keys the loop gives them, which is what catches a walk that has lost step
/// with the flattening.
///
/// Matching by the key alone is what this replaced, and a key names a value
/// only up to its spelling: two loops over overlapping ids — projects 1, 2, 3
/// and people 1, 2 in one sidebar — handed each other's answers, or, where they
/// disagreed, lost both; and an outline node spelled like a loop's element took
/// the loop's tag. By position each row gets its own loop's answer, whatever
/// any other provider's rows are called.
///
/// A provider the walk cannot see into (``KeyedRowRun/opaque``) owns whatever
/// keyed children are left between the loops placed from the front and from
/// the back. Two of them leave the loops BETWEEN them unplaced, and a failed
/// check unplaces every loop. An unplaced row keeps the hand-written rule —
/// the answer it had before — with its tag read through the value memo, which
/// is at least the tag it wrote.
///
/// The rows themselves are still the flattened ones, rendered at the
/// identities the splice gave them — the `"\(slot)#\(key)"` namespacing and
/// the row memo untouched. Only the id is read from the loop. Asking the
/// content's top-level `ForEach`es for their rows outright
/// (``ListRowExtractor``) would resolve the ids too, and would render the rows
/// at `ForEach.makeListRowContent`'s identity, which has no slot prefix: two
/// loops over the same ids in one container would share `@State` and each
/// other's memoised buffers again.
///
/// ## An ordinal never names a looped row
///
/// An untagged hand-written row falls back to its ordinal, which only an `Int`
/// selection can hold — and an `Int` is exactly what `ForEach(0..<3)` names its
/// rows. Beside such a loop the two collide: "None" at ordinal 0 and the loop's
/// first row both answer 0, so selecting either highlights both, Space on
/// "None" writes the loop's 0, and focus returning to a selection of 0 lands on
/// "None". SwiftUI gives an untagged row no selection value at all, so here an
/// ordinal some looped row in the container already answers to YIELDS: the
/// hand-written row draws, and cannot be selected. An ordinal nothing collides
/// with stays, so a container of hand-written rows keeps the numbers it always
/// had.
///
/// - Note: An id is a SELECTION value and says nothing about which collection a
///   row is in or where — a tag can replace it and a second loop can share it —
///   so recovering it does not make `.onDelete` / `.onMove` attributable in this
///   arrangement, and those still refuse (see
///   ``SectionContentRows/actions``). The placement itself does know
///   each row's loop and offset; it is used for the id and nothing else.
///
/// ## Asked, not computed
///
/// Nothing is walked, placed or resolved until the first answer is asked for,
/// and then only the answer asked for is resolved: a looped row's is its
/// loop's rule, which for a `.tag(_:)`-outermost row means BUILDING the row to
/// read the tag. The one answer that asks others is an untagged hand-written
/// row's ordinal, which has to know whether a looped row answers it (see
/// ``ordinalID(_:)``). The placement is made once, on that first question, and
/// each row's own answer is kept once found, so asking twice costs nothing
/// more. A reference type so that everything holding an answer still to be
/// asked shares the one placement and the one set of answers.
@MainActor
final class FlattenedRowIDs<ID: Hashable> {
    /// The view `children` were flattened from, walked for the placement.
    private let content: any View

    /// The children the answers are for, as `resolveChildViews` returned them —
    /// spacers included, since a position is what matches a row to its loop.
    private let children: [ChildView]

    /// How each child, by its index in ``children``, was placed — `nil` until
    /// the first answer is asked for, then empty when no child was placed as a
    /// looped row, which is every container of hand-written rows.
    private var placements: [Placement]?

    /// The loops ``Placement/looped(loop:offset:)`` points into, in the order
    /// the walk met them.
    private var loops: [any KeyedLoop] = []

    /// Each child's OWN answer — its loop's, or its tag — once asked for,
    /// before any ordinal is considered. Sized to ``children`` on the first
    /// question.
    private var ownAnswers: [OwnAnswer] = []

    /// Every id a placed looped row answers to — built the first time an
    /// ordinal has to be checked against them, and only then.
    private var loopedIDs: Set<ID>?

    private enum Placement {
        /// Not a looped row, or a looped row this walk could not place.
        case handWritten
        /// A looped row: the `offset`-th row of `loops[loop]`.
        case looped(loop: Int, offset: Int)
    }

    /// A child's own answer: not yet asked, or what it names itself — `nil`
    /// when it names nothing this selection can hold.
    private enum OwnAnswer {
        case unasked
        case answered(ID?)
    }

    /// The answers for `children`, which `resolveChildViews` made of `content`.
    /// Nothing is walked here; see the type's note.
    init(content: some View, children: [ChildView]) {
        self.content = content
        self.children = children
    }

    /// The selection value of the child at `index`, the `ordinal`-th row of its
    /// container: a placed looped row's own loop's answer, else the
    /// hand-written rule. `nil` means the row draws but cannot be selected —
    /// see `ListRow.id`.
    func id(ofChildAt index: Int, ordinal: Int) -> ID? {
        if let own = ownAnswer(ofChildAt: index) { return own }
        // A looped row its loop named nothing this selection can hold — asked
        // tag first — or a hand-written row with no tag that casts: the ordinal
        // is all that is left, the number it had before.
        return ordinalID(ordinal)
    }

    /// What the child at `index` names itself, before any ordinal: a placed
    /// looped row's loop's answer — the row's tag, else its element's id — and
    /// any other row's own tag.
    private func ownAnswer(ofChildAt index: Int) -> ID? {
        let placements = placed()
        if ownAnswers.isEmpty {
            ownAnswers = [OwnAnswer](repeating: .unasked, count: children.count)
        }
        if case .answered(let answer) = ownAnswers[index] { return answer }
        let answer: ID?
        switch placements.isEmpty ? .handWritten : placements[index] {
        case .looped(let loop, let offset):
            answer = loops[loop].keyedRowSelectionID(at: offset)
        case .handWritten:
            let child = children[index]
            // A keyed child here is a loop's row this walk could not place,
            // and its tag is behind the value memo. A positional child is
            // never memoised, so the plain read is the whole answer for it,
            // and the memo cast is not paid on every hand-written row.
            answer =
                child.identityChildKey == nil
                ? extractTagValue(from: child.wrappedView, as: ID.self)
                : extractRowTagValue(from: child.wrappedView, as: ID.self)
        }
        ownAnswers[index] = .answered(answer)
        return answer
    }

    /// `ordinal` as a selection value, unless a looped row here already
    /// answers to it — see the type's note on why it yields.
    private func ordinalID(_ ordinal: Int) -> ID? {
        guard let id = ordinal as? ID else { return nil }
        let placements = placed()
        guard !placements.isEmpty else { return id }
        // Only a looped ROW's id: a looped `Section` is spliced as rows keyed
        // by its own items, so the group's id is no row's selection value, and
        // counted here it took a hand-written row's number away for nothing.
        // Every such row's answer is needed, so this is the one question that
        // resolves them all.
        let taken =
            loopedIDs
            ?? Set(
                placements.indices.compactMap { index -> ID? in
                    guard case .looped = placements[index], !Self.isSection(children[index])
                    else { return nil }
                    return ownAnswer(ofChildAt: index)
                })
        loopedIDs = taken
        return taken.contains(id) ? nil : id
    }

    /// The placement, made on the first question.
    private func placed() -> [Placement] {
        if let placements { return placements }
        let placements = place()
        self.placements = placements
        return placements
    }

    /// Walks the content and places its loops on the children.
    ///
    /// The content is walked only when some child IS keyed, so a container of
    /// hand-written rows pays one scan of the children it already has, and
    /// nothing is placed unless the walk found a loop. A failed placement
    /// places nothing at all.
    private func place() -> [Placement] {
        let keyed = children.indices.filter { children[$0].identityChildKey != nil }
        // A loop of sections — `ForEach(groups) { Section … }` — makes no rows
        // of its own: the list splices each section's rows, keyed by the
        // section's own items, and asks nothing here. So nothing is walked.
        guard !keyed.isEmpty, !keyed.allSatisfy({ Self.isSection(children[$0]) }) else { return [] }
        var runs: [KeyedRowRun] = []
        appendKeyedRowRuns(of: content, to: &runs)
        let loops = runs.compactMap { run -> (any KeyedLoop)? in
            if case .loop(let loop) = run { return loop }
            return nil
        }
        guard !loops.isEmpty,
            let placements = Self.placements(of: runs, onKeyed: keyed, of: children)
        else { return [] }
        self.loops = loops
        return placements
    }

    /// Whether `child` is a `Section`, which the list splices as rows of its
    /// own rather than asking an id of — the question `_ListCore`'s
    /// `sectionRow(of:)` asks, answered without building the section.
    static func isSection(_ child: ChildView) -> Bool {
        if child.wrappedView is SectionRowExtractor { return true }
        guard let memo = child.wrappedView as? any _ValueMemoWrapping else { return false }
        return memo.memoizedContentType is any SectionRowExtractor.Type
    }

    // MARK: Placing the loops

    /// Places each loop in `runs` on the keyed children it made, or answers
    /// `nil` when a loop's rows are not where the walk says they are.
    ///
    /// `keyed` holds the indices into `children` of the keyed ones, in order.
    /// Runs are counted off from the front until a provider whose rows cannot
    /// be counted, then from the back down to the last such provider; the
    /// uncountable provider between owns what is left.
    private static func placements(
        of runs: [KeyedRowRun], onKeyed keyed: [Int], of children: [ChildView]
    ) -> [Placement]? {
        var placements = [Placement](repeating: .handWritten, count: children.count)
        // Each run's loop number, in the order `place()` collects the loops.
        var loopNumbers: [Int] = []
        var loopCount = 0
        for run in runs {
            loopNumbers.append(loopCount)
            if run.isLoop { loopCount += 1 }
        }
        var front = 0
        var first = 0
        frontwards: while first < runs.count {
            switch runs[first] {
            case .loop(let loop):
                guard
                    place(
                        loop, number: loopNumbers[first], at: front, lowerBound: front,
                        keyed: keyed, children: children, into: &placements)
                else { return nil }
                front += loop.keyedRowCount
            case .outline:
                while front < keyed.count, isOutlineRow(children[keyed[front]]) { front += 1 }
            case .opaque:
                break frontwards
            }
            first += 1
        }
        var back = keyed.count
        var last = runs.count
        backwards: while last > first {
            switch runs[last - 1] {
            case .loop(let loop):
                let start = back - loop.keyedRowCount
                guard
                    place(
                        loop, number: loopNumbers[last - 1], at: start, lowerBound: front,
                        keyed: keyed, children: children, into: &placements)
                else { return nil }
                back = start
            case .outline:
                while back > front, isOutlineRow(children[keyed[back - 1]]) { back -= 1 }
            case .opaque:
                break backwards
            }
            last -= 1
        }
        // Every run was counted, so every keyed child must have been claimed:
        // one left over is one the walk does not know about.
        if first == last, front != back { return nil }
        return placements
    }

    /// Places `loop` — the `number`-th loop the walk met — on
    /// `keyed[start..<start + count]`, having checked that the first and the
    /// last of those rows carry the keys the loop gives them: `false` when they
    /// do not, or when the span falls outside `lowerBound..<keyed.count`.
    ///
    /// Records WHICH row of which loop each one is, and resolves nothing: the
    /// loop is asked for a row's answer only when that row's is asked for.
    private static func place(
        _ loop: any KeyedLoop, number: Int, at start: Int, lowerBound: Int, keyed: [Int],
        children: [ChildView], into placements: inout [Placement]
    ) -> Bool {
        let count = loop.keyedRowCount
        guard count > 0 else { return true }
        let end = start + count
        guard start >= lowerBound, end <= keyed.count,
            children[keyed[start]].identityChildKey == loop.keyedRowKey(at: 0),
            children[keyed[end - 1]].identityChildKey == loop.keyedRowKey(at: count - 1)
        else { return false }
        for offset in 0..<count {
            placements[keyed[start + offset]] = .looped(loop: number, offset: offset)
        }
        return true
    }

    /// Whether `child` is a row an `OutlineGroup` made, seen through the
    /// wrappers the splice puts round a modified provider's members.
    private static func isOutlineRow(_ child: ChildView) -> Bool {
        throughWrappers(child.wrappedView, as: (any OutlineRowMarking).self) != nil
    }
}

// MARK: - Where keyed rows come from

/// One provider's share of a flattened container's KEYED children, in the
/// order the splice emits them.
@MainActor
enum KeyedRowRun {
    /// A `ForEach`'s rows: exactly one per element, each keyed by its element.
    case loop(any KeyedLoop)
    /// An `OutlineGroup`'s rows: one per VISIBLE node, which only the outline's
    /// expansion state knows — so the run is recognised by its rows' type
    /// rather than counted. They keep the hand-written rule.
    case outline
    /// A provider this walk cannot see into, whose children may be keyed and
    /// cannot be counted — `MenuStyleConfiguration.Content`, or one added
    /// after this was written. They keep the hand-written rule.
    case opaque

    var isLoop: Bool {
        if case .loop = self { return true }
        return false
    }
}

/// A loop, asked about its rows by offset.
@MainActor
protocol KeyedLoop {
    /// How many rows the loop flattens into its container.
    var keyedRowCount: Int { get }

    /// The key the row at `offset` carries — its `identityChildKey`.
    func keyedRowKey(at offset: Int) -> String

    /// What the row at `offset` names itself when the loop is its container's
    /// whole content, without the index fallback.
    func keyedRowSelectionID<RowID: Hashable>(at offset: Int) -> RowID?
}

/// A view that flattens keyed rows into its container, or passes another's
/// through — `ForEach`, `OutlineGroup`, and the providers between them and the
/// container.
///
/// The same shape as `PickerOptionProvider`, asked a different question. The
/// wrappers that pass a provider's members through by ``ContentRewrapping`` or
/// as a `ModifiedView` need no conformance: ``appendKeyedRowRuns(of:to:)``
/// looks through every ``SingleContentWrapper`` that is also a
/// ``ChildViewProvider``, which is exactly when the splice does.
@MainActor
protocol KeyedRowProvider {
    /// Appends the runs of keyed rows this view flattens, in order.
    func appendKeyedRowRuns(to runs: inout [KeyedRowRun])
}

/// Appends the runs of keyed rows `view` flattens into its container, going
/// exactly where `resolveChildViews` flattens and nowhere else.
///
/// A view that is no provider is ONE child of its container, and a positional
/// one, so it adds nothing — `.onAppear` on a loop keeps the loop as one opaque
/// row, exactly as the splice does. A single-content wrapper is looked through
/// only when it is itself a provider: `.foregroundStyle` hands a loop's rows
/// out one by one. Any other provider is a run of its own that cannot be
/// counted.
@MainActor
func appendKeyedRowRuns(of view: some View, to runs: inout [KeyedRowRun]) {
    if let provider = view as? KeyedRowProvider {
        provider.appendKeyedRowRuns(to: &runs)
        return
    }
    guard view is ChildViewProvider else { return }
    if let wrapper = view as? any SingleContentWrapper {
        appendKeyedRowRuns(of: wrapper.wrappedContent, to: &runs)
    } else {
        runs.append(.opaque)
    }
}

extension TupleView: KeyedRowProvider {
    func appendKeyedRowRuns(to runs: inout [KeyedRowRun]) {
        for child in repeat each children {
            TUIkit.appendKeyedRowRuns(of: child, to: &runs)
        }
    }
}

extension Group: KeyedRowProvider {
    func appendKeyedRowRuns(to runs: inout [KeyedRowRun]) {
        TUIkit.appendKeyedRowRuns(of: content, to: &runs)
    }
}

extension ConditionalView: KeyedRowProvider {
    func appendKeyedRowRuns(to runs: inout [KeyedRowRun]) {
        switch self {
        case .trueContent(let content): TUIkit.appendKeyedRowRuns(of: content, to: &runs)
        case .falseContent(let content): TUIkit.appendKeyedRowRuns(of: content, to: &runs)
        }
    }
}

extension Optional: KeyedRowProvider where Wrapped: View {
    func appendKeyedRowRuns(to runs: inout [KeyedRowRun]) {
        // A `nil` still leaving keeps a slot in its container (see
        // `Optional.childViews`), but a positional one: no keyed row.
        if case .some(let wrapped) = self { TUIkit.appendKeyedRowRuns(of: wrapped, to: &runs) }
    }
}

extension OutlineGroup: KeyedRowProvider {
    func appendKeyedRowRuns(to runs: inout [KeyedRowRun]) {
        runs.append(.outline)
    }
}

/// What an `OutlineGroup`'s flattened row is, whatever it outlines.
@MainActor
private protocol OutlineRowMarking {}

extension _OutlineRow: OutlineRowMarking {}
