//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ValueHashPlan.swift
//
//  One type's value-hash plan — which of its bytes the value hash reads, and
//  which parts it reads through typed Swift instead — and the walk that
//  builds it from the runtime's field metadata.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// How the value hash reads one type's values: the runs of bytes every value
/// defines, and the parts only typed Swift can read. Built once per type, from
/// the type alone (``ValueHashPlanBuilder``), and kept by ``ValueHashPlans``.
package struct ValueHashPlan {
    /// What the hot path branches on.
    package enum Shape: UInt8, Sendable {
        /// Every byte of every value is defined and says something: the value
        /// is hashed as it lies, word by word — exactly the loop the hash used
        /// before plans, at the same cost.
        case dense
        /// Some bytes are never defined (padding between fields): loads over
        /// the runs that are.
        case runs
        /// Some part needs typed Swift to read — an optional's case, a
        /// conditional's branch, an existential's payload — beside any runs.
        case steps
        /// The type holds something the hash cannot read without reading bytes
        /// a value may leave undefined: a payload enum that has not opted in, a
        /// constrained existential, a type the runtime cannot describe. A memo
        /// measures such a value every time and keeps nothing: a lost hit,
        /// never a wrong answer.
        case bypass
    }

    /// A run of bytes every value defines, `[offset, offset + count)`.
    package struct Run: Equatable, Sendable {
        package let offset: Int
        package let count: Int

        package var range: Range<Int> { offset..<(offset + count) }
    }

    /// A part read through typed Swift, at `offset`.
    struct Step {
        enum Action {
            /// The type reads itself: ``_ValueHashing``.
            case typed(any _ValueHashing.Type)
            /// An existential field, opened through its static type.
            case existential(ExistentialField)
        }

        let offset: Int
        let action: Action
    }

    package let shape: Shape
    /// `MemoryLayout.size` of the type.
    package let size: Int
    /// The defined runs, in offset order; all of `0..<size` when dense.
    let runs: UnsafeBufferPointer<Run>
    /// The typed steps, in offset order.
    let steps: UnsafeBufferPointer<Step>
    /// Why the type bypasses, naming the field that made it — for a test and
    /// the census; `nil` unless ``shape`` is ``Shape/bypass``.
    package let bypassReason: String?

    /// The defined runs, as ranges — what a test compares.
    package var definedRanges: [Range<Int>] { runs.map(\.range) }

    /// Each step's offset and what it reads, as text — what a test compares.
    package var stepDescriptions: [String] {
        steps.map { step in
            switch step.action {
            case .typed(let type): "\(step.offset): \(type)"
            case .existential(let field): "\(step.offset): existential \(field)"
            }
        }
    }
}

// MARK: - The builder

/// Builds a type's ``ValueHashPlan`` from the runtime's field metadata
/// (``RuntimeFields`` — the walk the type walk rests on too), with no instance
/// of the type: what is read is decided by the type, the same for every value.
///
/// The rules, kind by kind:
/// - **Struct / tuple**: each field in turn, at its offset, flattened into the
///   plan — a nested struct's fields become this plan's runs and steps. A gap
///   between two fields is skipped only if it is exactly the next field's
///   alignment padding (`next.offset == roundUp(end, next.alignment)`); any
///   other gap, an overlap, or fields that end short of the type's size bypass,
///   because something the metadata does not describe is there. A struct that
///   lists no fields but has a size had its field metadata stripped (the
///   runtime answers as if it had none): bypass. A field of type `()` bypasses
///   too — how a runtime before 6.4 reports noncopyable storage, which the type
///   walk refuses for the same reason. Any other field of no size is skipped,
///   wherever it is reported. In a struct imported from C, ANY gap bypasses:
///   the importer's field list leaves out bitfields, so a gap shaped like
///   padding may be a field's bytes.
/// - **A field held weakly or unowned**: its bytes, never loaded as its
///   declared type — its storage is a reference the runtime manages. A weak
///   class-bound existential's `nil` writes its witness-table word too, as
///   zero: measured assigned in place over a scribbled word and initialised,
///   at -Onone and -O (6.2.4, arm64, 2026-09-28).
/// - **Builtins, class references, existential metatypes, functions** (both
///   words of a closure): their bytes, all defined. Addresses, so equal
///   values built apart can differ, which costs a miss, never a wrong answer.
///   x87's `Float80` (x86): the ten bytes a store writes, not the six after
///   them.
/// - **A metatype** (`Int.Type`, `(any P).Type`, a class's): bypass, and so
///   does an optional or a tuple holding one — never a typed step, which
///   would load it at the runtime's layout. Swift stores a metatype that has
///   only one value THIN, in no bytes at all, wherever its type is written
///   out: a field `Int.Type` takes none, `Int.Type?` one tag byte, and a tuple
///   holding either is laid out so. Where it may hold more than one value — a
///   class's, a type parameter's — it is a pointer. The runtime reports the
///   pointer's layout for every one of them (`Int.Type?` eight bytes, and in
///   `(UInt8, Int.Type?)` the optional at offset 8, where the stored tuple
///   has it at 1), and nothing typed tells a class's metatype from another's
///   — so no layout the plan could read is known to be the stored one. A
///   tuple that bypasses for ANY reason counts as holding one: the walk stops
///   at the element that stopped it, which may lie before a metatype it never
///   reached (`(AppChoice, Int.Type)?`, 64-bit: stored, the enum's 17 bytes,
///   `nil` in its tag; as the runtime lays it out, `nil` in the metatype's
///   word at 24 — padding, as stored).
/// - **An enum of one byte or none**: its bytes — every write of a one-byte
///   value writes the byte.
/// - **`_AllBytesDefined`** (TUIkitCore: a non-generic, trivial enum only ever built
///   where its layout is known): its bytes.
/// - **`Optional`**: whole bytes where every value's are all written, measured
///   (2026-09-28) — a payload with no spare values, so `nil` has a tag byte of
///   its own and the payload is zero-filled, over a payload that is itself
///   dense (`Int?`, `Date?`); or a payload that is ONE builtin, reference,
///   existential metatype of one word (`Any.Type`: no witness tables) or
///   one-byte enum, whose spare values `nil` writes whole (`Bool?`, a class
///   reference's, `[Int]?`). `OptionalWholeBytesTests` measures both in the
///   suite. Otherwise a typed step: `== nil`, then the payload's own plan
///   (`String?`, a closure's, `Color?`).
/// - **``_ValueHashing``** (`ConditionalView`, `AnyView`): a typed step.
/// - **An opaque existential** (`any P`, `Any`): a typed step that loads it as
///   its static type and opens it — see ``ExistentialField``. Never its
///   container's words: the unused ones are undefined, and a boxed payload's
///   box address says nothing about the payload.
/// - **Anything else**: bypass — a payload enum that has not opted in (an
///   app's, a generic one such as `Result`), a constrained existential (the
///   runtime reports it as a kind the walk does not know), any unknown kind.
struct ValueHashPlanBuilder {
    /// Lists a type's stored fields: ``RuntimeFields/fields(of:)``, which a
    /// test replaces to see a type whose metadata was stripped bypass.
    typealias FieldLister = (Any.Type) -> [RuntimeFields.Field]

    /// One part of a plan, at an offset from the start of the planned type.
    enum Item {
        case bytes(offset: Int, count: Int, leaf: Leaf)
        case step(ValueHashPlan.Step)
    }

    /// What a run of bytes is, for the optional rule's "one leaf" test.
    enum Leaf {
        /// A builtin: an integer, a float, a pointer, a buffer's reference.
        case builtin
        case reference
        /// An existential metatype of one word (`Any.Type`,
        /// `AnyObject.Type`): a pointer to a type's metadata, and nothing
        /// else. Never a metatype of one type (`Int.Type`), which bypasses.
        case metatype
        /// An enum of one byte or none.
        case smallEnum
        /// Anything else, including several leaves read together.
        case other

        /// Whether an optional of this leaf, alone, spells `nil` in spare
        /// values it writes whole, where it is a word or less (the builder
        /// checks the size: a builtin can be wider). Not a
        /// closure's (`nil` writes its first word, not its context), not an
        /// existential metatype's with witness tables (`nil` writes its
        /// metadata word, not them).
        var nilWritesItWhole: Bool {
            switch self {
            case .builtin, .reference, .metatype, .smallEnum: true
            case .other: false
            }
        }
    }

    /// Why a type cannot be planned: the path to what stopped it, and what.
    struct Bypass: Error {
        let reason: String
        /// Whether what stopped it may not even lie as the runtime lays it
        /// out — a metatype, which a struct may store in no bytes at all, or
        /// a tuple the walk did not see the whole of, which may hold one after
        /// what stopped it. An optional of such a thing bypasses with it
        /// rather than falling back to its typed step, which would load it at
        /// the runtime's layout. Kept as it leaves a struct too, though a
        /// struct's own layout is always the stored one: an optional of a
        /// struct holding a metatype could take its typed step, and all it
        /// would hash is a `nil` — the `.some` payload bypasses.
        var layoutUnknown = false
    }

    let listFields: FieldLister

    init(listFields: @escaping FieldLister = { RuntimeFields.fields(of: $0) }) {
        self.listFields = listFields
    }

    /// The parts of `type`'s plan, or why it bypasses.
    func items(for type: Any.Type) -> Result<[Item], Bypass> {
        var items: [Item] = []
        do {
            try describe(type, at: 0, path: { "\(type)" }, into: &items)
            return .success(items)
        } catch let bypass as Bypass {
            return .failure(bypass)
        } catch {
            return .failure(Bypass(reason: "\(type): \(error)"))
        }
    }

    /// Appends the parts of a value of `type` lying at `base` to `items`.
    ///
    /// `path` names where in the planned type this value lies, for a bypass's
    /// reason, and is asked for only by one: it demangles a type's name and
    /// reads its fields' names back from the runtime, work a plan that does
    /// not bypass never needs.
    private func describe(
        _ type: Any.Type, at base: Int, path: () -> String, into items: inout [Item]
    ) throws {
        let layout = Self.layout(of: type)
        guard layout.size > 0 else { return }
        let kind = RuntimeFields.Kind(of: type)
        if kind == .optional {
            try describeOptional(type, at: base, size: layout.size, path: path, into: &items)
            return
        }
        #if !(os(Windows) || os(Android)) && (arch(i386) || arch(x86_64))
        if type == Float80.self {
            // x87's 80-bit float: a store writes ten bytes of the sixteen it
            // occupies, and the six after them are never written.
            items.append(.bytes(offset: base, count: 10, leaf: .builtin))
            return
        }
        #endif
        if let typed = type as? any _ValueHashing.Type {
            items.append(.step(.init(offset: base, action: .typed(typed))))
            return
        }
        if type is any _AllBytesDefined.Type {
            guard kind == .enum, Self.isTrivial(type), !Self.isGeneric(type) else {
                throw Bypass(reason: "\(path()): marked _AllBytesDefined, but not a trivial non-generic enum")
            }
            items.append(.bytes(offset: base, count: layout.size, leaf: .other))
            return
        }
        try describe(kind, type, at: base, size: layout.size, path: path, into: &items)
    }

    /// ``describe(_:at:path:into:)`` for a type that has not opted in to
    /// anything: by its kind alone.
    private func describe(
        _ kind: RuntimeFields.Kind, _ type: Any.Type, at base: Int, size: Int, path: () -> String,
        into items: inout [Item]
    ) throws {
        switch kind {
        case .struct:
            try describeFields(of: type, at: base, size: size, path: path, into: &items)
        case .tuple:
            // The walk stops at the first element that bypasses, so one that
            // lies before a metatype hides it — and a tuple's layout, unlike a
            // struct's, is the runtime's, worked out from its elements'. An
            // optional around it must not fall back to its typed step.
            do {
                try describeFields(of: type, at: base, size: size, path: path, into: &items)
            } catch var bypass as Bypass {
                bypass.layoutUnknown = true
                throw bypass
            }
        case .class, .foreignClass, .objcClassWrapper:
            items.append(.bytes(offset: base, count: size, leaf: .reference))
        case .metatype:
            throw Bypass(
                reason: "\(path()): a metatype, \(type), which a struct may store in no bytes", layoutUnknown: true)
        case .existentialMetatype where size == MemoryLayout<UnsafeRawPointer>.size:
            // `Any.Type`, `AnyObject.Type`: a metatype with no witness tables,
            // one pointer — and so a metatype for the optional rule.
            items.append(.bytes(offset: base, count: size, leaf: .metatype))
        case .existentialMetatype, .function:
            items.append(.bytes(offset: base, count: size, leaf: .other))
        case .opaque:
            items.append(.bytes(offset: base, count: size, leaf: .builtin))
        case .enum where size <= 1:
            items.append(.bytes(offset: base, count: size, leaf: .smallEnum))
        case .enum:
            throw Bypass(reason: "\(path()): a payload enum")
        case .existential:
            items.append(.step(.init(offset: base, action: .existential(ExistentialField(type)))))
        default:
            throw Bypass(reason: "\(path()): a kind the walk does not know (\(kind))")
        }
    }

    /// A struct's or tuple's fields, in offset order, with the gaps between
    /// them proved to be alignment padding.
    ///
    /// Not in a struct imported from C: its field list is the one the importer
    /// wrote, which leaves out what Swift cannot declare — bitfields above all
    /// — without a trace, so a gap exactly the shape of alignment padding may
    /// hold a field's bytes. There, any gap bypasses, padding or not.
    private func describeFields(
        of type: Any.Type, at base: Int, size: Int, path: () -> String, into items: inout [Item]
    ) throws {
        let fields = listFields(type).sorted { $0.offset < $1.offset }
        guard !fields.isEmpty else { throw Bypass(reason: "\(path()): no field metadata") }
        var end = 0
        // Asked only at a gap, and once: it prints the type's qualified name.
        var importedFromC: Bool?
        for field in fields {
            guard field.type != Void.self else {
                throw Bypass(reason: "\(Self.path(path(), field)): storage reported as ()")
            }
            let fieldLayout = Self.layout(of: field.type)
            // Nothing to read, and no byte of its own: where a layout is fixed
            // at compile time, the runtime reports a field of no size at
            // offset 0, whatever was declared before it.
            if fieldLayout.size == 0 { continue }
            guard field.offset >= end else {
                throw Bypass(reason: "\(Self.path(path(), field)): overlaps the field before")
            }
            if field.offset > end {
                guard field.offset == Self.roundUp(end, to: fieldLayout.alignment) else {
                    throw Bypass(reason: "\(Self.path(path(), field)): a gap before it that is not alignment padding")
                }
                if importedFromC == nil { importedFromC = Self.isImportedFromC(type) }
                guard importedFromC == false else {
                    throw Bypass(reason: "\(Self.path(path(), field)): a gap before it, in a struct imported from C")
                }
            }
            if field.isStrong {
                try describe(field.type, at: base + field.offset, path: { Self.path(path(), field) }, into: &items)
            } else {
                items.append(.bytes(offset: base + field.offset, count: fieldLayout.size, leaf: .other))
            }
            end = field.offset + fieldLayout.size
        }
        guard end == size else { throw Bypass(reason: "\(path()): its fields end at \(end), not at \(size)") }
    }

    /// Where `field` lies, under `parent`'s path. A tuple's unlabelled
    /// elements are already named `.0`, `.1`, ….
    private static func path(_ parent: String, _ field: RuntimeFields.Field) -> String {
        let name = field.name
        return name.hasPrefix(".") ? parent + name : "\(parent).\(name)"
    }

    /// Whether `type` was imported from C: `__C` — the module Swift files
    /// every imported declaration under — leads its qualified name, as does
    /// `__C_Synthesized`, for the types the importer makes up.
    private static func isImportedFromC(_ type: Any.Type) -> Bool {
        String(reflecting: type).hasPrefix("__C")
    }

    /// An optional: whole bytes where every value's are all written, else a
    /// typed step. See the type's rules.
    private func describeOptional(
        _ type: Any.Type, at base: Int, size: Int, path: () -> String, into items: inout [Item]
    ) throws {
        guard let wrapped = (type as? any _ElementTypesProviding.Type)?.elementTypes.first,
            let typed = type as? any _ValueHashing.Type
        else { throw Bypass(reason: "\(path()): an optional the walk cannot open") }
        let wrappedSize = Self.layout(of: wrapped).size
        var payload: [Item] = []
        do {
            try describe(wrapped, at: 0, path: { path() + "!" }, into: &payload)
            // A tag byte of its own, over a payload every byte of which is
            // defined: `nil` zero-fills the payload.
            if size == wrappedSize + 1, Self.coversWhole(payload, size: wrappedSize) {
                items.append(.bytes(offset: base, count: size, leaf: .other))
                return
            }
            // One scalar of a word or less, whose spare values spell `nil`,
            // written whole. Not a wider builtin (an executor's two words):
            // only scalars of a word or less are measured to be.
            if size == wrappedSize, wrappedSize <= MemoryLayout<UInt>.size, payload.count == 1,
                case .bytes(0, wrappedSize, let leaf) = payload[0], leaf.nilWritesItWhole
            {
                items.append(.bytes(offset: base, count: size, leaf: leaf))
                return
            }
        } catch let bypass as Bypass where bypass.layoutUnknown {
            // Not even the optional's own layout is known to be the stored
            // one: its typed step would load it at the runtime's.
            throw bypass
        } catch {
            // A payload the plan cannot read: the typed step reads the case,
            // and hashes a `nil` whatever its payload's type.
        }
        items.append(.step(.init(offset: base, action: .typed(typed))))
    }

    /// Whether `items` are runs of bytes, and nothing else, covering
    /// `0..<size` without a gap.
    static func coversWhole(_ items: [Item], size: Int) -> Bool {
        var end = 0
        for item in items {
            guard case .bytes(let offset, let count, _) = item, offset == end else { return false }
            end += count
        }
        return end == size
    }

    static func roundUp(_ value: Int, to alignment: Int) -> Int {
        (value + alignment - 1) / alignment * alignment
    }

    static func layout(of type: Any.Type) -> (size: Int, alignment: Int) {
        func measure<T>(_: T.Type) -> (size: Int, alignment: Int) {
            (MemoryLayout<T>.size, MemoryLayout<T>.alignment)
        }
        return _openExistential(type, do: measure)
    }

    /// Whether `type` is generic, or nested in a generic type: its qualified
    /// name carries arguments. Asked only of a type marked
    /// `_AllBytesDefined`, once per table; a name holding a `<` of its own
    /// (a raw identifier) is taken for generic, the safe side.
    private static func isGeneric(_ type: Any.Type) -> Bool {
        String(reflecting: type).contains("<")
    }

    private static func isTrivial(_ type: Any.Type) -> Bool {
        func trivial<T>(_: T.Type) -> Bool { _isPOD(T.self) }
        return _openExistential(type, do: trivial)
    }
}
