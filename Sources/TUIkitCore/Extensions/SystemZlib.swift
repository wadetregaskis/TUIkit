//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SystemZlib.swift
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

// MARK: - The system's zlib, if it has one

/// Deflate, borrowed from whatever `libz` the host already has — and nothing
/// at all where it has none.
///
/// ## Why borrowed and not carried
///
/// The Kitty graphics protocol takes a payload zlib-compressed (`o=z`), and a
/// gradient rendered as pixels is exactly the kind of payload that shrinks by
/// an order of magnitude under deflate: a 320×17 ramp is 16 KB raw and 1.1 KB
/// compressed, because its seventeen rows are the same row. A photograph gains
/// far less, but still gains. What the package will NOT do is carry a deflate
/// encoder — vendored, hand-rolled, or as a dependency — for a feature that
/// only ever saves bytes: the uncompressed path is correct everywhere, and an
/// encoder is a permanent maintenance charge against a saving that is real
/// only on the hosts that answer the compression probe.
///
/// So the encoder is the system's. Every macOS and every mainstream Linux has
/// a `libz`, it is one `dlopen` away, and the only two symbols this needs have
/// had the same signatures since 1995. Where the library is absent — or the
/// platform has no `dlopen` — ``isAvailable`` is `false` and every transmission
/// goes uncompressed, exactly as before. Nothing is assumed about the library
/// at build time, and nothing links against it.
///
/// ## What is deliberately not here
///
/// Only `compress2` and `compressBound` — a whole buffer in, a whole buffer
/// out. The streaming interface (`deflateInit_`/`deflate`/`deflateEnd`) needs
/// the library's `z_stream` layout, which differs by build, and a mismatch
/// there corrupts memory rather than failing. The one-shot call takes plain
/// pointers and lengths and is safe to call through a function pointer with
/// no header at all.
public enum SystemZlib {

    /// Whether the host's zlib was found and both entry points resolved.
    public static var isAvailable: Bool { library != nil }

    /// `bytes`, deflated in the RFC 1950 (zlib) container the graphics
    /// protocol's `o=z` expects — or `nil` where there is no zlib, or the
    /// library refused.
    ///
    /// - Parameters:
    ///   - bytes: The raw payload.
    ///   - level: zlib's own 0–9. The default is zlib's default (6), which on
    ///     a smooth ramp compresses three times better than level 1 for a cost
    ///     that is invisible next to transmitting the result.
    public static func compress(_ bytes: [UInt8], level: Int32 = 6) -> [UInt8]? {
        guard let library, !bytes.isEmpty else { return nil }
        let bound = Int(library.bound(CUnsignedLong(bytes.count)))
        guard bound > 0 else { return nil }
        var written = CUnsignedLong(bound)
        let out = [UInt8](unsafeUninitializedCapacity: bound) { buffer, initialized in
            let status = bytes.withUnsafeBufferPointer { source in
                library.compress(buffer.baseAddress, &written, source.baseAddress, CUnsignedLong(bytes.count), level)
            }
            initialized = status == 0 ? Int(written) : 0
        }
        return out.isEmpty ? nil : out
    }

    // MARK: - Binding

    /// `int compress2(Bytef *dest, uLongf *destLen, const Bytef *source, uLong sourceLen, int level)`.
    private typealias Compress2 = @convention(c) (
        UnsafeMutablePointer<UInt8>?, UnsafeMutablePointer<CUnsignedLong>?,
        UnsafePointer<UInt8>?, CUnsignedLong, Int32
    ) -> Int32

    /// `uLong compressBound(uLong sourceLen)`.
    private typealias CompressBound = @convention(c) (CUnsignedLong) -> CUnsignedLong

    private struct Library {
        let compress: Compress2
        let bound: CompressBound
    }

    /// Resolved once for the process. A missing library is a permanent fact
    /// about the host, and the handle is never closed: it is the system's own
    /// shared library, already mapped for everything else that uses it.
    private static let library: Library? = {
        #if canImport(Darwin) || canImport(Glibc) || canImport(Musl)
            // The soname first, then the bare name: Linux distributions ship
            // `libz.so.1` and only the development package adds `libz.so`;
            // macOS has both spellings of its dylib.
            let names = ["libz.so.1", "libz.1.dylib", "libz.dylib", "libz.so"]
            for name in names {
                guard let handle = dlopen(name, RTLD_NOW | RTLD_LOCAL) else { continue }
                guard let compress = dlsym(handle, "compress2"), let bound = dlsym(handle, "compressBound")
                else {
                    dlclose(handle)
                    continue
                }
                return Library(
                    compress: unsafeBitCast(compress, to: Compress2.self),
                    bound: unsafeBitCast(bound, to: CompressBound.self))
            }
            return nil
        #else
            return nil
        #endif
    }()
}
