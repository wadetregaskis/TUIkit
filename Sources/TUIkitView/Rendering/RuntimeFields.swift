//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RuntimeFields.swift
//
//  A type's stored fields, read from the runtime's field metadata with no
//  instance: the stdlib's `_forEachField`, rebuilt on the runtime entry
//  points it calls.
//
//  Why not `_forEachField` itself: it is `@_spi(Reflection)`, and an SPI is
//  visible only where the toolchain ships the stdlib's PRIVATE module
//  interface. swift.org's toolchains do; Xcode's SDKs ship only the public
//  one. So `@_spi(Reflection) import Swift` built everywhere this was tried —
//  swiftly's 6.2, 6.3 and 6.4, Linux — and failed on every Xcode, which is
//  how most apps are built. The entry points below are what `_forEachField`
//  is made of (stdlib/public/core/ReflectionMirror.swift), exported by the
//  runtime on every platform since Swift 5.2, and declared here exactly as
//  the stdlib declares them for itself — all but `swift_isClassType`, which
//  the compiler reserves (it calls it itself, and warns that binding it
//  "will become an error"); the kind answers the same question.
//
//  Performance-profile §58 turned down `@_silgen_name` for the same trap one
//  level up: `_forEachFieldWithKeyPath` takes a stdlib struct that is not
//  `@frozen`, passed indirectly, so binding it meant guessing an ABI. These
//  take a metadata pointer, an `Int`, and a pointer to a C struct the runtime
//  fills in, so the one layout depended on is that struct's — unchanged since
//  5.2, and padded below so a runtime that appends a field cannot write past
//  it.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - The runtime's entry points

/// The runtime's kind for `type` — ``RuntimeFields/Kind``'s raw value.
@_silgen_name("swift_getMetadataKind")
private func runtimeMetadataKind(_: Any.Type) -> UInt

/// How many stored fields `type` has, a class's superclasses' included.
@_silgen_name("swift_reflectionMirror_recursiveCount")
private func runtimeRecursiveFieldCount(_: Any.Type) -> Int

/// The declared type of field `index`, with its name written to `field`.
@_silgen_name("swift_reflectionMirror_recursiveChildMetadata")
private func runtimeRecursiveFieldType(
    _: Any.Type, index: Int, fieldMetadata: UnsafeMutablePointer<RuntimeFieldMetadata>
) -> Any.Type

/// The byte offset of field `index`.
@_silgen_name("swift_reflectionMirror_recursiveChildOffset")
private func runtimeRecursiveFieldOffset(_: Any.Type, index: Int) -> Int

/// What the runtime writes about one field — the stdlib's
/// `_FieldReflectionMetadata`, field for field, since the runtime writes it
/// through a pointer. `name` belongs to the caller once written, and
/// `freeFunc` is how to give it back.
private struct RuntimeFieldMetadata {
    var name: UnsafePointer<CChar>?
    var freeFunc: (@convention(c) (UnsafePointer<CChar>?) -> Void)?
    var isStrong = false
    var isVar = false
    /// Room for fields a later runtime might append, which it would write
    /// without knowing this struct stops short of them. Never read.
    private var reserved: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0)
}

// MARK: - The walk over them

/// A type's stored fields, as the runtime's field metadata lists them.
package enum RuntimeFields {
    /// What to list — the stdlib's `_EachFieldOptions`, same raw values.
    package struct Options: OptionSet, Sendable {
        package let rawValue: UInt32

        package init(rawValue: UInt32) { self.rawValue = rawValue }

        /// Ask for a class's fields. Asked of a class without it — or of
        /// anything else with it — the walk lists nothing and answers `false`,
        /// as `_forEachField` does.
        package static let classType = Self(rawValue: 1 << 0)
    }

    /// The runtime's kind for a type — the stdlib's `_MetadataKind`, for the
    /// kinds the type walk tells apart. Any other raw value, including a kind
    /// added to the runtime after this was written, is ``unknown``.
    ///
    /// The runtime names a constrained existential (`any Collection<Int>`)
    /// "extended existential", 0x307. It is ``unknown`` here, as the stdlib's
    /// enum reported it to the type walk this replaced, so what the walk
    /// refuses is unchanged.
    package enum Kind: UInt, Sendable {
        case `class` = 0
        case `struct` = 0x200
        case `enum` = 0x201
        case optional = 0x202
        case foreignClass = 0x203
        case opaque = 0x300
        case tuple = 0x301
        case function = 0x302
        case existential = 0x303
        case metatype = 0x304
        case objcClassWrapper = 0x305
        case existentialMetatype = 0x306
        /// `Builtin.FixedArray`, the storage of an `InlineArray`: `count` elements
        /// of one type, laid out at its stride (``RuntimeFields/fixedArray(_:)``).
        case fixedArray = 0x308
        case unknown = 0xffff

        /// Any kind of class: what the runtime's `swift_isClassType` answers,
        /// and what it decides from (`Metadata::isAnyKindOfClass`).
        package var isClass: Bool {
            switch self {
            case .class, .objcClassWrapper, .foreignClass: true
            default: false
            }
        }

        /// The runtime's kind for `type`. Read from the type itself, so it
        /// needs no field metadata: a type from a module built without it
        /// still has a kind.
        package init(of type: Any.Type) {
            self = Self(rawValue: runtimeMetadataKind(type)) ?? .unknown
        }
    }

    /// A fixed-size array's element count and element type, or `nil` for any other
    /// kind — read from its metadata, which the runtime lays out as its kind, then
    /// the count (a pointer-sized signed integer), then the element's metadata
    /// (`TargetFixedArrayTypeMetadata`, swift/ABI/Metadata.h).
    ///
    /// Checked against the array's own layout before it is believed: `count`
    /// elements at the element's stride must be what the array occupies, or it is
    /// not what this reads it as, and the caller bypasses.
    package static func fixedArray(_ type: Any.Type) -> (count: Int, element: Any.Type)? {
        guard Kind(of: type) == .fixedArray else { return nil }
        let metadata = unsafeBitCast(type, to: UnsafeRawPointer.self)
        let word = MemoryLayout<Int>.size
        let count = metadata.load(fromByteOffset: word, as: Int.self)
        let elementMetadata = metadata.load(fromByteOffset: 2 * word, as: UnsafeRawPointer.self)
        let element = unsafeBitCast(elementMetadata, to: Any.Type.self)
        guard count >= 0 else { return nil }
        let size = _openExistential(type, do: fixedArraySize)
        let (elementSize, elementStride) = _openExistential(element, do: sizeAndStride)
        let expected = count == 0 ? 0 : (count - 1) * elementStride + elementSize
        guard size == expected || size == count * elementStride else { return nil }
        return (count, element)
    }

    /// Lists `type`'s stored fields to `body` — name (`""` where the runtime
    /// has none), byte offset, declared type, kind — in declaration order,
    /// stopping early when `body` answers `false`. Answers whether it listed
    /// them all: `false` for a class asked without ``Options/classType`` (or
    /// anything else asked with it), or when `body` stopped it.
    ///
    /// A type whose module was built without reflection metadata lists no
    /// fields and answers `true`, as `_forEachField` does; the type walk is
    /// what tells that apart.
    @discardableResult
    package static func forEach(
        of type: Any.Type, options: Options = [],
        body: (UnsafePointer<CChar>, Int, Any.Type, Kind) -> Bool
    ) -> Bool {
        forEachListed(of: type, options: options) { name, offset, fieldType, kind, _ in
            body(name, offset, fieldType, kind)
        }
    }

    /// One stored field, as the runtime's field metadata lists it.
    package struct Field {
        /// The type the field belongs to, and its index there: where ``name``
        /// is read back from.
        private let owner: Any.Type
        private let index: Int
        /// Its byte offset from the start of the value.
        package let offset: Int
        /// Its declared type.
        package let type: Any.Type
        /// The runtime's kind for ``type``.
        package let kind: Kind
        /// Whether the field holds a value of ``type`` as itself: `false` for
        /// a `weak`, `unowned` or `unowned(unsafe)` reference, whose storage is
        /// a reference the runtime manages rather than the declared type's
        /// value — a `weak var` declared `C?` does not hold a `C?` a reader
        /// may load as one.
        package let isStrong: Bool

        init(owner: Any.Type, index: Int, offset: Int, type: Any.Type, kind: Kind, isStrong: Bool) {
            self.owner = owner
            self.index = index
            self.offset = offset
            self.type = type
            self.kind = kind
            self.isStrong = isStrong
        }

        /// The field's name, `""` where the runtime has none; a tuple's
        /// unlabelled elements are `.0`, `.1`, ….
        ///
        /// Read from the runtime when asked, not when the field is listed: the
        /// value-hash plan builder lists the fields of every type it plans and
        /// wants a name only to say why a type bypasses.
        package var name: String {
            var field = RuntimeFieldMetadata()
            _ = runtimeRecursiveFieldType(owner, index: index, fieldMetadata: &field)
            defer { field.freeFunc?(field.name) }
            return field.name.map { String(cString: $0) } ?? ""
        }
    }

    /// `type`'s stored fields (not a class's), in declaration order — what
    /// ``forEach(of:options:body:)`` lists, with whether each is held
    /// strongly.
    ///
    /// Empty for a type whose module was built without reflection metadata,
    /// as for one with no stored fields: the caller tells those apart by the
    /// type's size.
    package static func fields(of type: Any.Type) -> [Field] {
        var found: [Field] = []
        _ = forEachListed(of: type, options: []) { _, offset, fieldType, kind, isStrong in
            found.append(
                Field(
                    owner: type, index: found.count, offset: offset, type: fieldType, kind: kind,
                    isStrong: isStrong))
            return true
        }
        return found
    }

    /// The one walk over the runtime's entry points both listings share.
    private static func forEachListed(
        of type: Any.Type, options: Options,
        body: (UnsafePointer<CChar>, Int, Any.Type, Kind, Bool) -> Bool
    ) -> Bool {
        guard Kind(of: type).isClass == options.contains(.classType) else { return false }
        for index in 0..<runtimeRecursiveFieldCount(type) {
            let offset = runtimeRecursiveFieldOffset(type, index: index)
            var field = RuntimeFieldMetadata()
            let fieldType = runtimeRecursiveFieldType(type, index: index, fieldMetadata: &field)
            defer { field.freeFunc?(field.name) }
            let listed = withUnnamedFallback(field.name) { name in
                body(name, offset, fieldType, Kind(of: fieldType), field.isStrong)
            }
            guard listed else { return false }
        }
        return true
    }

    /// `name`, or an empty C string where the runtime gave none.
    private static func withUnnamedFallback(
        _ name: UnsafePointer<CChar>?, _ body: (UnsafePointer<CChar>) -> Bool
    ) -> Bool {
        if let name { return body(name) }
        return "".withCString(body)
    }
}

/// `T`'s size, for ``RuntimeFields/fixedArray(_:)``.
private func fixedArraySize<T>(_: T.Type) -> Int { MemoryLayout<T>.size }

/// `T`'s size and stride, for ``RuntimeFields/fixedArray(_:)``.
private func sizeAndStride<T>(_: T.Type) -> (Int, Int) { (MemoryLayout<T>.size, MemoryLayout<T>.stride) }
