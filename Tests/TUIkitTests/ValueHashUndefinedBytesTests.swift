//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ValueHashUndefinedBytesTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import CTestSupport
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

// MARK: - Shapes

/// A view shaped as an app would write it: a flag, then a word. Seven bytes
/// of padding lie between them, and nothing writes them.
private struct PaddedRow: View {
    let flag: Bool
    let count: Int
    var body: some View { Text("\(count)") }
}

/// ``PaddedRow`` with two more words: too big to sit inside an existential's
/// three-word buffer, so an `AnyView` of it keeps it in a heap box that every
/// copy of the `AnyView` shares.
private struct BoxedPaddedRow: View {
    let flag: Bool
    let count: Int
    let first: Int
    let second: Int
    var body: some View { Text("\(count) \(first) \(second)") }
}

/// A view holding an optional string: `nil` is spelled in the string's spare
/// values, so its first word is written by nobody when `nil` is stored in
/// place.
private struct OptionalLabel: View {
    let label: String?
    var body: some View { Text(label ?? "-") }
}

/// A view holding an optional word: `nil` has a tag byte of its own.
private struct OptionalCount: View {
    let count: Int?
    var body: some View { Text(count.map(String.init) ?? "-") }
}

/// A payload enum of the kind an app declares: not opted in, so the value
/// hash cannot read it.
private enum AppChoice {
    case number(Int)
    case word(String)
}

/// A view holding one.
private struct HoldsAppChoice: View {
    let choice: AppChoice
    var body: some View { Text(label) }

    private var label: String {
        switch choice {
        case .number(let number): "\(number)"
        case .word(let word): word
        }
    }
}

/// ``HoldsAppChoice``'s control: the same body, over a value the hash reads.
private struct HoldsLabel: View {
    let label: String
    var body: some View { Text(label) }
}

/// A view holding an existential: `AnyEquatableBox` is `ForEach`'s row key.
private struct BoxHolder: View {
    let box: AnyEquatableBox
    var body: some View { EmptyView() }
}

/// A view holding a metatype's optional, then a word. Swift stores the
/// optional thin — one tag byte, the metatype itself in none — so seven bytes
/// of padding follow it, where the runtime's `Int.Type?` is a whole pointer.
private struct MetatypeOptionalRow: View {
    let kind: Int.Type?
    let count: Int
    var body: some View { Text(kind == nil ? "-" : "\(count)") }
}

/// A view holding a byte and a metatype's optional, then a field aligned to
/// sixteen: stored, the pair takes bytes 0..<2, the optional's tag at 1, and
/// 2..<16 are padding.
private struct MetatypePairRow: View {
    let pair: (UInt8, Int.Type?)
    let wide: SIMD4<Float>
    var body: some View { Text(pair.1 == nil ? "x" : "xx") }
}

/// A view holding an optional of a tuple — a payload enum, then a metatype —
/// then a field aligned to sixteen. Stored, the metatype takes no bytes and
/// the optional only the enum's (`nil` in its tag byte); padding runs from
/// there to `wide`. The runtime's tuple has the metatype as a pointer, in that
/// padding, and its optional spells `nil` there.
private struct MetatypeBehindAnEnumRow: View {
    let pair: (AppChoice, Int.Type)?
    let wide: SIMD4<Float>
    var body: some View { Text(pair == nil ? "x" : "xx") }

    /// Where the stored optional ends: the enum's bytes, `nil` among its
    /// spare tag values. (`MemoryLayout` of the optional itself answers as the
    /// runtime lays it out, the metatype a pointer.)
    static let pairEnd = MemoryLayout<AppChoice>.size

    /// Whether this is `(.number(5), Int.self)`, read through concrete Swift.
    var isFiveAndInt: Bool {
        guard case .number(5)? = pair?.0 else { return false }
        return pair?.1 == Int.self
    }
}

/// A view holding a struct imported from C whose bitfields the runtime's
/// field list leaves out, and drawn as wide as one of them says.
private struct BitfieldRow: View {
    let bits: CTestBitfields

    init(lo: UInt8) {
        var bits = CTestBitfields()
        bits.c = 1
        bits.lo = lo
        bits.x = 7
        self.bits = bits
    }

    var body: some View { Text(String(repeating: "x", count: Int(bits.lo))) }
}

// MARK: - Tests

/// The per-pass memos key a view by a hash of its value, and that hash read
/// the value's bytes, all of them — including bytes no field covers, whose
/// contents are whatever the memory held before: struct padding, the inactive
/// payload of a generic enum, the unused words of an existential's buffer, the
/// unwritten half of an optional's `nil`. Two equal values then hashed apart,
/// and the memo missed; which it did differed by platform and run (Linux
/// missed where macOS hit), and reading those bytes at all was reading
/// uninitialised memory. The hash reads a type by its `ValueHashPlan` now,
/// which never loads such a byte.
///
/// Each test here builds a value in memory of its own, writes three
/// different fills into bytes the value leaves undefined — the value is the
/// same after each — and hashes it where it lies, through
/// `viewValueHash(at:in:)`: a copy would not carry the fill.
@MainActor
@Suite("The value hash reads no byte a value leaves undefined")
struct ValueHashUndefinedBytesTests {
    /// The hash of `value`, placed in memory of its own, after each of three
    /// fills of `bytes`; `check` runs after each fill, to confirm the fill left
    /// the value as it was.
    private func hashes<V: View>(
        of value: V, filling bytes: [Range<Int>], check: (V) -> Bool = { _ in true }
    ) -> (hashes: [Int?], valueUnchanged: Bool) {
        let cache = RenderCache()
        let pointer = UnsafeMutablePointer<V>.allocate(capacity: 1)
        pointer.initialize(to: value)
        defer {
            pointer.deinitialize(count: 1)
            pointer.deallocate()
        }
        var unchanged = true
        let found = [UInt8(0xAA), 0x55, 0x00].map { fill -> Int? in
            poke(UnsafeMutableRawPointer(pointer), bytes, fill)
            unchanged = unchanged && check(pointer.pointee)
            return viewValueHash(at: pointer, in: cache)
        }
        return (found, unchanged)
    }

    private func poke(_ base: UnsafeMutableRawPointer, _ ranges: [Range<Int>], _ fill: UInt8) {
        for range in ranges {
            for offset in range { base.storeBytes(of: fill, toByteOffset: offset, as: UInt8.self) }
        }
    }

    private func hash<V: View>(_ value: V, cache: RenderCache) -> Int? {
        var copy = value
        return withUnsafePointer(to: &copy) { viewValueHash(at: $0, in: cache) }
    }

    // MARK: Equal values, undefined bytes

    @Test("An app's padded view in a wrapper hashes the same whatever its padding holds")
    func paddedViewInAWrapper() throws {
        let wrapped = PaddedRow(flag: true, count: 7).padding(1)
        let gaps = interiorPadding(of: type(of: wrapped))
        try #require(!gaps.isEmpty, "the probe must have padding to fill")
        let result = hashes(of: wrapped, filling: gaps)
        #expect(Set(result.hashes).count == 1 && result.hashes[0] != nil, "\(result.hashes)")
    }

    @Test("A conditional's inactive payload is not read")
    func conditionalInactivePayload() throws {
        typealias Conditional = ConditionalView<Text, EmptyView>
        // The false branch is empty, so the whole payload area — the size of
        // a `Text` — is written by nobody; the case is in the byte after it.
        try #require(MemoryLayout<Conditional>.size == MemoryLayout<Text>.size + 1)
        let result = hashes(
            of: Conditional.falseContent(EmptyView()),
            filling: [0..<MemoryLayout<Text>.size],
            check: { if case .falseContent = $0 { true } else { false } })
        #expect(result.valueUnchanged)
        #expect(Set(result.hashes).count == 1 && result.hashes[0] != nil, "\(result.hashes)")
    }

    #if _pointerBitWidth(_64)
    @Test("An optional string's nil hashes the same whatever its unwritten word holds")
    func optionalStringNil() throws {
        // `nil` is one of the string's spare values in its SECOND word; the
        // first is left as it was.
        try #require(MemoryLayout<String?>.size == 16)
        let result = hashes(of: OptionalLabel(label: nil), filling: [0..<8], check: { $0.label == nil })
        #expect(result.valueUnchanged)
        #expect(Set(result.hashes).count == 1 && result.hashes[0] != nil, "\(result.hashes)")
    }

    @Test("An existential holding a word hashes the same whatever its unused buffer words hold")
    func existentialUnusedWords() throws {
        // Three words of inline buffer, then the type, then the witness table:
        // a one-word payload leaves words 1 and 2 unused.
        try #require(MemoryLayout<AnyEquatableBox>.size == 5 * 8)
        let result = hashes(
            of: BoxHolder(box: AnyEquatableBox(5)), filling: [8..<24],
            check: { $0.box == AnyEquatableBox(5) })
        #expect(result.valueUnchanged)
        #expect(Set(result.hashes).count == 1 && result.hashes[0] != nil, "\(result.hashes)")
    }

    /// The hash cannot tell a metatype stored thin from one stored as a
    /// pointer, so it does not hash a view holding one: all three answers are
    /// "no hash", which is the same answer.
    @Test("A view holding a metatype's optional hashes the same whatever the padding after it holds")
    func metatypeOptionalPadding() throws {
        try #require(MemoryLayout<MetatypeOptionalRow>.size == 16)
        let result = hashes(
            of: MetatypeOptionalRow(kind: Int.self, count: 7), filling: [1..<8],
            check: { $0.kind == Int.self && $0.count == 7 })
        #expect(result.valueUnchanged)
        #expect(Set(result.hashes).count == 1, "\(result.hashes)")
    }
    #endif

    /// The same, with the metatype behind an element the hash cannot read
    /// either: `nil`, and the padding between the optional and the next field.
    @Test("A view holding a metatype behind a payload enum in an optional tuple hashes the same whatever the padding holds")
    func metatypeBehindAnEnumPadding() throws {
        let wide = try #require(MemoryLayout<MetatypeBehindAnEnumRow>.offset(of: \.wide))
        let padding = MetatypeBehindAnEnumRow.pairEnd..<wide
        try #require(!padding.isEmpty, "the probe must have padding to fill")
        let result = hashes(
            of: MetatypeBehindAnEnumRow(pair: nil, wide: .zero), filling: [padding], check: { $0.pair == nil })
        #expect(result.valueUnchanged)
        #expect(Set(result.hashes).count == 1, "\(result.hashes)")
    }

    /// End to end: the memo, not the hash. The content of an `AnyView` lives
    /// in a heap box every copy shares, so filling its padding between two
    /// measures changes nothing a measure could see — and the second must be
    /// served.
    #if _pointerBitWidth(_64)
    @Test("An erased view measured twice is served the second time, whatever its padding held")
    func erasedPaddingIsNotAMiss() throws {
        let context = memoisedContext()
        let cache = try #require(context.renderCache)
        let row = BoxedPaddedRow(flag: true, count: 3, first: 4, second: 5)
        let gaps = interiorPadding(of: BoxedPaddedRow.self)
        try #require(gaps == [1..<8])
        let erased = AnyView(row)
        // The box: a heap object whose header is two words, then the payload
        // at the payload's alignment. Checked against the value itself before
        // anything is written there.
        let box = withUnsafeBytes(of: erased) { $0.load(as: UnsafeMutableRawPointer.self) }
        let content = box + 16
        try #require(
            withUnsafeBytes(of: row) { source in
                (0..<source.count).allSatisfy { index in
                    gaps.contains { $0.contains(index) }
                        || source[index] == content.load(fromByteOffset: index, as: UInt8.self)
                }
            })
        let unspecified = ProposedSize(width: nil, height: nil)
        poke(content, gaps, 0xAA)
        let first = measureChild(erased, proposal: unspecified, context: context)
        let before = cache.measureMemoTotals
        poke(content, gaps, 0x55)
        let second = measureChild(erased, proposal: unspecified, context: context)

        #expect(second == first)
        #expect(cache.measureMemoTotals.hits == before.hits + 1)
        #expect(cache.measureMemoTotals.misses == before.misses)
    }
    #endif

    // MARK: A value the hash cannot read

    /// A payload enum an app declares cannot be read without reading bytes one
    /// of its values may leave undefined, so a view holding one has no hash:
    /// the memo measures it every time, looks nothing up and keeps nothing —
    /// a lost hit, never a wrong answer. Its body's own views are keyed as
    /// ever.
    @Test("A view the hash cannot read is measured every time and kept nowhere")
    func unhashableViewIsMeasuredNotKept() throws {
        let context = memoisedContext()
        let cache = try #require(context.renderCache)
        let view = HoldsAppChoice(choice: .word("four"))
        #expect(hash(view, cache: cache) == nil)
        let unspecified = ProposedSize(width: nil, height: nil)
        let bypassesBefore = cache.measureMemoBypasses
        let entriesBefore = cache.measureEntryCount
        let first = measureChild(view, proposal: unspecified, context: context)
        // Kept: the body's `Text`, and not the view around it.
        let keptByTheView = cache.measureEntryCount - entriesBefore
        let second = measureChild(view, proposal: unspecified, context: context)
        #expect(first == second)
        #expect(first.width == 4)
        #expect(cache.measureMemoBypasses == bypassesBefore + 2)
        // The control, the same body over a value the hash reads, keeps one
        // entry more: its own.
        let controlBefore = cache.measureEntryCount
        _ = measureChild(HoldsLabel(label: "five"), proposal: unspecified, context: context)
        #expect(cache.measureEntryCount - controlBefore == keptByTheView + 1)
    }

    /// Two values of a struct imported from C that differ only in a bitfield,
    /// at one identity in one pass — the shape of a form's labels measured
    /// twice (Performance-profile §60). Taking the gap the bitfields sit in
    /// for padding, the plan
    /// read the rest and keyed both alike, and the second was served the
    /// first's size.
    @Test("Values that differ only in a C bitfield are never served each other's size")
    func importedBitfieldsAreNotServedAcross() throws {
        let context = memoisedContext()
        let cache = try #require(context.renderCache)
        let unspecified = ProposedSize(width: nil, height: nil)
        let bypassesBefore = cache.measureMemoBypasses
        let one = measureChild(BitfieldRow(lo: 1), proposal: unspecified, context: context)
        let two = measureChild(BitfieldRow(lo: 2), proposal: unspecified, context: context)
        #expect(one.width == 1)
        #expect(two.width == 2)
        #expect(cache.measureMemoBypasses == bypassesBefore + 2)
    }

    /// An `AnyView` of a stack holding an `AnyView` …, far deeper than any
    /// stack. The measure guards its own descent and truncates the chain, but
    /// hashes each level before it descends, and a level's hash covers every
    /// level below it: the hash overflowed the stack there (a debug build,
    /// from a chain 2,000 deep), where the key it replaced — the box's
    /// address — had nothing to walk. The hash stops when the stack runs low
    /// now, and a level too deep to hash is measured unkeyed.
    @Test("An erased chain deeper than the stack is measured and truncated, not overflowed in the hash")
    func erasedChainDeeperThanTheStack() throws {
        let context = memoisedContext()
        let cache = try #require(context.renderCache)
        var levels = erasedChain(depth: 50_000)
        defer { releaseFromTheTop(&levels) }
        let bypassesBefore = cache.measureMemoBypasses
        let size = measureChild(
            levels[levels.count - 1], proposal: ProposedSize(width: nil, height: nil), context: context)
        #expect(size.height > 0)
        #expect(cache.measureMemoBypasses > bypassesBefore)
    }

    // MARK: Different values stay apart

    @Test("Frames of different widths hash apart")
    func frameWidths() {
        let cache = RenderCache()
        #expect(hash(Text("x").frame(width: 5), cache: cache) != hash(Text("x").frame(width: 6), cache: cache))
    }

    @Test("The two branches of a conditional over one value hash apart")
    func conditionalBranches() {
        let cache = RenderCache()
        typealias Conditional = ConditionalView<Text, Text>
        #expect(
            hash(Conditional.trueContent(Text("x")), cache: cache)
                != hash(Conditional.falseContent(Text("x")), cache: cache))
    }

    @Test("nil and a value that is all zeros hash apart")
    func nilAgainstZero() {
        let cache = RenderCache()
        #expect(hash(OptionalCount(count: nil), cache: cache) != hash(OptionalCount(count: 0), cache: cache))
        #expect(hash(OptionalLabel(label: nil), cache: cache) != hash(OptionalLabel(label: ""), cache: cache))
    }

    @Test("A view and the same view erased twice hash apart")
    func erasedOnceAgainstTwice() {
        let cache = RenderCache()
        let text = Text("x")
        #expect(hash(AnyView(text), cache: cache) != hash(AnyView(AnyView(text)), cache: cache))
    }

    @Test("The same bits in an existential as two different types hash apart")
    func existentialTypes() {
        let cache = RenderCache()
        #expect(
            hash(BoxHolder(box: AnyEquatableBox(5 as Int)), cache: cache)
                != hash(BoxHolder(box: AnyEquatableBox(5 as UInt)), cache: cache))
    }

    /// Only the tag byte at offset 1 tells these two apart, and a hash that
    /// laid the pair out as the runtime does — the optional at 8 — never read
    /// it. The padding after the pair is filled the same in both.
    @Test("Views that differ only in a metatype's optional never share a hash")
    func metatypeOptionalCases() {
        let some = hashes(of: MetatypePairRow(pair: (1, Int.self), wide: .zero), filling: [2..<16])
        let none = hashes(of: MetatypePairRow(pair: (1, nil), wide: .zero), filling: [2..<16])
        #expect(some.hashes[0] == nil || some.hashes[0] != none.hashes[0], "\(some.hashes) \(none.hashes)")
    }

    /// Only the enum's tag byte tells these two apart as stored; a hash that
    /// asked `== nil` of the tuple as the runtime lays it out read the padding
    /// instead, and with it filled with zeros took the value for `nil`.
    @Test("Views that differ only in whether an optional tuple holding a metatype is nil never share a hash")
    func metatypeBehindAnEnumCases() throws {
        let wide = try #require(MemoryLayout<MetatypeBehindAnEnumRow>.offset(of: \.wide))
        let padding = MetatypeBehindAnEnumRow.pairEnd..<wide
        try #require(!padding.isEmpty, "the probe must have padding to fill")
        let some = hashes(
            of: MetatypeBehindAnEnumRow(pair: (.number(5), Int.self), wide: .zero), filling: [padding],
            check: \.isFiveAndInt)
        let none = hashes(of: MetatypeBehindAnEnumRow(pair: nil, wide: .zero), filling: [padding], check: { $0.pair == nil })
        #expect(some.valueUnchanged && none.valueUnchanged)
        for (someHash, noneHash) in zip(some.hashes, none.hashes) {
            #expect(someHash == nil || someHash != noneHash, "\(some.hashes) \(none.hashes)")
        }
    }

    @Test("Equal values built apart hash the same")
    func equalValues() {
        let cache = RenderCache()
        let frames = [5, 5].map { hash(Text("x").frame(width: $0), cache: cache) }
        let counts = [3, 3].map { hash(OptionalCount(count: $0), cache: cache) }
        #expect(frames[0] == frames[1])
        #expect(counts[0] == counts[1])
    }

    /// The render loop's shape: an isolated cache and the volatile-read tracker
    /// whose presence is what turns the memo on at all.
    private func memoisedContext() -> RenderContext {
        var context = makeRenderContext(width: 80, height: 24)
        let storage = StateStorage()
        context.environment.stateStorage = storage
        context.stateStorage = storage
        context.environment.installVolatileReadTracker(VolatileReadTracker())
        return context
    }
}
