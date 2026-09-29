//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AllBytesDefinedTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling
@testable import TUIkitView

/// The bytes of a `T` that `build` leaves as they were: `build` runs twice, on
/// memory filled with two different bytes first, and a byte that comes out
/// different in the two is one it did not write.
///
/// `build` must store the value INTO the memory it is handed, from code that
/// knows `T` — a closure written where `T` is concrete, assigning through the
/// pointer (`{ $0.pointee = .someCase(1) }`), for a trivial `T` only (the
/// assignment releases nothing it overwrites). That is how compiled code that
/// knows a layout stores a value, and the route measured to write in place at
/// -Onone and -O alike. `initialize(to:)` is NOT such a route: at -Onone it
/// builds the value in a temporary and copies the temporary whole, and a copy
/// of a trivial type is a `memcpy`, so whatever the build left unwritten
/// arrives as the temporary's junk — the same junk both times, which reads as
/// written (a padded struct's padding did, measured on 6.2.4).
private func unwrittenBytes<T>(of _: T.Type, builtBy build: (UnsafeMutablePointer<T>) -> Void) -> Set<Int> {
    let size = MemoryLayout<T>.size
    let built = [UInt8(0xAA), 0x55].map { fill in
        let memory = UnsafeMutablePointer<T>.allocate(capacity: 1)
        for offset in 0..<size {
            UnsafeMutableRawPointer(memory).storeBytes(of: fill, toByteOffset: offset, as: UInt8.self)
        }
        build(memory)
        let bytes = Array(UnsafeRawBufferPointer(start: memory, count: size))
        memory.deinitialize(count: 1)
        memory.deallocate()
        return bytes
    }
    return Set((0..<size).filter { built[0][$0] != built[1][$0] })
}

// Top-level rather than nested in the tests: `_openExistential` handed a
// generic function nested in a test crashes swiftc 6.2.4 ("Fell off the end:
// generic_type_param_type"), as the value-hash design found.

private func isTrivial<T>(_: T.Type) -> Bool { _isPOD(T.self) }

/// One conformer, and each of its cases stored in place by concrete code.
private struct Conformer {
    let type: Any.Type
    /// Each case's build, and the bytes it left unwritten.
    let unwrittenByCase: () -> [(build: Int, unwritten: Set<Int>)]

    /// `builds` are written where `T` is concrete, each storing one case —
    /// every case of the type, between them.
    init<T>(_ type: T.Type, _ builds: [(UnsafeMutablePointer<T>) -> Void]) {
        self.type = type
        unwrittenByCase = {
            builds.indices.map { ($0, unwrittenBytes(of: T.self, builtBy: builds[$0])) }
        }
    }
}

/// A flag, then a word: the control, whose padding nothing writes.
private struct PaddedControl {
    var flag: Bool
    var count: Int
}

/// Every conformer of `_AllBytesDefined` — a type the value hash reads whole,
/// on the promise that every byte of every value of it is written — held to
/// that promise.
///
/// The promise rests on who builds the values: code that knows the layout
/// writes a whole payload area, the unused part of a smaller case's payload
/// included; only an enum's inject witness writes part of one, and only
/// generic code or a module that sees the enum resiliently calls it (measured
/// 2026-09-28 by the value-hash design's probes). So each conformer must be an
/// enum, not generic, trivially copyable, and internal or `@frozen` — and each
/// of its cases, stored in place here by code that knows its layout, must come
/// out with every byte written. That is measured at the suite's own
/// optimisation level (-Onone, as CI runs it); the design's probes measured
/// -O too.
///
/// A copy is not measured: a trivially copyable value's copy is a `memcpy`
/// where the type is not known, and a load and store of the same parts the
/// build stored where it is — nothing a build that writes every byte could
/// lose (and the design measured both).
///
/// A new conformer goes on the list below.
@MainActor
@Suite("Every type the value hash reads whole has every byte of every value written")
struct AllBytesDefinedTests {
    /// Each conformer, and each of its cases, stored in place.
    private static let conformers: [Conformer] = [
        Conformer(Color.ColorValue.self, [
            { $0.pointee = .ansi(.brightRed) }, { $0.pointee = .terminalDefault },
            { $0.pointee = .palette256(200) }, { $0.pointee = .rgb(red: 1, green: 2, blue: 3) },
            { $0.pointee = .semantic(.accent) }, { $0.pointee = .terminalForeground },
            { $0.pointee = .terminalBackground },
        ]),
        Conformer(LineLimit.self, [
            { $0.pointee = .unlimited }, { $0.pointee = .lines(3) }, { $0.pointee = .lines(2, reservesSpace: true) },
        ]),
        Conformer(AnimationCurve.self, [
            { $0.pointee = .bezier(p1x: 0.1, p1y: 0.2, p2x: 0.3, p2y: 0.4) },
            { $0.pointee = .spring(omega: 12, zeta: 0.5) },
        ]),
        Conformer(StatedColor.self, [{ $0.pointee = .unstated }, { $0.pointee = .stated(.rgb(1, 2, 3)) }]),
        Conformer(StatedLineLimit.self, [{ $0.pointee = .unstated }, { $0.pointee = .stated(.lines(4)) }]),
        Conformer(StatedFont.self, [
            { $0.pointee = .unstated }, { $0.pointee = .statedNone }, { $0.pointee = .stated(.headline) },
        ]),
        Conformer(Animation.Repeat.self, [
            { $0.pointee = .count(2, autoreverses: true) }, { $0.pointee = .forever(autoreverses: false) },
        ]),
    ]

    @Test("Each is a trivial, non-generic enum")
    func shape() {
        for conformer in Self.conformers {
            let type = conformer.type
            #expect(type is any _AllBytesDefined.Type, "\(type)")
            #expect(RuntimeFields.Kind(of: type) == .enum, "\(type)")
            // Opened outside `#expect`: inside the macro's closure,
            // `_openExistential` crashes swiftc 6.2.4 as well.
            let trivial = _openExistential(type, do: isTrivial)
            #expect(trivial, "\(type)")
            #expect(!String(reflecting: type).contains("<"), "\(type) is generic")
        }
    }

    @Test("Every case, stored in place by code that knows the layout, has every byte written")
    func everyCaseWrittenWhole() {
        for conformer in Self.conformers {
            for (build, unwritten) in conformer.unwrittenByCase() {
                #expect(unwritten.isEmpty, "\(conformer.type), build #\(build): \(unwritten.sorted())")
            }
        }
    }

    /// Without this, a measure that could not see an unwritten byte would pass
    /// every conformer — as the one this replaced did.
    @Test("The measure sees a byte a build leaves unwritten")
    func measureSeesUnwrittenBytes() {
        let unwritten = unwrittenBytes(of: PaddedControl.self) { $0.pointee = PaddedControl(flag: true, count: 3) }
        #expect(unwritten == Set(1..<MemoryLayout<Int>.alignment))
    }

    @Test("The value hash reads each whole, and a colour with it")
    func planDense() {
        let plans = ValueHashPlans()
        for conformer in Self.conformers {
            #expect(plans.plan(for: conformer.type).pointee.shape == .dense, "\(conformer.type)")
        }
        #expect(plans.plan(for: Color.self).pointee.shape == .dense)
        // An animation reads its curve whole, and only its padding is skipped.
        #expect(plans.plan(for: Animation.self).pointee.shape == .runs)
    }
}
