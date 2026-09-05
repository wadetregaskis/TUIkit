//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SystemZlibTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

/// The borrowed deflate against the same library's inflate.
///
/// Round-tripped rather than compared to a byte vector: deflate is
/// deterministic for one zlib, and the hosts CI runs on do not share one —
/// Fedora ships zlib-ng, macOS ships Apple's — so the bytes differ while every
/// one of them inflates to the input. The test borrows `uncompress` the same
/// way the framework borrows `compress2`, so it needs nothing the framework
/// does not.
@Suite("System zlib")
struct SystemZlibTests {

    /// `int uncompress(Bytef *dest, uLongf *destLen, const Bytef *source, uLong sourceLen)`.
    private typealias Uncompress = @convention(c) (
        UnsafeMutablePointer<UInt8>?, UnsafeMutablePointer<CUnsignedLong>?, UnsafePointer<UInt8>?, CUnsignedLong
    ) -> Int32

    private static func inflate(_ bytes: [UInt8], expecting count: Int) -> [UInt8]? {
        #if canImport(Darwin) || canImport(Glibc) || canImport(Musl)
            for name in ["libz.so.1", "libz.1.dylib", "libz.dylib", "libz.so"] {
                guard let handle = dlopen(name, RTLD_NOW | RTLD_LOCAL), let symbol = dlsym(handle, "uncompress")
                else { continue }
                let uncompress = unsafeBitCast(symbol, to: Uncompress.self)
                var written = CUnsignedLong(count)
                var out = [UInt8](repeating: 0, count: count)
                let status = out.withUnsafeMutableBufferPointer { dest in
                    bytes.withUnsafeBufferPointer { source in
                        uncompress(dest.baseAddress, &written, source.baseAddress, CUnsignedLong(bytes.count))
                    }
                }
                return status == 0 && Int(written) == count ? out : nil
            }
        #endif
        return nil
    }

    @Test("Where a zlib was found, a deflated payload inflates back to the input")
    func roundTrip() throws {
        try #require(SystemZlib.isAvailable, "no libz on this host — nothing to test, and nothing is compressed")
        // A ramp, as a gradient transmits one: seventeen identical rows of
        // 320 pixels.
        var row: [UInt8] = []
        for x in 0..<320 { row += [UInt8(x * 255 / 319), UInt8(128 - x * 128 / 319), UInt8(x % 7 * 36)] }
        let input = Array(repeating: row, count: 17).flatMap { $0 }
        let deflated = try #require(SystemZlib.compress(input))
        #expect(deflated.count < input.count / 8, "17 identical rows: \(deflated.count) of \(input.count)")
        #expect(deflated.prefix(1) == [0x78], "RFC 1950: the CMF byte says deflate with a 32 K window")
        #expect(Self.inflate(deflated, expecting: input.count) == input)
    }

    @Test("Nothing in is nothing out, not a stream of nothing")
    func emptyInputIsDeclined() {
        #expect(SystemZlib.compress([]) == nil)
    }

    @Test("The level is honoured: the default deflates a repetitive payload at least as tightly as the fastest")
    func levelsAreDistinguishable() throws {
        try #require(SystemZlib.isAvailable)
        let input = (0..<(1280 * 68)).map { UInt8(($0 / 68) % 251) }
        let fastest = try #require(SystemZlib.compress(input, level: 1))
        let normal = try #require(SystemZlib.compress(input))
        #expect(normal.count <= fastest.count)
        #expect(Self.inflate(fastest, expecting: input.count) == input)
        #expect(Self.inflate(normal, expecting: input.count) == input)
    }
}
