//  🖥️ TUIkit — Terminal UI Kit for Swift
//  InteriorPaddingSupport.swift
//
//  Created by Wade Tregaskis
//  License: MIT

@testable import TUIkitView

/// The byte ranges inside a type's `MemoryLayout.size` that no stored field
/// covers — padding BETWEEN fields — found from the runtime's field metadata
/// and recursing into struct and tuple fields.
///
/// Enum and optional fields are taken whole, and that is a limit of this
/// measure, not a claim that their bytes are defined: an optional whose `nil`
/// is spelled in its payload's spare values (`String?`, a closure's, `Color?`)
/// has bytes nothing writes when `nil` is stored in place, and a generic
/// enum's inactive payload keeps what was there (measured 2026-09-28). What a
/// type needs beyond "no padding" to hash soundly is the value-hash plan's
/// business.
func interiorPadding(of type: Any.Type) -> [Range<Int>] {
    func size(_ type: Any.Type) -> Int {
        func measure<T>(_: T.Type) -> Int { MemoryLayout<T>.size }
        return _openExistential(type, do: measure)
    }
    func gaps(of type: Any.Type, at base: Int) -> [Range<Int>] {
        var fields: [(offset: Int, type: Any.Type, kind: RuntimeFields.Kind)] = []
        RuntimeFields.forEach(of: type) { _, offset, field, kind in
            fields.append((offset, field, kind))
            return true
        }
        var found: [Range<Int>] = []
        var covered = 0
        for field in fields.sorted(by: { $0.offset < $1.offset }) {
            if field.offset > covered { found.append(base + covered..<base + field.offset) }
            if field.kind == .struct || field.kind == .tuple {
                found += gaps(of: field.type, at: base + field.offset)
            }
            covered = max(covered, field.offset + size(field.type))
        }
        if !fields.isEmpty, covered < size(type) { found.append(base + covered..<base + size(type)) }
        return found
    }
    return gaps(of: type, at: 0)
}
