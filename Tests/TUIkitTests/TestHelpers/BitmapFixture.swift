//  🖥️ TUIkit — Terminal UI Kit for Swift
//  BitmapFixture.swift
//
//  A real image file, for the tests that need the LOADER to have run rather
//  than an `RGBAImage` handed straight to a converter.
//
//  BMP, and 24-bit uncompressed at that, because it is the one format both
//  decoders take that can be written by hand: `NSImage` reads it on Apple
//  platforms and the bundled stb_image reads it everywhere else, and neither
//  needs a byte of it compressed. A PNG would need a deflate stream and a
//  checksum to say the same thing.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// A 24-bit uncompressed BMP of `width` × `height`, written to a temporary
/// file that is deleted when the returned handle goes away.
///
/// The image is a simple vertical split — left half `left`, right half
/// `right` — so a test can tell an upright render from a mirrored or rotated
/// one, which a flat fill cannot.
final class BitmapFixture {
    /// Where the file is. Hand this to `Image(.file(_:))`.
    let path: String

    let width: Int
    let height: Int

    init(
        width: Int, height: Int,
        left: (r: UInt8, g: UInt8, b: UInt8) = (20, 20, 20),
        right: (r: UInt8, g: UInt8, b: UInt8) = (230, 230, 230)
    ) throws {
        self.width = width
        self.height = height
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tuikit-bitmap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("fixture.bmp")
        try Self.bmpData(width: width, height: height, left: left, right: right).write(to: file)
        path = file.path
        self.directory = directory
    }

    private let directory: URL

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// The file's bytes: a 14-byte file header, a 40-byte `BITMAPINFOHEADER`,
    /// then bottom-up BGR rows each padded to a multiple of four bytes.
    private static func bmpData(
        width: Int, height: Int,
        left: (r: UInt8, g: UInt8, b: UInt8), right: (r: UInt8, g: UInt8, b: UInt8)
    ) -> Data {
        let rowStride = (width * 3 + 3) & ~3
        let pixelBytes = rowStride * height
        var data = Data()

        func append32(_ value: Int) {
            var little = UInt32(truncatingIfNeeded: value).littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func append16(_ value: Int) {
            var little = UInt16(truncatingIfNeeded: value).littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }

        data.append(contentsOf: Array("BM".utf8))
        append32(14 + 40 + pixelBytes)  // file size
        append32(0)  // reserved
        append32(14 + 40)  // offset to the pixels
        append32(40)  // DIB header size
        append32(width)
        append32(height)  // positive: bottom-up
        append16(1)  // planes
        append16(24)  // bits per pixel
        append32(0)  // BI_RGB — no compression
        append32(pixelBytes)
        append32(2835)  // 72 dpi, in pixels per metre
        append32(2835)
        append32(0)  // palette colours used
        append32(0)  // palette colours that matter

        for _ in 0..<height {
            var row = Data()
            for column in 0..<width {
                let colour = column < width / 2 ? left : right
                row.append(contentsOf: [colour.b, colour.g, colour.r])  // BMP is BGR
            }
            row.append(contentsOf: [UInt8](repeating: 0, count: rowStride - width * 3))
            data.append(row)
        }
        return data
    }
}
