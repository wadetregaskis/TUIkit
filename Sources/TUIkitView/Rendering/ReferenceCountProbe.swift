//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReferenceCountProbe.swift
//
//  Whether an object's reference count has moved to a side table: what the
//  first weak reference to it does, for good.
//
//  Created by Wade Tregaskis
//  License: MIT

/// Reads whether an object's reference count lives in a side table.
///
/// The Swift runtime keeps an object's reference counts inline, in the word
/// after its type pointer, until something forms a weak reference to it. Then
/// the counts move to a side table for the rest of the object's life, and
/// every retain and release of it takes the slow path through that table. The
/// render cache is retained and released with every context a render copies,
/// so whether it has a side table is worth a check of its own
/// (`RenderCache.Link` is why it should not): this reads the inline word's two
/// top bits, which the 64-bit runtimes set together exactly when the word
/// names a side table.
///
/// A diagnostic, for tests and `Stress`, never for a decision a render makes.
/// It reads the runtime's private layout, so it checks that layout first, on
/// an object of its own: a fresh one must read inline, and the same one after
/// a weak reference to it must read as moved. Where either fails — another
/// word size, another runtime — it answers `nil`.
package enum ReferenceCountProbe {
    /// Whether `object`'s reference count lives in a side table; `nil` when
    /// this runtime's layout is not the one this reads.
    package static func usesSideTable(_ object: AnyObject) -> Bool? {
        layoutIsKnown ? movedToSideTable(object) : nil
    }

    /// The inline word's two top bits, set together when it names a side
    /// table.
    private static func movedToSideTable(_ object: AnyObject) -> Bool {
        let word = Unmanaged.passUnretained(object).toOpaque()
            .load(fromByteOffset: MemoryLayout<UnsafeRawPointer>.size, as: UInt.self)
        return word >> (UInt.bitWidth - 2) == 0b11
    }

    /// Whether the layout reads as expected on an object of the probe's own.
    ///
    /// Only a 64-bit runtime keeps the word this reads; on a 32-bit one
    /// (`wasm32`) the check is not compiled at all, rather than written as a
    /// runtime test the compiler can see is always false, which it reports as
    /// code that will never run.
    private static let layoutIsKnown: Bool = {
        #if _pointerBitWidth(_64)
            final class Control {}
            let control = Control()
            guard !movedToSideTable(control) else { return false }
            weak var weakly = control
            let moved = movedToSideTable(control)
            withExtendedLifetime(weakly) {}
            return moved
        #else
            return false
        #endif
    }()
}
