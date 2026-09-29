//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ValueHashing.swift
//
//  How the value hash reads the values whose bytes it must not read whole:
//  the typed opt-in a type can make, the optional's case, and an
//  existential's payload — all through typed Swift, never by reading how
//  Swift lays out an enum's case or an existential's container.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling

// MARK: - The opt-ins

/// A type whose value hash is mixed by typed Swift that reads it, rather than
/// from its bytes: `Optional` (its case, then its payload), `ConditionalView`
/// (its branch, then the branch's content), `AnyView` (its content's type,
/// then the content).
///
/// For a type some of whose bytes can be left undefined by a value that is
/// perfectly well formed — an enum's inactive payload, the half of a `nil` its
/// spare values do not spell, an existential's unused buffer words — so no
/// fixed choice of bytes is safe to read, but a `switch`, a `== nil` or an
/// opened existential finds exactly the part that means something.
///
/// The encoding must tell values apart: two different values of the type must
/// never mix the same words (up to a collision of the hash). So a case is
/// mixed before its payload, and an opened existential's type before its
/// value.
package protocol _ValueHashing {
    /// Mixes the value of this type at `pointer` into `hash`, reading it through
    /// typed Swift; `false` when some part of it cannot be hashed, and the whole
    /// value must go unhashed.
    @MainActor
    static func _mixValueHash(at pointer: UnsafeRawPointer, into hash: inout UInt64, plans: ValueHashPlans) -> Bool
}

// MARK: - Markers

/// The words the typed steps mix to say which case they read — distinct from
/// one another so `nil` and a `.some` whose payload hashes to nothing, or two
/// branches over one value, never mix the same words.
enum ValueHashMark {
    static let none: UInt64 = 0x6E6F_6E65_0000_0001
    static let some: UInt64 = 0x736F_6D65_0000_0002
    static let firstBranch: UInt64 = 0x6272_616E_6368_0001
    static let secondBranch: UInt64 = 0x6272_616E_6368_0002
}

// MARK: - Optional

extension Optional: _ValueHashing {
    /// `nil` is a marker and nothing else; `.some` is a marker, then the
    /// payload by its own plan, where it lies — at the start of the optional.
    ///
    /// The case is read by `== nil`, never from the bytes: an optional whose
    /// `nil` is spelled in its payload's spare values (`String?`, a closure's,
    /// `Color?`) leaves the rest of the payload as it was when `nil` is stored
    /// in place, so no fixed choice of bytes says which case it is and holds
    /// nothing undefined. The plan reads a whole optional without asking this
    /// where its bytes are always all written — see `ValueHashPlanBuilder`.
    @MainActor
    package static func _mixValueHash(
        at pointer: UnsafeRawPointer, into hash: inout UInt64, plans: ValueHashPlans
    ) -> Bool {
        if isNone(pointer.assumingMemoryBound(to: Self.self).pointee) {
            hash = mixHashWord(hash, ValueHashMark.none)
            return true
        }
        hash = mixHashWord(hash, ValueHashMark.some)
        return plans.mix(at: pointer, type: Wrapped.self, into: &hash)
    }
}

/// Whether `value` is `nil`, borrowed: no copy of the payload, and no retain
/// of one.
@inline(__always)
private func isNone<Wrapped>(_ value: borrowing Wrapped?) -> Bool {
    value == nil
}

// MARK: - Existentials

/// How the value hash opens an existential field: through its static type,
/// loaded as that type and opened by Swift, never by reading the container.
///
/// The few static types TUIkit stores are opened directly — a typed load and
/// Swift's own opening, a few nanoseconds. Any other (`any P` an app declares)
/// is loaded as its static type through a metatype and opened by casting to the
/// dynamic type `type(of:)` finds, which costs a dynamic cast.
enum ExistentialField {
    case any
    case view
    case equatable
    case hashable
    case other(Any.Type)

    /// The opener for a field whose static type is `type`, an existential.
    init(_ type: Any.Type) {
        if type == Any.self {
            self = .any
        } else if type == (any View).self {
            self = .view
        } else if type == (any Equatable).self {
            self = .equatable
        } else if type == (any Hashable).self {
            self = .hashable
        } else {
            self = .other(type)
        }
    }

    /// Mixes the existential at `pointer` into `hash`: its payload's dynamic
    /// type, then the payload by that type's plan.
    @MainActor
    func mix(at pointer: UnsafeRawPointer, into hash: inout UInt64, plans: ValueHashPlans) -> Bool {
        switch self {
        case .any:
            return mixOpenedAny(pointer.assumingMemoryBound(to: Any.self).pointee, into: &hash, plans: plans)
        case .view:
            return mixOpenedView(pointer.assumingMemoryBound(to: (any View).self).pointee, into: &hash, plans: plans)
        case .equatable:
            return mixOpenedEquatable(
                pointer.assumingMemoryBound(to: (any Equatable).self).pointee, into: &hash, plans: plans)
        case .hashable:
            return mixOpenedHashable(
                pointer.assumingMemoryBound(to: (any Hashable).self).pointee, into: &hash, plans: plans)
        case .other(let staticType):
            return mixExistential(at: pointer, staticType: staticType, into: &hash, plans: plans)
        }
    }
}

/// Mixes `value` — an existential's payload, opened — as its type, then its
/// value by that type's plan.
///
/// The type is mixed because the payload's bytes alone do not carry it: the
/// same eight bytes are `5 as Int` and `5 as UInt`, and a `Text` and a
/// `Divider` whose structs held the same bytes would be one key.
///
/// `false`, unhashed, when the stack is running out (``StackGuard``). This is
/// the one place the hash recurses as deep as a VALUE goes rather than as
/// deep as a type is written: a payload can hold another existential — an
/// `AnyView` of a stack holding an `AnyView` … — to whatever depth the value
/// was built to. The measure that asked has its own guard, but asks for the
/// whole subtree's hash before it descends: an `AnyView` chain 2,000 deep,
/// which the measure truncates, overflowed the stack in the hash (a debug
/// build, 2026-09-28). A value too deep to hash is measured unkeyed — and the
/// measure descends anyway, under its own guard — so giving up here is not a
/// truncation, and is not counted as one (`StackGuard.truncationCount`, which
/// a harness reads as "the tree was cut short").
@MainActor
func mixOpened<Payload>(_ value: Payload, into hash: inout UInt64, plans: ValueHashPlans) -> Bool {
    guard StackGuard.hasHeadroomUncounted() else { return false }
    hash = mixHashWord(hash, UInt64(UInt(bitPattern: ObjectIdentifier(Payload.self))))
    return plans.mixValue(value, into: &hash)
}

// The openers below each take the existential as a CONSTRAINED generic
// parameter, which is what makes Swift open it: passed to an unconstrained one
// (`mixOpened`'s), `any View` binds the parameter to `any View` itself, and the
// payload's type is never seen (measured on 6.2.4: `any P` → `P`, `Any` → `Any`).

/// ``mixOpened(_:into:plans:)`` for an `any View`, opened.
@MainActor
func mixOpenedView<Payload: View>(_ value: Payload, into hash: inout UInt64, plans: ValueHashPlans) -> Bool {
    mixOpened(value, into: &hash, plans: plans)
}

/// ``mixOpened(_:into:plans:)`` for an `any Equatable`, opened.
@MainActor
private func mixOpenedEquatable<Payload: Equatable>(
    _ value: Payload, into hash: inout UInt64, plans: ValueHashPlans
) -> Bool {
    mixOpened(value, into: &hash, plans: plans)
}

/// ``mixOpened(_:into:plans:)`` for an `any Hashable`, opened.
@MainActor
private func mixOpenedHashable<Payload: Hashable>(
    _ value: Payload, into hash: inout UInt64, plans: ValueHashPlans
) -> Bool {
    mixOpened(value, into: &hash, plans: plans)
}

/// ``mixOpened(_:into:plans:)`` for an `Any`, which no constraint can open:
/// `_openExistential` does.
@MainActor
private func mixOpenedAny(_ value: Any, into hash: inout UInt64, plans: ValueHashPlans) -> Bool {
    func opened<Payload>(_ payload: Payload) -> Bool {
        mixOpened(payload, into: &hash, plans: plans)
    }
    return _openExistential(value, do: opened)
}

/// An existential of a static type the value hash has no direct opener for:
/// loaded as that type, found through its metatype.
@MainActor
private func mixExistential(
    at pointer: UnsafeRawPointer, staticType: Any.Type, into hash: inout UInt64, plans: ValueHashPlans
) -> Bool {
    func loaded<Existential>(_: Existential.Type) -> Bool {
        mixDynamic(pointer.assumingMemoryBound(to: Existential.self).pointee, into: &hash, plans: plans)
    }
    return _openExistential(staticType, do: loaded)
}

/// `value`, an existential held as a generic parameter, opened to its dynamic
/// type: `type(of:)` over it as `Any` finds that type, and a cast to it
/// unwraps the payload. (Opening the `Any` would find the existential's own
/// type again, not its payload's.)
@MainActor
private func mixDynamic<Existential>(_ value: Existential, into hash: inout UInt64, plans: ValueHashPlans) -> Bool {
    func cast<Payload>(_: Payload.Type) -> Bool {
        guard let payload = value as? Payload else { return false }
        return mixOpened(payload, into: &hash, plans: plans)
    }
    return _openExistential(type(of: value as Any), do: cast)
}

// MARK: - Colours

/// A colour's value: a trivial non-generic enum, public and `@frozen`, so every
/// module builds it knowing its layout — see `_AllBytesDefined`. Declared here
/// because the colour's own module does not depend on the protocol's.
extension Color.ColorValue: _AllBytesDefined {}
