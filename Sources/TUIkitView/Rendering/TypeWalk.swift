//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TypeWalk.swift
//
//  What a type can hold, asked of the type rather than of a value.
//
//  A row that is re-checked after a parent's write is trusted to draw the
//  same when its value compares equal. That trust is sound only for a value
//  whose `==` can see what it draws, and three kinds of field cannot be seen:
//  a `Binding`, which reads a source the row does not hold; an existential,
//  which can hold anything, so a hand-written `==` over it is partial of
//  necessity; and a field the runtime cannot describe. So the question "may
//  this row be re-checked?" is a question about its TYPE: what fields it has,
//  and what fields they have.
//
//  The runtime answers it from field metadata (`_forEachField`, the stdlib's
//  reflection SPI, which `Mirror` is built on) with no instance at all: no
//  element of an array is walked, so a large array costs nothing and an
//  empty one hides nothing, and the answer is the same for every value of the
//  type, so it is found once and kept.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
@_spi(Reflection) import Swift

// MARK: - Markers

/// A type that reads a source it does not hold: `Binding`, `FocusState.Binding`.
///
/// A value holding one compares equal to another over a different source,
/// because the source is not part of the value, so a row holding one can never
/// be re-checked by its value. The type walk refuses it wherever it is found.
package protocol _ReadsItsSource {}

/// A container whose elements are not fields: a collection's storage is a
/// buffer the runtime's field metadata does not describe, so the walk asks
/// the container for its element types instead. One conformance per
/// container.
package protocol _ElementTypesProviding {
    /// The types of what the container can hold.
    static var elementTypes: [Any.Type] { get }
}

extension Optional: _ElementTypesProviding {
    package static var elementTypes: [Any.Type] { [Wrapped.self] }
}

extension Array: _ElementTypesProviding {
    package static var elementTypes: [Any.Type] { [Element.self] }
}

extension ContiguousArray: _ElementTypesProviding {
    package static var elementTypes: [Any.Type] { [Element.self] }
}

extension ArraySlice: _ElementTypesProviding {
    package static var elementTypes: [Any.Type] { [Element.self] }
}

extension Set: _ElementTypesProviding {
    package static var elementTypes: [Any.Type] { [Element.self] }
}

extension Dictionary: _ElementTypesProviding {
    package static var elementTypes: [Any.Type] { [Key.self, Value.self] }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension InlineArray: _ElementTypesProviding where Element: Copyable {
    package static var elementTypes: [Any.Type] { [Element.self] }
}

extension Binding: _ReadsItsSource {}

/// A one-field wrapper, whose field's kind is `T`'s — see `TypeWalk.kind(of:)`.
private struct KindProbe<T> {
    var value: T
}

// MARK: - The walk

/// What a type can hold, read from the runtime's field metadata and kept per
/// type.
///
/// The rules, field kind by field kind:
/// - **POD** (`_isPOD`): a leaf. Nothing inside can hold a reference or a
///   closure.
/// - **Known leaves** — `String`, `Substring`, `Character`, `Data`, `URL`,
///   `Decimal`, `AttributedString`, `AnyHashable`, and any metatype: leaves.
/// - **Containers** (``_ElementTypesProviding``: `Optional`, `Array`,
///   `ContiguousArray`, `ArraySlice`, `Set`, `Dictionary`, `InlineArray`):
///   their element types, never their elements.
/// - **Structs and tuples**: their fields.
/// - **Classes**: their fields, looking only for a source reader. A class is
///   shared state held by identity, so what it holds otherwise — existentials,
///   closures, storage the runtime cannot see — is its own business. A class
///   that lists no fields (its field metadata stripped) is a leaf.
/// - **Functions**: allowed and noted. A closure is covered by the app's
///   `==`, as an action is.
/// - **Existentials**: refused.
/// - **Enums** other than `Optional`: leaves. The runtime reports no
///   payloads, so what a case carries is not seen — a documented blind spot.
/// - **Objective-C and foreign classes, and builtins** (the opaque kind, a
///   buffer's reference): leaves.
/// - **A source reader** (``_ReadsItsSource``): refused.
/// - **A field reported as `()`**: refused. That is how the runtime describes
///   a noncopyable field — `Mutex`, `Atomic` — whose contents it cannot see;
///   a real `()` field is vanishingly rare, and a POD struct holding one is a
///   leaf before its fields are asked. Only a class can hold a noncopyable
///   field and still be copied, and inside a class only a source reader
///   counts.
/// - **No field metadata** — a struct or tuple that is not POD and lists no
///   fields: refused. A value with no stored fields is POD, so one that is
///   not and lists none is one whose module was built without reflection
///   metadata, which `_forEachField` does not report as a failure: it
///   answers `true` having listed nothing.
/// - **Any other kind** that is not POD — the kind the SPI calls `unknown`,
///   or one it names that the walk does not list above: refused. The SPI
///   reports a constrained existential (`any Collection<Int>`) as unknown,
///   and on macOS 15 cannot even name its type; every type reads as unknown
///   when TUIkitView itself is built without reflection metadata (the kind
///   is read off a wrapper's field); and a kind added to the runtime after
///   this was written reads as one the walk does not list.
///
/// Recursion stops at a type already being walked, which is answered by the
/// walk that is under way.
///
/// Blind spots, beyond an enum's payloads: a `Binding` captured in a closure;
/// the elements of a container that keeps them in a buffer without
/// conforming to ``_ElementTypesProviding`` (`Deque`, the persistent
/// collections); fields a subclass adds, which the declared type's
/// metadata does not list; and a source reader inside a class whose field
/// metadata was stripped. Each is documented rather than refused, because
/// refusing every closure, buffer or class would refuse almost every row.
package struct TypeWalk {
    /// Why a type cannot be re-checked by its value.
    package enum Refusal: Equatable, Sendable {
        /// It holds a ``_ReadsItsSource`` (a `Binding`), at `path`.
        case readsItsSource(path: String)
        /// It holds an existential, at `path`.
        case existential(path: String)
        /// The runtime has no field metadata for the type at `path`: it lists
        /// no fields for a struct or tuple that is not POD, or does not
        /// describe it at all.
        case noFieldMetadata(path: String)
        /// The runtime reports a kind for the type at `path` that the walk
        /// does not know — a constrained existential such as
        /// `any Collection<Int>` is one — so what it holds cannot be seen.
        case unknownKind(path: String)
        /// A field at `path` is described as `()`: noncopyable storage the
        /// runtime cannot see into.
        case opaqueStorage(path: String)
    }

    /// What the walk found in a type.
    package struct Verdict: Equatable, Sendable {
        /// Why it cannot be re-checked, or `nil` when it can.
        package var refusal: Refusal?
        /// Whether it holds a closure anywhere a value can see.
        package var holdsFunctions: Bool
    }

    /// Lists a type's stored fields to `body` — name, declared type, kind —
    /// and says whether the runtime could describe it: the stdlib's
    /// `_forEachField`, which a test replaces to see the walk refuse a type
    /// the runtime cannot describe.
    package typealias FieldLister = (
        _ type: Any.Type, _ options: _EachFieldOptions,
        _ body: (UnsafePointer<CChar>, Int, Any.Type, _MetadataKind) -> Bool
    ) -> Bool

    /// Every type walked so far, and what it holds.
    private var verdicts: [ObjectIdentifier: Verdict] = [:]

    /// How many types have been walked — each once. What a test counts.
    package private(set) var walks = 0

    private let listFields: FieldLister

    package init(listFields: @escaping FieldLister = { _forEachField(of: $0, options: $1, body: $2) }) {
        self.listFields = listFields
    }

    /// What `type` holds, walked the first time it is asked about and kept.
    ///
    /// Only the types asked about are kept, and a type met inside another is
    /// walked again for each type it is met in: bounded by the types asked
    /// about, it keeps a verdict reached through a cycle — answered
    /// provisionally by the walk under way — from outliving that walk, and
    /// every refusal's path starts at the type asked about.
    package mutating func verdict(for type: Any.Type) -> Verdict {
        if let known = verdicts[ObjectIdentifier(type)] { return known }
        var walking: Set<ObjectIdentifier> = []
        let found = walk(type, path: "\(type)", inClass: false, walking: &walking)
        verdicts[ObjectIdentifier(type)] = found
        return found
    }

    /// The walk of one type: what its fields, and theirs, hold.
    private mutating func walk(
        _ type: Any.Type, path: String, inClass: Bool, walking: inout Set<ObjectIdentifier>
    ) -> Verdict {
        let id = ObjectIdentifier(type)
        // A cycle: the walk under way answers for it.
        guard walking.insert(id).inserted else { return Verdict(refusal: nil, holdsFunctions: false) }
        defer { walking.remove(id) }
        walks += 1

        if type is any _ReadsItsSource.Type {
            return Verdict(refusal: .readsItsSource(path: path), holdsFunctions: false)
        }
        if Self.isLeaf(type) { return Verdict(refusal: nil, holdsFunctions: false) }
        if let container = type as? any _ElementTypesProviding.Type {
            return fold(container.elementTypes.enumerated().map { index, element in
                walk(element, path: "\(path)[\(index)]", inClass: inClass, walking: &walking)
            })
        }
        let found: Verdict
        switch Self.kind(of: type) {
        case .struct, .tuple:
            found = fields(of: type, path: path, options: [], inClass: inClass, walking: &walking)
        case .class:
            found = Self.withinClass(
                fields(of: type, path: path, options: Self.classType, inClass: true, walking: &walking))
        case .function:
            found = Verdict(refusal: nil, holdsFunctions: true)
        case .existential:
            found = Verdict(refusal: .existential(path: path), holdsFunctions: false)
        case .enum, .objcClassWrapper, .foreignClass, .opaque:
            // An enum (its payloads unseen), an Objective-C or foreign class, a
            // builtin: a leaf.
            found = Verdict(refusal: nil, holdsFunctions: false)
        default:
            // Not POD (a POD type is a leaf above), and of a kind the walk does
            // not know: `.unknown`, which is how the SPI reports a constrained
            // existential and every type of a module built without reflection
            // metadata, or a kind it did not name when this was written.
            // Refused, since what it holds cannot be seen.
            found = Verdict(refusal: .unknownKind(path: path), holdsFunctions: false)
        }
        return inClass ? Self.withinClass(found) : found
    }

    /// What counts inside a class: a source reader, and nothing else. A class
    /// is shared state, held by identity; its existentials, closures and
    /// storage are its own business, and a class the runtime cannot describe
    /// is a leaf.
    private static func withinClass(_ verdict: Verdict) -> Verdict {
        guard case .readsItsSource = verdict.refusal else { return Verdict(refusal: nil, holdsFunctions: false) }
        return Verdict(refusal: verdict.refusal, holdsFunctions: false)
    }

    /// The fields of a struct, tuple or class, folded.
    private mutating func fields(
        of type: Any.Type, path: String, options: _EachFieldOptions, inClass: Bool,
        walking: inout Set<ObjectIdentifier>
    ) -> Verdict {
        var found: [Verdict] = []
        let described = listFields(type, options) { name, _, field, _ in
            // A tuple's unlabelled elements are named ".0", ".1".
            let name = String(cString: name)
            let fieldPath = name.hasPrefix(".") ? path + name : "\(path).\(name)"
            if field == Void.self {
                found.append(Verdict(refusal: .opaqueStorage(path: fieldPath), holdsFunctions: false))
            } else {
                found.append(walk(field, path: fieldPath, inClass: inClass, walking: &walking))
            }
            return true
        }
        // Only a type that is not POD is asked for its fields, and a struct or
        // tuple with no stored fields is POD — so one that lists none had its
        // field metadata stripped, which `_forEachField` answers `true` to. (A
        // class that lists none is refused here too, and `withinClass` makes
        // that a leaf, as it does every refusal in a class but a source
        // reader's.)
        guard described, !found.isEmpty else {
            return Verdict(refusal: .noFieldMetadata(path: path), holdsFunctions: false)
        }
        return fold(found)
    }

    /// The first refusal, and whether any holds a function.
    private func fold(_ verdicts: [Verdict]) -> Verdict {
        Verdict(
            refusal: verdicts.lazy.compactMap(\.refusal).first,
            holdsFunctions: verdicts.contains(where: \.holdsFunctions))
    }

    /// POD, a known leaf, or a metatype.
    private static func isLeaf(_ type: Any.Type) -> Bool {
        func pod<T>(_: T.Type) -> Bool { _isPOD(T.self) }
        if _openExistential(type, do: pod) { return true }
        if knownLeaves.contains(ObjectIdentifier(type)) { return true }
        switch kind(of: type) {
        case .metatype, .existentialMetatype: return true
        default: return false
        }
    }

    /// The runtime's kind for `type`: the kind `_forEachField` reports for a
    /// stored field of that type, read off a one-field wrapper, which is the
    /// only way the SPI says what kind a type is without an instance. `.unknown`
    /// when the wrapper lists no field: this module built without reflection
    /// metadata.
    private static func kind(of type: Any.Type) -> _MetadataKind {
        func probe<T>(_: T.Type) -> _MetadataKind {
            var found = _MetadataKind.unknown
            _ = _forEachField(of: KindProbe<T>.self) { _, _, _, kind in
                found = kind
                return false
            }
            return found
        }
        return _openExistential(type, do: probe)
    }

    /// `_EachFieldOptions.classType`, spelled by its raw value: the SPI
    /// declares the option a `static var`, which Swift 6 will not read from a
    /// nonisolated context. The walk's class tests fail if the value ever
    /// means something else.
    private static let classType = _EachFieldOptions(rawValue: 1 << 0)

    /// Types held by value whose contents cannot hold a source reader,
    /// existential or closure, and whose storage the field metadata does not
    /// describe usefully.
    private static let knownLeaves: Set<ObjectIdentifier> = [
        ObjectIdentifier(String.self), ObjectIdentifier(Substring.self), ObjectIdentifier(Character.self),
        ObjectIdentifier(Data.self), ObjectIdentifier(URL.self), ObjectIdentifier(Decimal.self),
        ObjectIdentifier(AttributedString.self), ObjectIdentifier(AnyHashable.self),
    ]
}
