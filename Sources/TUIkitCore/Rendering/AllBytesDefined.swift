//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AllBytesDefined.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// A non-generic enum whose values are only ever built by code that knows its
/// layout, so every byte of every value is written — which lets the per-pass
/// memos' value hash (TUIkitView's `ValueHashPlan`) read it whole, as it does a
/// word, rather than bypass the memo for any view holding one.
///
/// Why that holds, measured (2026-09-28, arm64 macOS, Swift 6.2.4 and 6.4, at
/// -Onone and -O): compiled code that builds an enum case writes the whole
/// payload area, the unused part of a smaller case's payload included; so does
/// a copy, generic or not, of a value built that way. The ONE thing that writes
/// part of a payload is the enum's own inject witness, which the runtime calls
/// where the layout is not known at compile time: generic code building a case
/// of a type parameter (an enum that is generic, or `Optional<Self>`'s `nil` —
/// the optional's business, not this type's), and a module that sees the type
/// resiliently. So a conformer must be:
/// - an enum — the rule is about cases, and anything else carrying the marker
///   bypasses;
/// - not generic, so no generic code can build its cases;
/// - trivially copyable (`_isPOD`), so no copy is ever field by field;
/// - built only where its layout is known: internal, with its cases built only
///   in its own module (conformed there, which this protocol living in the
///   lowest module allows), or public and `@frozen` — `@frozen` changes nothing
///   in a build without library evolution, which is how TUIkit is built, and
///   keeps this true in one with it.
///
/// `AllBytesDefinedTests` pins every conformer against all of that: the shape
/// above, and each case stored in place — by code that knows the layout, into
/// memory filled two ways — with every byte coming out the same, at the suite's
/// optimisation level (a control shows the measure sees a padding byte it
/// misses). A new conformer goes on its list. One that is not — or not yet —
/// is still held to the shape where it is read: the plan builder bypasses a
/// marked type that is not an enum, not trivial, or generic (its qualified
/// name carries arguments). That a copy keeps every byte
/// rests on the conformer being trivially copyable, and on the design's
/// probes: such a copy is a `memcpy`, or a load and store of the parts a build
/// stores.
package protocol _AllBytesDefined {}
