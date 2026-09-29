//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ValueHash.swift
//
//  The per-pass memos' value hash: what tells two values of one view type
//  apart inside a render pass.
//
//  Created by Wade Tregaskis
//  License: MIT

/// Hashes a view value's raw storage, to tell two values of one type apart
/// inside a single render pass.
///
/// `measureChild` is generic over `V: View` and so cannot demand `Equatable`,
/// which is why the only value-keyed memo in the tree sits behind
/// `EquatableView`. The bytes are the conformance-free substitute: no
/// reflection (which would cost what the memo saves), just the struct's own
/// storage, which for a view is a handful of words.
///
/// See ``RenderCache/MeasureKey/valueHash`` for why raw bytes are sound within
/// a pass but were not across frames.
///
/// `Hasher` is the obvious spelling and the wrong one here. It is SipHash-1-3 —
/// keyed, randomised per process, and built to resist an adversary choosing
/// collisions. Nothing here has an adversary: this is a discriminator inside a
/// per-pass memo whose key ALSO carries the identity's hash, the view's type
/// and two widths, so a value collision on its own is unlikely to serve a wrong
/// answer. Unlikely, and not impossible, which is what the `AnyView` arm below
/// is about: siblings measured at ONE identity — a `Form` sizing its label
/// column, say — have all four of those fields in common, and the bytes are the
/// only thing telling them apart.
/// What it is, is hot — a whole-struct hash on every measured child, **3.4% of
/// a `menus` frame between this and the `withUnsafeBytes` around it**.
///
/// So: FNV-style mixing over whole words with a splitmix64 finalizer, which
/// avalanches the low bits a `Dictionary` probes on. A side effect worth having
/// is that it is deterministic — `Hasher`'s seed is randomised per process, so
/// the memo's key stream (and any bug that depends on it) differed run to run.
@MainActor
func viewValueHash<V: View>(_ view: V) -> Int {
    // The gate is a static witness and the arm is a cast to the ONE concrete
    // type, and both of those were arrived at by measurement. `measureChild` is
    // generic and public, so a caller in another module does not specialise it;
    // what it reads off `V` there is a witness-table access, and the cheapest
    // shapes are not the ones that read cheapest. `V.self == AnyView.self` in
    // place of the witness cost `deep` +2.7% and `modifiers` +4.6%, and hoisting
    // the loop below into a second function so this one could `return` it cost
    // another point on top. So: one witness, one branch, and the loop stays
    // where it was — `hashOfRawBytes` is always inlined, so it is still here.
    if V._valueIsBoxed, let boxed = view as? AnyView {
        return boxed.erasedValueHash
    }
    return withUnsafeBytes(of: view) { hashOfRawBytes($0) }
}

/// ``viewValueHash(_:)`` of the value at `value`, read where it lies.
///
/// A test's seam, and the reason it takes a pointer rather than a value: what
/// the hash must not read is the bytes a value's fields do not cover, and a
/// test can only put something there by writing into memory the value
/// occupies. A value passed by copy would arrive with whatever the copy wrote
/// in those bytes instead of what the test poked.
///
/// `cache` is the render cache whose memos the hash keys; `nil` means the value
/// cannot be hashed, and a memo measures it without keeping it.
@MainActor
package func viewValueHash<V: View>(at value: UnsafePointer<V>, in cache: RenderCache) -> Int? {
    if V._valueIsBoxed, let boxed = value.pointee as? AnyView {
        return boxed.erasedValueHash
    }
    return hashOfRawBytes(UnsafeRawBufferPointer(start: value, count: MemoryLayout<V>.size))
}

/// The hash of `bytes`, word by word, with the tail packed into one last word.
///
/// Always inlined: the hot path's shape — the loop in the function that tests
/// the gate — was measured, and a call here would be the second function it
/// was measured against.
@inline(__always)
func hashOfRawBytes(_ bytes: UnsafeRawBufferPointer) -> Int {
    var hash = hashFoldSeed
    let count = bytes.count
    var index = 0
    while index + 8 <= count {
        hash = mixHashWord(hash, bytes.loadUnaligned(fromByteOffset: index, as: UInt64.self))
        index += 8
    }
    // The tail, packed into one word so a short struct still mixes every
    // byte it has. A view is a handful of words, so this runs at most once.
    if index < count {
        var tail: UInt64 = 0
        var shift: UInt64 = 0
        while index < count {
            tail |= UInt64(bytes[index]) &<< shift
            shift &+= 8
            index += 1
        }
        hash = mixHashWord(hash, tail)
    }
    return finalizeHashWord(hash)
}

/// The value hash of an existential's payload: what it holds, opened back to
/// its concrete type, and the type beside it.
///
/// The type is hashed beside the bytes because the bytes alone do not carry it
/// here: the key's own `viewType` field says `AnyView` for every erased view,
/// whatever is inside. Without this, a `Text` and a `Divider` whose structs
/// happen to hold the same bytes would be one key.
///
/// Recursive by construction, through the gate rather than around it: the
/// payload of an `AnyView(AnyView(x))` is itself boxed, its dynamic type says
/// so, and it is asked the same question.
@MainActor
func erasedViewValueHash(_ view: any View) -> Int {
    var folded = mixHashWord(hashFoldSeed, UInt64(bitPattern: Int64(viewValueHash(view))))
    folded = mixHashWord(folded, UInt64(UInt(bitPattern: ObjectIdentifier(type(of: view)))))
    return finalizeHashWord(folded)
}
