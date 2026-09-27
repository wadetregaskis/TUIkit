//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TypeWalkTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
@_spi(Reflection) import Swift
import Testing

@testable import TUIkitCore
@testable import TUIkitView

#if canImport(Synchronization)
    import Synchronization
#endif

/// The type walk answers from a type's field metadata, with no instance, what
/// a value of it can hold: a source reader (`Binding`), an existential, a
/// closure. Each rule is pinned by a type built to exercise it, and the
/// stdlib reflection SPI it rests on is pinned too, so a toolchain that
/// changes what `_forEachField` reports fails here, on every lane.
@Suite("A type can say what it holds without an instance")
struct TypeWalkTests {
    // MARK: Types that exercise the rules

    fileprivate protocol Payload {}
    fileprivate struct Note: Payload { var text: String }

    private struct Plain {
        var count: Int
        var ratio: Double
        var flag: Bool
    }

    private struct Leaves {
        var text: String
        var slice: Substring
        var letter: Character
        var data: Data
        var url: URL
        var decimal: Decimal
        var attributed: AttributedString
        var any: AnyHashable
        var type: Int.Type
        var anyType: any Payload.Type
        var date: Date
        var uuid: UUID
    }

    private struct HoldsBinding { var title: String; var isOn: Binding<Bool> }
    private struct NestsBinding { var inner: HoldsBinding }
    private struct TupleOfBinding { var pair: (Int, Binding<Int>) }
    private struct HoldsExistential { var payload: any Payload }
    private struct HoldsClosure { var title: String; var action: () -> Void }
    private struct HoldsVoid { var title: String; var nothing: () }
    private struct PODVoid { var count: Int; var nothing: () }

    private final class Shared {
        var payload: any Payload = Note(text: "")
        var action: () -> Void = {}
    }
    private final class SharedBinding { var isOn = Binding<Bool>(get: { false }, set: { _ in }) }
    private struct HoldsShared { var shared: Shared }
    private struct HoldsSharedBinding { var shared: SharedBinding }

    private enum Carrier { case bound(Binding<Int>), plain(Int) }
    private struct HoldsCarrier { var carrier: Carrier }

    private final class Node { var next: Node?; init() {} }
    private struct Tree { var children: [Self] }

    private func verdict(_ type: Any.Type) -> TypeWalk.Verdict {
        var walk = TypeWalk()
        return walk.verdict(for: type)
    }

    // MARK: The rules

    @Test("POD is a leaf")
    func podIsALeaf() {
        #expect(verdict(Plain.self) == .init(refusal: nil, holdsFunctions: false))
    }

    @Test("The known leaves, AnyHashable and metatypes are leaves")
    func knownLeaves() {
        #expect(verdict(Leaves.self) == .init(refusal: nil, holdsFunctions: false))
    }

    @Test("A Binding is refused wherever a struct or tuple holds it")
    func bindingRefused() {
        #expect(verdict(Binding<Int>.self).refusal == .readsItsSource(path: "Binding<Int>"))
        #expect(verdict(HoldsBinding.self).refusal == .readsItsSource(path: "HoldsBinding.isOn"))
        #expect(verdict(NestsBinding.self).refusal == .readsItsSource(path: "NestsBinding.inner.isOn"))
        #expect(verdict(TupleOfBinding.self).refusal == .readsItsSource(path: "TupleOfBinding.pair.1"))
    }

    @Test("Containers are judged by their element types, so an empty one hides nothing")
    func containersByElementType() {
        #expect(verdict([Binding<Int>].self).refusal != nil, "an array of Bindings, empty or not")
        #expect(verdict(Binding<Int>?.self).refusal != nil, "an optional Binding, nil or not")
        #expect(verdict(ContiguousArray<Binding<Int>>.self).refusal != nil)
        #expect(verdict(ArraySlice<Binding<Int>>.self).refusal != nil)
        #expect(verdict([String: Binding<Int>].self).refusal != nil, "a dictionary's values")
        #expect(verdict([any Payload].self).refusal != nil, "an array of existentials")
        #expect(verdict([Int].self) == .init(refusal: nil, holdsFunctions: false))
        #expect(verdict(Set<String>.self) == .init(refusal: nil, holdsFunctions: false))
        #expect(verdict([String: [Int]].self) == .init(refusal: nil, holdsFunctions: false))
    }

    @Test("An existential is refused")
    func existentialRefused() {
        #expect(verdict(HoldsExistential.self).refusal == .existential(path: "HoldsExistential.payload"))
    }

    @Test("A closure is allowed and noted")
    func closureNoted() {
        #expect(verdict(HoldsClosure.self) == .init(refusal: nil, holdsFunctions: true))
    }

    @Test("A class is searched for source readers only")
    func classSearchedForSourceReaders() {
        #expect(
            verdict(HoldsShared.self) == .init(refusal: nil, holdsFunctions: false),
            "a class's existential and closure are its own business")
        #expect(verdict(HoldsSharedBinding.self).refusal == .readsItsSource(path: "HoldsSharedBinding.shared.isOn"))
    }

    @Test("An enum is a leaf: its payloads are not visible (a documented blind spot)")
    func enumIsALeaf() {
        #expect(verdict(HoldsCarrier.self) == .init(refusal: nil, holdsFunctions: false))
    }

    @Test("A field the runtime describes as () is refused, unless the whole value is POD")
    func voidFieldRefused() {
        #expect(verdict(HoldsVoid.self).refusal == .opaqueStorage(path: "HoldsVoid.nothing"))
        #expect(verdict(PODVoid.self) == .init(refusal: nil, holdsFunctions: false))
    }

    @Test("A type the runtime cannot describe is refused")
    func undescribedRefused() {
        var walk = TypeWalk(listFields: { _, _, _ in false })
        #expect(walk.verdict(for: HoldsClosure.self).refusal == .noFieldMetadata(path: "HoldsClosure"))
    }

    @Test("Recursion through a class or an array terminates")
    func recursionTerminates() {
        #expect(verdict(Node.self) == .init(refusal: nil, holdsFunctions: false))
        #expect(verdict(Tree.self) == .init(refusal: nil, holdsFunctions: false))
    }

    @Test("A type is walked once, however often it is asked about")
    func walkedOnce() {
        var walk = TypeWalk()
        _ = walk.verdict(for: NestsBinding.self)
        let walks = walk.walks
        for _ in 0..<1_000 { _ = walk.verdict(for: NestsBinding.self) }
        #expect(walks > 0)
        #expect(walk.walks == walks, "\(walk.walks - walks) walks after the first")
    }

    @Test("An InlineArray is judged by its element type")
    func inlineArrayByElementType() {
        if #available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *) {
            #expect(verdict(InlineArray<2, Binding<Int>>.self).refusal != nil)
            #expect(verdict(InlineArray<2, Int>.self) == .init(refusal: nil, holdsFunctions: false))
        }
    }

    // MARK: The SPI it rests on

    @Test("_forEachField lists a struct's stored fields, in order, with their types and kinds")
    func spiListsStructFields() {
        struct Sample {
            var count: Int
            var action: () -> Void
            var payload: any Payload
            var shared: Shared
            var maybe: Int?
            var pair: (Int, Int)
            var carrier: Carrier
        }
        var fields: [String] = []
        let described = _forEachField(of: Sample.self) { name, _, type, kind in
            fields.append("\(String(cString: name)):\(type == Int.self ? "Int" : "…"):\(kind)")
            return true
        }
        #expect(described)
        #expect(
            fields == [
                "count:Int:struct", "action:…:function", "payload:…:existential", "shared:…:class",
                "maybe:…:optional", "pair:…:tuple", "carrier:…:enum",
            ])
    }

    @Test("_forEachField lists a class's fields only with the class option, whose raw value is 1")
    func spiListsClassFieldsWithTheOption() {
        var without = 0
        _ = _forEachField(of: Shared.self) { _, _, _, _ in
            without += 1
            return true
        }
        var with = 0
        let described = _forEachField(of: Shared.self, options: _EachFieldOptions(rawValue: 1 << 0)) { _, _, _, _ in
            with += 1
            return true
        }
        #expect(without == 0)
        #expect(described && with == 2)
    }

    @Test("_forEachField describes a noncopyable field as ()")
    func spiDescribesNoncopyableAsVoid() {
        #if canImport(Synchronization)
            if #available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) {
                final class Guarded { let lock = Mutex(0) }
                var types: [Any.Type] = []
                _ = _forEachField(of: Guarded.self, options: _EachFieldOptions(rawValue: 1 << 0)) { _, _, type, _ in
                    types.append(type)
                    return true
                }
                #expect(types.count == 1 && types[0] == Void.self, "\(types)")
                #expect(verdict(Guarded.self) == .init(refusal: nil, holdsFunctions: false), "inside a class, a leaf")
            }
        #endif
    }
}
