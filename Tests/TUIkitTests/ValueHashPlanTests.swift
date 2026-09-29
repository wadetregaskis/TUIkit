//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ValueHashPlanTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import CTestSupport
import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

// MARK: - Shapes

/// A flag, then a word: seven bytes of padding between.
private struct PaddedRow: View {
    let flag: Bool
    let count: Int
    var body: some View { EmptyView() }
}

private protocol Shape {}
extension Int: Shape {}

private struct HoldsExistentials {
    let flag: Bool
    let shape: any Shape
    let anything: Any
}

private struct HoldsConstrainedExistential {
    let items: any Collection<Int>
}

private enum Choice: Equatable {
    case number(Int)
    case word(UInt32)
}

/// ``Choice``, opted in.
private enum MarkedChoice: Equatable, _AllBytesDefined {
    case number(Int)
    case word(UInt32)
}

/// A struct marked as if it were an enum: the marker is refused, and the
/// struct bypasses.
private struct MarkedStruct: _AllBytesDefined {
    let flag: Bool
    let count: Int
}

/// ``MarkedChoice``, generic: generic code can build its cases through the
/// enum's inject witness, which writes a smaller case's payload in part, so
/// the marker is refused.
private enum MarkedGeneric<Payload>: _AllBytesDefined {
    case number(Int)
    case word(UInt32)
}

private enum Generic<Payload> {
    case some(Payload)
    case other(Int)
}

private final class Referent {}

private protocol ClassBound: AnyObject {}
extension Referent: ClassBound {}

/// References the runtime manages. Held strongly, `bound` would be an optional
/// of a class-bound existential, which plans as a typed step that loads it as
/// one; `referent` would plan whole either way, by the optional's one-scalar
/// rule, so it alone cannot tell the two readings apart.
private struct HoldsWeak {
    weak var referent: Referent?
    weak var bound: (any ClassBound)?
    unowned let owner: Referent
    unowned(unsafe) let unsafeOwner: Referent
    let count: Int
}

/// A field of no size after a sized one, in a type whose layout is fixed at
/// compile time: the runtime reports the empty field at offset 0, under the
/// field declared before it.
private struct Marker {}

private struct HoldsMarker: View {
    let count: Int
    let marker: Marker
    let placeholder: EmptyView
    var body: some View { EmptyView() }
}

private struct HoldsBitfields: View {
    let bits: CTestBitfields
    var body: some View { EmptyView() }
}

/// A view holding an optional string: `nil` is spelled in the string's spare
/// values, so its first word is written by nobody when `nil` is stored in
/// place.
private struct OptionalLabel: View {
    let label: String?
    var body: some View { EmptyView() }
}

private struct BoxHolder: View {
    let box: AnyEquatableBox
    var body: some View { EmptyView() }
}

/// A metatype with only one value, as a struct stores it: in no bytes.
private struct HoldsMetatype {
    let kind: Int.Type
}

/// Its optional, as a struct stores it: one tag byte.
private struct HoldsMetatypeOptionalAlone {
    let kind: Int.Type?
}

/// The optional's tag byte, then seven bytes of padding, then a word — where
/// the runtime's `Int.Type?` is a pointer, and would cover the padding.
private struct HoldsMetatypeOptional: View {
    let kind: Int.Type?
    let count: Int
    var body: some View { EmptyView() }
}

/// A byte and a metatype's optional, then a field aligned to sixteen. Stored,
/// the pair takes bytes 0..<2, the optional's tag at 1; the runtime's tuple
/// puts the optional at 8, so a plan from it never read byte 1.
private struct HoldsMetatypePair: View {
    let pair: (UInt8, Int.Type?)
    let wide: SIMD4<Float>
    var body: some View { EmptyView() }
}

/// A type parameter's metatype: a pointer, since it may hold any type — and
/// reported exactly as a thin one is.
private struct HoldsGenericMetatype<Subject>: View {
    let subject: Subject.Type
    let count: Int
    var body: some View { EmptyView() }
}

/// A payload enum that has not opted in: it bypasses.
private enum TupleChoice {
    case number(Int)
    case word(String)
}

/// An optional of a tuple whose first element bypasses and whose second is a
/// thin metatype, then a field aligned to sixteen. Stored, the optional takes
/// the enum's bytes and no more (0..<17 on a 64-bit target, `nil` in the enum's
/// tag byte) and padding runs to `wide`; the runtime's tuple has the metatype
/// as a pointer at 24, and its optional spells `nil` there — in the padding.
private struct HoldsMetatypeBehindABypass: View {
    let pair: (TupleChoice, Int.Type)?
    let wide: SIMD4<Float>
    var body: some View { EmptyView() }
}

/// The optional alone, as a struct stores it: `MemoryLayout` of the optional
/// itself answers as the runtime lays it out, the metatype a pointer.
private struct HoldsMetatypeBehindABypassAlone {
    let pair: (TupleChoice, Int.Type)?
}

/// Metatypes that are pointers however they are stored.
private struct HoldsExistentialMetatypes: View {
    let any: Any.Type
    let shape: any Shape.Type
    var body: some View { EmptyView() }
}

// MARK: - Tests

/// The value hash's per-type plans: which bytes of a type's values it reads,
/// and which parts it reads through typed Swift instead — built from the type
/// alone, so these pin the RULES (see `ValueHashPlanBuilder`), and the
/// property that matters above all: no plan loads a byte a value can leave
/// undefined.
@MainActor
@Suite("A type's value-hash plan reads only the bytes its values define")
struct ValueHashPlanTests {
    /// The table the plans below are read from. It owns their storage, so it
    /// lives as long as the test does: a plan read from a table that has gone
    /// is read from freed memory.
    private let plans = ValueHashPlans()

    private func plan(_ type: Any.Type) -> ValueHashPlan {
        plan(type, in: plans)
    }

    private func plan(_ type: Any.Type, in plans: ValueHashPlans) -> ValueHashPlan {
        plans.plan(for: type).pointee
    }

    /// `0..<size` less `gaps`, as ranges.
    private func complement(of gaps: [Range<Int>], in size: Int) -> [Range<Int>] {
        var found: [Range<Int>] = []
        var start = 0
        for gap in gaps.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if gap.lowerBound > start { found.append(start..<gap.lowerBound) }
            start = max(start, gap.upperBound)
        }
        if start < size { found.append(start..<size) }
        return found
    }

    // MARK: Structs and tuples

    @Test("A padded view in a wrapper reads exactly the bytes that are not padding")
    func paddedWrapper() {
        let type = type(of: PaddedRow(flag: true, count: 1).padding(1))
        let found = plan(type)
        let gaps = interiorPadding(of: type)
        #expect(!gaps.isEmpty)
        #expect(found.shape == .runs)
        #expect(found.definedRanges == complement(of: gaps, in: found.size))
    }

    @Test("A padding-free struct is dense: hashed as it lies, word by word")
    func denseStruct() {
        #expect(plan(FlexibleFrameView<EmptyView>.self).shape == .dense)
        #expect(plan((Int, Int).self).shape == .dense)
        #expect(plan(EmptyView.self).shape == .dense)
    }

    @Test("A tuple's padding is skipped as a struct's is")
    func paddedTuple() {
        let found = plan((Bool, Int, UInt8, Int32).self)
        #expect(found.definedRanges == [0..<1, 8..<17, 20..<24])
    }

    @Test("A field of no size has nothing to read, wherever the runtime puts it")
    func zeroSizeFields() {
        // Offset 0 for both empty fields, under `count`: taken as an overlap,
        // this bypassed a view with nothing wrong with it.
        #expect(RuntimeFields.fields(of: HoldsMarker.self).map(\.offset) == [0, 0, 0])
        #expect(plan(HoldsMarker.self).shape == .dense)
        // A tuple's layout is worked out at run time, which puts an empty
        // element at the end so far instead.
        #expect(plan((Int, Marker, UInt8).self).definedRanges == [0..<9])
    }

    /// The runtime's field list for a struct imported from C is the one the
    /// importer wrote, which leaves out what Swift cannot declare — bitfields
    /// above all — and says nothing about what it left out. A gap shaped like
    /// alignment padding may be a dropped field's bytes.
    @Test("A gap in a struct imported from C is never taken for padding")
    func importedStructGaps() {
        #expect(RuntimeFields.fields(of: CTestBitfields.self).map(\.offset) == [0, 4])
        let found = plan(HoldsBitfields.self)
        #expect(found.shape == .bypass)
        #expect(found.bypassReason?.contains("imported from C") == true, "\(found.bypassReason ?? "")")
        // Real padding in an imported struct looks the same, and costs a hit.
        #expect(plan(CTestPadded.self).shape == .bypass)
        // An imported struct with no gap is read as any other.
        #expect(plan(timespec.self).shape == .dense)
        // Values that differ only in a bitfield must not share a key.
        var first = CTestBitfields()
        first.c = 1
        first.lo = 1
        first.x = 7
        var second = first
        second.lo = 2
        let hashes = [first, second].map { hash(HoldsBitfields(bits: $0), plans: plans) }
        #expect(hashes[0] == nil || hashes[0] != hashes[1], "\(hashes)")
    }

    #if !(os(Windows) || os(Android)) && (arch(i386) || arch(x86_64))
    /// x87's 80-bit float is stored in ten bytes of the sixteen it occupies.
    @Test("An 80-bit float reads the ten bytes a store writes, not the six after them")
    func float80() {
        #expect(MemoryLayout<Float80>.size == 16)
        #expect(plan(Float80.self).definedRanges == [0..<10])
        #expect(plan((Float80, Int).self).definedRanges == [0..<10, 16..<24])
        #expect(plan(Float80?.self).shape == .steps)
    }
    #endif

    // MARK: Optionals

    @Test("An optional whose every byte is always written is read whole")
    func wholeOptionals() {
        // A tag byte of its own over a dense payload: nil zero-fills the payload.
        // An optional's spare tag values are not spare values of its own, so
        // `Int??` has a tag byte of its own too.
        #expect(MemoryLayout<Int?>.size == MemoryLayout<Int>.size + 1)
        #expect(MemoryLayout<Int??>.size == MemoryLayout<Int?>.size + 1)
        for type in [Int?.self, Int??.self, Date?.self, (UInt8, UInt8)?.self, EmptyView?.self] as [Any.Type] {
            #expect(plan(type).shape == .dense, "\(type)")
        }
        // One scalar whose spare values spell nil, written whole.
        for type in [Bool?.self, [Int]?.self, Referent?.self, Bool??.self] as [Any.Type] {
            #expect(plan(type).shape == .dense, "\(type)")
        }
    }

    @Test("An optional whose nil leaves bytes unwritten reads its case through == nil")
    func typedOptionals() {
        // nil is in the payload's spare values, and the rest of the payload is
        // left as it was: the string's first word, a closure's context, the
        // word after a padded row's flag, an existential's buffer.
        for type in [String?.self, (() -> Void)?.self, PaddedRow?.self, AnyView?.self] as [Any.Type] {
            let found = plan(type)
            #expect(found.shape == .steps, "\(type)")
            #expect(found.stepDescriptions == ["0: \(type)"], "\(type)")
        }
        // One builtin, but wider than a word: only scalars of a word or less
        // are measured to write their `nil` whole.
        #expect(MemoryLayout<UnownedSerialExecutor?>.size == MemoryLayout<UnownedSerialExecutor>.size)
        #expect(MemoryLayout<UnownedSerialExecutor>.size > MemoryLayout<UInt>.size)
        #expect(plan(UnownedSerialExecutor?.self).stepDescriptions == ["0: Optional<UnownedSerialExecutor>"])
    }

    // MARK: Typed Swift

    @Test("A conditional reads its branch by a switch; an erased view opens its content")
    func conditionalAndErased() {
        #expect(plan(ConditionalView<EmptyView, EmptyView>.self).stepDescriptions
            == ["0: ConditionalView<EmptyView, EmptyView>"])
        #expect(plan(AnyView.self).stepDescriptions == ["0: existential view"])
    }

    @Test("An existential field is opened through its static type, never read from its container")
    func existentialFields() {
        #expect(plan(AnyEquatableBox.self).stepDescriptions == ["0: existential equatable"])
        let found = plan(HoldsExistentials.self)
        #expect(found.definedRanges == [0..<1])
        #expect(found.stepDescriptions.count == 2)
        #expect(found.stepDescriptions.last == "48: existential any")
    }

    @Test("A weak or unowned reference is read as its bytes, never loaded as the type it is declared as")
    func weakField() {
        #expect(RuntimeFields.fields(of: HoldsWeak.self).map(\.isStrong) == [false, false, false, false, true])
        let found = plan(HoldsWeak.self)
        #expect(found.shape == .dense)
        #expect(found.stepDescriptions.isEmpty)
    }

    // MARK: Metatypes

    /// Swift stores a metatype that has only one value in no bytes, and the
    /// runtime reports every metatype as a pointer. A plan from the runtime's
    /// layout read seven bytes of padding as the rest of a `Int.Type?`, and
    /// never read the tag byte of one that a tuple put at offset 1 where the
    /// runtime's tuple has it at 8.
    @Test("A metatype bypasses, and so does an optional or a tuple holding one")
    func metatypesBypass() {
        // Stored, and as the runtime has it.
        #expect(MemoryLayout<HoldsMetatype>.size == 0)
        #expect(MemoryLayout<HoldsMetatypeOptionalAlone>.size == 1)
        #expect(MemoryLayout<Int.Type>.size == MemoryLayout<UnsafeRawPointer>.size)
        #expect(MemoryLayout<Int.Type?>.size == MemoryLayout<UnsafeRawPointer>.size)
        #expect(
            RuntimeFields.fields(of: (UInt8, Int.Type?).self).map(\.offset)
                == [0, MemoryLayout<UnsafeRawPointer>.size])
        // A type parameter's is a pointer, and bypasses too: nothing the
        // runtime says tells it from a thin one, nor a class's from either.
        let types: [Any.Type] = [
            HoldsMetatypeOptional.self, HoldsMetatypePair.self, HoldsGenericMetatype<Int>.self,
            HoldsGenericMetatype<Referent>.self, HoldsMetatypeOptionalAlone.self, Int.Type?.self,
        ]
        for type in types {
            let found = plan(type)
            #expect(found.shape == .bypass, "\(type)")
            #expect(found.bypassReason?.contains("a metatype") == true, "\(type): \(found.bypassReason ?? "")")
        }
        // An existential metatype is a pointer (and its witness tables)
        // wherever it is stored.
        #expect(plan(HoldsExistentialMetatypes.self).shape == .dense)
    }

    @Test("Views that differ only in a metatype's optional never share a key, and none hashes padding")
    func metatypeHashes() {
        // The pair's padding, 2..<16, filled the same in both.
        let some = hashes(of: HoldsMetatypePair(pair: (1, Int.self), wide: .zero), filling: [2..<16], plans: plans)
        let none = hashes(of: HoldsMetatypePair(pair: (1, nil), wide: .zero), filling: [2..<16], plans: plans)
        #expect(some[0] == nil || some[0] != none[0], "\(some) \(none)")
        let padded = hashes(of: HoldsMetatypeOptional(kind: Int.self, count: 7), filling: [1..<8], plans: plans)
        #expect(Set(padded).count == 1, "\(padded)")
    }

    /// A tuple's fields are planned in the order the runtime lays them out,
    /// and the first that bypasses ends the walk — so a payload enum before a
    /// thin metatype hid the metatype, and the optional around the tuple fell
    /// back to its typed step, which asks `== nil` of the tuple as the runtime
    /// lays it out: the metatype's word, which is padding as stored.
    @Test("An optional tuple bypasses when an element bypasses before its metatype is reached")
    func metatypeBehindABypass() throws {
        // Stored, and as the runtime has it.
        let stored = MemoryLayout<HoldsMetatypeBehindABypassAlone>.size
        let wide = try #require(MemoryLayout<HoldsMetatypeBehindABypass>.offset(of: \.wide))
        #expect(stored == MemoryLayout<TupleChoice>.size)
        #expect(stored < wide)
        #expect(MemoryLayout<(TupleChoice, Int.Type)?>.size > stored)
        #expect(RuntimeFields.fields(of: (TupleChoice, Int.Type).self).last?.offset ?? 0 >= stored)
        let found = plan(HoldsMetatypeBehindABypass.self)
        #expect(found.shape == .bypass, "\(found.stepDescriptions)")
        // The padding between the optional and `wide`, filled alike in both.
        let some = hashes(
            of: HoldsMetatypeBehindABypass(pair: (.number(5), Int.self), wide: .zero), filling: [stored..<wide],
            plans: plans)
        let none = hashes(of: HoldsMetatypeBehindABypass(pair: nil, wide: .zero), filling: [stored..<wide], plans: plans)
        for (someHash, noneHash) in zip(some, none) {
            #expect(someHash == nil || someHash != noneHash, "\(some) \(none)")
        }
        #expect(Set(none).count == 1, "\(none)")
    }

    // MARK: Depth

    /// An `AnyView` of a stack holding an `AnyView` …, far deeper than any
    /// stack can hash: the hash recurses as deep as a value goes through its
    /// existentials, so it stops when the stack runs low, and the value goes
    /// unhashed. Before it did, this overflowed the stack.
    @Test("A value too deep to hash goes unhashed rather than overflowing the stack")
    func erasedChainTooDeepToHash() {
        var levels = erasedChain(depth: 50_000)
        defer { releaseFromTheTop(&levels) }
        let truncations = StackGuard.truncationCount
        #expect(hash(levels[levels.count - 1], plans: plans) == nil)
        // Giving a value up unhashed cuts no tree short: not a truncation.
        #expect(StackGuard.truncationCount == truncations)
        // A shallow one hashes.
        #expect(hash(levels[3], plans: plans) != nil)
    }

    /// The steps run off the main actor and compare the stack pointer with the
    /// floor their entry read from the stack guard. An entry that finds no
    /// headroom must leave every opening to give up — and only openings: a
    /// value with steps but no existential is hashed as before.
    @Test("An entry with no headroom left opens no existential, and hashes the rest")
    func noHeadroomAtTheEntry() {
        let saved = StackGuard.cachedExtent
        defer { StackGuard.cachedExtent = saved }
        let erased = AnyView(Text("x"))
        let conditional = ConditionalView<Text, EmptyView>.trueContent(Text("x"))
        #expect(hash(erased, plans: plans) != nil)

        let stackPointer = StackGuard.currentStackPointer()
        let megabyte: UInt = 1 << 20
        StackGuard.cachedExtent = StackGuard.StackExtent(
            low: stackPointer - megabyte, floor: stackPointer + megabyte, high: stackPointer + 2 * megabyte)
        #expect(hash(erased, plans: plans) == nil)
        #expect(hash(conditional, plans: plans) != nil)

        StackGuard.cachedExtent = saved
        #expect(hash(erased, plans: plans) != nil)
    }

    // MARK: Bypass

    @Test("A payload enum that has not opted in bypasses, and says where")
    func payloadEnumsBypass() {
        let result = plan(Result<Int, any Error>.self)
        #expect(result.shape == .bypass)
        #expect(result.bypassReason?.contains("payload enum") == true)
        #expect(plan(Choice.self).shape == .bypass)
        #expect(plan(Generic<Int>.self).shape == .bypass)
    }

    @Test("A constrained existential bypasses")
    func constrainedExistentialBypasses() {
        #expect(plan(HoldsConstrainedExistential.self).shape == .bypass)
    }

    @Test("A struct whose field metadata was stripped bypasses")
    func strippedMetadataBypasses() {
        let stripped = ValueHashPlans(builder: ValueHashPlanBuilder(listFields: { _ in [] }))
        let found = plan(PaddedRow.self, in: stripped)
        #expect(found.shape == .bypass)
        #expect(found.bypassReason?.contains("no field metadata") == true)
        // A type of no size has nothing to read, stripped or not.
        #expect(plan(EmptyView.self, in: stripped).shape == .dense)
    }

    @Test("A non-generic trivial enum that opts in is read whole; a struct or a generic enum carrying the marker bypasses")
    func allBytesDefinedMarker() {
        #expect(plan(MarkedChoice.self).shape == .dense)
        let marked = plan(MarkedStruct.self)
        #expect(marked.shape == .bypass)
        let generic = plan(MarkedGeneric<Int>.self)
        #expect(generic.shape == .bypass)
        #expect(generic.bypassReason?.contains("not a trivial non-generic enum") == true, "\(generic.bypassReason ?? "")")
    }

    // MARK: Coverage

    @Test("The field types views hold most do not bypass")
    func commonFieldTypes() {
        let types: [Any.Type] = [
            String.self, Substring.self, Character.self, [Int].self, [String: Int].self, Set<Int>.self,
            Date?.self, UUID.self, URL.self, Bool.self, Double.self, Int.self,
        ]
        for type in types {
            let found = plan(type)
            #expect(found.shape != .bypass, "\(type): \(found.bypassReason ?? "")")
        }
    }

    @Test("A navigation destination names its type by identifier, not by a metatype, and is read whole")
    func navigationDestination() {
        let modified = EmptyView().navigationDestination(for: Int.self) { _ in EmptyView() }
        let found = plan(type(of: modified))
        #expect(found.shape == .dense, "\(found.bypassReason ?? "")")
    }

    /// The property the plans exist for, over a corpus of the framework's own
    /// view types: no run a plan loads overlaps a byte that no field covers.
    @Test("No plan reads a padding byte")
    func noPlanReadsPadding() {
        let corpus: [Any.Type] = [
            Text.self, FlexibleFrameView<Text>.self, Toggle<Text>.self,
            type(of: Button("x") {}),
            type(of: Text("x").padding(1)),
            type(of: PaddedRow(flag: true, count: 1).padding(1)),
            type(of: HStack { Text("a"); Text("b") }),
            type(of: VStack { PaddedRow(flag: true, count: 1); Text("b") }),
            ConditionalView<Text, EmptyView>.self, AnyView.self, AnyEquatableBox.self,
            (Bool, Int, UInt8, Int32).self, HoldsExistentials.self, HoldsWeak.self,
        ]
        for type in corpus {
            let found = plan(type, in: plans)
            let gaps = interiorPadding(of: type)
            for run in found.definedRanges {
                #expect(!gaps.contains { $0.overlaps(run) }, "\(type): run \(run) overlaps padding \(gaps)")
            }
        }
    }

    // MARK: Running plans

    /// The hash of `value` placed in memory of its own, after each of three
    /// fills of `bytes` — through the plans directly, which nothing else calls
    /// yet.
    private func hashes<V>(of value: V, filling bytes: [Range<Int>], plans: ValueHashPlans) -> [Int?] {
        let pointer = UnsafeMutablePointer<V>.allocate(capacity: 1)
        pointer.initialize(to: value)
        defer {
            pointer.deinitialize(count: 1)
            pointer.deallocate()
        }
        return [UInt8(0xAA), 0x55, 0x00].map { fill in
            for range in bytes {
                for offset in range {
                    UnsafeMutableRawPointer(pointer).storeBytes(of: fill, toByteOffset: offset, as: UInt8.self)
                }
            }
            return plans.valueHash(at: pointer)
        }
    }

    private func hash<V>(_ value: V, plans: ValueHashPlans) -> Int? {
        withUnsafePointer(to: value) { plans.valueHash(at: $0) }
    }

    @Test("Equal values hash the same by their plans whatever their undefined bytes hold")
    func undefinedBytesDoNotMatter() throws {
        let wrapped = PaddedRow(flag: true, count: 7).padding(1)
        let padded = hashes(of: wrapped, filling: interiorPadding(of: type(of: wrapped)), plans: plans)
        #expect(Set(padded).count == 1 && padded[0] != nil, "\(padded)")
        typealias Conditional = ConditionalView<Text, EmptyView>
        let conditional = hashes(
            of: Conditional.falseContent(EmptyView()), filling: [0..<MemoryLayout<Text>.size], plans: plans)
        #expect(Set(conditional).count == 1 && conditional[0] != nil, "\(conditional)")
        #if _pointerBitWidth(_64)
        let label = hashes(of: OptionalLabel(label: nil), filling: [0..<8], plans: plans)
        #expect(Set(label).count == 1 && label[0] != nil, "\(label)")
        let box = hashes(of: BoxHolder(box: AnyEquatableBox(5)), filling: [8..<24], plans: plans)
        #expect(Set(box).count == 1 && box[0] != nil, "\(box)")
        #endif
    }

    @Test("Different values hash apart by their plans")
    func differentValuesHashApart() {
        #expect(hash(Text("x").frame(width: 5), plans: plans) != hash(Text("x").frame(width: 6), plans: plans))
        typealias Conditional = ConditionalView<Text, Text>
        #expect(
            hash(Conditional.trueContent(Text("x")), plans: plans)
                != hash(Conditional.falseContent(Text("x")), plans: plans))
        #expect(hash(Int?.none, plans: plans) != hash(Int?.some(0), plans: plans))
        #expect(hash(OptionalLabel(label: nil), plans: plans) != hash(OptionalLabel(label: ""), plans: plans))
        let text = Text("x")
        #expect(hash(AnyView(text), plans: plans) != hash(AnyView(AnyView(text)), plans: plans))
        #expect(
            hash(AnyEquatableBox(5 as Int), plans: plans) != hash(AnyEquatableBox(5 as UInt), plans: plans))
        #expect(hash(PaddedRow(flag: true, count: 1), plans: plans) != hash(PaddedRow(flag: false, count: 1), plans: plans))
        // Apart in the `Any` field (opened directly), then in the `any Shape`
        // one (opened through its metatype and a cast).
        let shapes = [
            HoldsExistentials(flag: true, shape: 1, anything: 2), .init(flag: true, shape: 1, anything: 3),
            .init(flag: true, shape: 2, anything: 2),
        ]
        let shapeHashes = shapes.map { hash($0, plans: plans) }
        #expect(!shapeHashes.contains(nil))
        #expect(Set(shapeHashes).count == shapes.count, "\(shapeHashes)")
    }

    @Test("TUIkit's own payload enums hash by their cases: equal values together, different cases apart")
    func frameworkEnums() {
        let types: [Any.Type] = [
            TrackStyle.self, SegmentColoring.self, StyleScope.self, TrackConfiguration.Background.self,
            KeyboardShortcut.Trigger.self,
        ]
        for type in types {
            #expect(plan(type).stepDescriptions == ["0: \(type)"], "\(type)")
        }
        let styles: [TrackStyle] = [
            .bar, .block, .shadeRamp(gradient: nil), .shadeRamp(gradient: Gradient(colors: [.red, .blue])),
            .threeSegment(leading: "a", middle: "b", trailing: "c"),
            .threeSegment(leading: "a", middle: "b", trailing: "c", coloring: .solid(.red)),
            .custom(.block),
        ]
        let hashes = styles.map { hash($0, plans: plans) }
        #expect(!hashes.contains(nil))
        #expect(Set(hashes).count == styles.count, "\(hashes)")
        #expect(hashes == styles.map { hash($0, plans: plans) })
        let scopes: [StyleScope] = [
            .all, .text, .semanticColor(.accent), .control(.button), .controlVariant(.button, "a"),
            .controlVariant(.button, "b"), .font(.headline),
        ]
        let scopeHashes = scopes.map { hash($0, plans: plans) }
        #expect(!scopeHashes.contains(nil))
        #expect(Set(scopeHashes).count == scopes.count, "\(scopeHashes)")
        let shortcuts: [KeyboardShortcut] = [.defaultAction, .cancelAction, KeyboardShortcut("k"), KeyboardShortcut("j")]
        let shortcutHashes = shortcuts.map { hash($0, plans: plans) }
        #expect(!shortcutHashes.contains(nil))
        #expect(Set(shortcutHashes).count == shortcuts.count, "\(shortcutHashes)")
        let colours: [AnimatedColor] = [
            AnimatedColor(.red), AnimatedColor(.blue), AnimatedColor(frames: [.red, .blue], step: 0),
        ]
        let colourHashes = colours.map { hash($0, plans: plans) }
        #expect(!colourHashes.contains(nil))
        #expect(Set(colourHashes).count == colours.count, "\(colourHashes)")
    }

    @Test("A type that bypasses has no hash")
    func bypassHasNoHash() {
        #expect(hash(Choice.number(1), plans: plans) == nil)
        #expect(hash(OptionalLabel(label: nil), plans: plans) != nil)
    }

    // MARK: The table

    @Test("The table grows past a quarter full and every plan stays where it was")
    func tableGrows() {
        let first = plans.plan(for: PaddedRow.self)
        var types: [Any.Type] = []
        // Seventy distinct types: past a quarter of the 256 slots it starts with.
        for depth in 0..<70 {
            types.append(nestedTuple(depth))
        }
        for type in types { _ = plans.plan(for: type) }
        #expect(plans.count == 71)
        #expect(plans.plan(for: PaddedRow.self) == first)
    }

    /// A distinct tuple type per `depth`.
    private func nestedTuple(_ depth: Int) -> Any.Type {
        func wrap<T>(_: T.Type) -> Any.Type { (T, UInt8).self }
        var type: Any.Type = UInt8.self
        for _ in 0..<depth {
            type = _openExistential(type, do: wrap)
        }
        return type
    }
}
