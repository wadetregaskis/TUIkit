//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TypeWalkTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitCore
@testable import TUIkitView

#if canImport(Synchronization)
    import Synchronization
#endif

/// The type walk answers from a type's field metadata, with no instance, what
/// a value of it can hold: a source reader (`Binding`), an existential, a
/// closure. Each rule is pinned by a type built to exercise it, and the
/// runtime field metadata it rests on (``RuntimeFields``) is pinned too, so a
/// runtime that changes what it reports fails here, on every lane.
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
    private struct HoldsConstrainedExistential { var items: any Collection<Int> }
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

    @Test("A struct or tuple that is not POD and lists no fields is refused: its field metadata was stripped")
    func strippedMetadataRefused() {
        // What the runtime does for a type from a module built without
        // reflection metadata: the runtime says it described the type,
        // and lists no fields.
        var walk = TypeWalk(listFields: { _, _, _ in true })
        #expect(walk.verdict(for: HoldsExistential.self).refusal == .noFieldMetadata(path: "HoldsExistential"))
        let tuple = (String, any Payload).self
        #expect(walk.verdict(for: tuple).refusal == .noFieldMetadata(path: "\(tuple)"))
        #expect(
            walk.verdict(for: Plain.self) == .init(refusal: nil, holdsFunctions: false),
            "POD is a leaf before its fields are asked")
        #expect(
            walk.verdict(for: Shared.self) == .init(refusal: nil, holdsFunctions: false),
            "a class that lists none is a leaf, as a class the runtime cannot describe is")
    }

    @Test("A type the lister does not describe is refused")
    func undescribedRefused() {
        // The runtime lister answers `false` only for a class asked without the
        // class option, or when its body stops it; the walk does neither, so
        // this refusal is a guard the runtime never reaches.
        var walk = TypeWalk(listFields: { _, _, _ in false })
        #expect(walk.verdict(for: HoldsClosure.self).refusal == .noFieldMetadata(path: "HoldsClosure"))
    }

    @Test("A constrained existential, whose kind the runtime does not name, is refused")
    func unknownKindRefused() {
        #expect(
            verdict(HoldsConstrainedExistential.self).refusal
                == .unknownKind(path: "HoldsConstrainedExistential.items"))
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

    // MARK: The runtime metadata it rests on

    @Test("The runtime lists a struct's stored fields, in order, with their types and kinds")
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
        let described = RuntimeFields.forEach(of: Sample.self) { name, _, type, kind in
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

    @Test("The runtime lists a class's fields only with the class option, whose raw value is the stdlib's, 1")
    func spiListsClassFieldsWithTheOption() {
        var without = 0
        let refused = RuntimeFields.forEach(of: Shared.self) { _, _, _, _ in
            without += 1
            return true
        }
        var with = 0
        let described = RuntimeFields.forEach(of: Shared.self, options: .classType) { _, _, _, _ in
            with += 1
            return true
        }
        #expect(!refused && without == 0)
        #expect(described && with == 2)
        #expect(!RuntimeFields.forEach(of: Plain.self, options: .classType) { _, _, _, _ in true })
        #expect(RuntimeFields.Options.classType.rawValue == 1)
    }

    @Test("The runtime's kind for a type needs no field of it")
    func kindReadFromTheType() {
        #expect(RuntimeFields.Kind(of: Int.self) == .struct)
        #expect(RuntimeFields.Kind(of: Shared.self) == .class)
        #expect(RuntimeFields.Kind(of: Carrier.self) == .enum)
        #expect(RuntimeFields.Kind(of: Int?.self) == .optional)
        #expect(RuntimeFields.Kind(of: (Int, Int).self) == .tuple)
        #expect(RuntimeFields.Kind(of: (() -> Void).self) == .function)
        #expect(RuntimeFields.Kind(of: (any Payload).self) == .existential)
        #expect(RuntimeFields.Kind(of: Int.Type.self) == .metatype)
    }

    /// Whether this process's runtime reports a noncopyable field as its own
    /// type, as Swift 6.4's does, rather than as `()`, as 6.2's and 6.3's do.
    ///
    /// A property of the RUNTIME, which is not always the compiler's: on
    /// Apple platforms it is the OS's, and the macOS 26 lane answered `()`
    /// under the 6.4 compiler. So there it is the OS version — macOS 27 is the
    /// first with 6.4's runtime, an assumption the macOS 27 lane checks — and
    /// everywhere else, where the runtime ships with the toolchain, the
    /// compiler's version. Observed 2026-09-28: `()` on Linux 6.2 and 6.3,
    /// macOS 15 and macOS 26; `Mutex<Int>` on Linux 6.4 and trunk.
    private static var runtimeReportsNoncopyableFieldTypes: Bool {
        #if canImport(Darwin)
            if #available(macOS 27, iOS 27, watchOS 27, tvOS 27, visionOS 27, *) { return true }
            return false
        #elseif compiler(>=6.4)
            return true
        #else
            return false
        #endif
    }

    /// Before Swift 6.4 the runtime describes a noncopyable field as `()`;
    /// 6.4's reports its own type, `Mutex<Int>`. Each runtime is held to its
    /// own answer (``runtimeReportsNoncopyableFieldTypes``), so a runtime that
    /// regressed to `()` fails here. The walk's verdict is the same under both:
    /// inside a class — the only place a copyable value can hold a
    /// noncopyable field — only a source reader counts.
    @Test("The runtime describes a noncopyable field as () before Swift 6.4, and as its own type from 6.4")
    func spiDescribesNoncopyableFields() {
        #if canImport(Synchronization)
            if #available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) {
                final class Guarded { let lock = Mutex(0) }
                var types: [Any.Type] = []
                RuntimeFields.forEach(of: Guarded.self, options: .classType) { _, _, type, _ in
                    types.append(type)
                    return true
                }
                #expect(types.count == 1, "\(types)")
                if Self.runtimeReportsNoncopyableFieldTypes {
                    #expect(types.first.map { "\($0)" } == "Mutex<Int>", "\(types)")
                } else {
                    #expect(types.first == Void.self, "\(types)")
                }
                #expect(verdict(Guarded.self) == .init(refusal: nil, holdsFunctions: false), "inside a class, a leaf")
            }
        #endif
    }
}
