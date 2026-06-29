//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ImageLoader.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

#if canImport(AppKit)
    import AppKit
    import CoreGraphics
#else
    import CSTBImage
#endif

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// MARK: - ImageLoader Protocol

/// Loads images from file paths or raw data and converts them to `RGBAImage`.
///
/// See `PlatformImageLoader` for the built-in implementation and the formats
/// it supports.
public protocol ImageLoader: Sendable {
    /// Loads an image from a file path.
    ///
    /// - Parameter path: The absolute file path to the image.
    /// - Returns: The decoded image as `RGBAImage`.
    /// - Throws: `ImageLoadError` if the file cannot be read or decoded.
    func loadImage(from path: String) throws -> RGBAImage

    /// Loads an image from raw data.
    ///
    /// - Parameter data: The image file data.
    /// - Returns: The decoded image as `RGBAImage`.
    /// - Throws: `ImageLoadError` if the data cannot be decoded.
    func loadImage(from data: Data) throws -> RGBAImage
}

// MARK: - ImageLoadError

/// Errors that can occur during image loading.
public enum ImageLoadError: Error, LocalizedError, CustomStringConvertible {
    /// The file was not found at the given path.
    case fileNotFound(String)

    /// The image format is not supported.
    case unsupportedFormat(String)

    /// The image data could not be decoded.
    case decodingFailed(String)

    /// A URL download failed.
    case downloadFailed(String)

    /// The image exceeds the maximum allowed pixel count.
    case imageTooLarge(pixelCount: Int, limit: Int)

    public var description: String {
        switch self {
        case .fileNotFound(let path):
            return "Image file not found: \(path)"
        case .unsupportedFormat(let format):
            return "Unsupported image format: \(format)"
        case .decodingFailed(let reason):
            return "Image decoding failed: \(reason)"
        case .downloadFailed(let reason):
            return "Image download failed: \(reason)"
        case .imageTooLarge(let pixelCount, let limit):
            return "Image too large: \(pixelCount) pixels (limit: \(limit))"
        }
    }

    public var errorDescription: String? { description }
}

// MARK: - Platform Image Loader

/// The built-in image loader, decoding with the best facility available for
/// the current build.
///
/// Selection is by capability rather than a hard-coded platform list: when
/// `canImport(AppKit)` holds (Apple platforms) it decodes via `NSImage`,
/// gaining the system image codecs and colour management with no third-party
/// code; otherwise it falls back to the bundled stb_image C library
/// (`CSTBImage`). Both paths produce straight-alpha, row-major RGBA, so the
/// backends are interchangeable.
///
/// Formats via the stb_image fallback: PNG, JPEG, GIF, BMP, TGA, HDR, PSD, PNM.
/// The `NSImage` path additionally decodes any format the host OS supports.
public struct PlatformImageLoader: ImageLoader {

    public init() {}

    public func loadImage(from path: String) throws -> RGBAImage {
        try loadImage(from: path, maxPixelCount: nil)
    }

    public func loadImage(from data: Data) throws -> RGBAImage {
        try loadImage(from: data, maxPixelCount: nil)
    }

    /// Loads an image from a file path with an optional pixel count limit.
    ///
    /// - Parameters:
    ///   - path: The absolute file path to the image.
    ///   - maxPixelCount: The maximum allowed total pixel count, or `nil` for no limit.
    /// - Returns: The decoded image as `RGBAImage`.
    /// - Throws: `ImageLoadError` if the file cannot be read, decoded, or exceeds the limit.
    public func loadImage(from path: String, maxPixelCount: Int?) throws -> RGBAImage {
        guard FileManager.default.fileExists(atPath: path) else {
            throw ImageLoadError.fileNotFound(path)
        }
        #if canImport(AppKit)
            guard let image = NSImage(contentsOfFile: path) else {
                throw ImageLoadError.decodingFailed("NSImage could not load image at \(path)")
            }
            return try decodeWithNSImage(image, maxPixelCount: maxPixelCount)
        #else
            return try decodeWithSTB(path: path, maxPixelCount: maxPixelCount)
        #endif
    }

    /// Loads an image from raw data with an optional pixel count limit.
    ///
    /// - Parameters:
    ///   - data: The image file data.
    ///   - maxPixelCount: The maximum allowed total pixel count, or `nil` for no limit.
    /// - Returns: The decoded image as `RGBAImage`.
    /// - Throws: `ImageLoadError` if the data cannot be decoded or exceeds the limit.
    public func loadImage(from data: Data, maxPixelCount: Int?) throws -> RGBAImage {
        #if canImport(AppKit)
            guard let image = NSImage(data: data) else {
                throw ImageLoadError.decodingFailed("NSImage could not decode image data")
            }
            return try decodeWithNSImage(image, maxPixelCount: maxPixelCount)
        #else
            return try decodeWithSTB(data: data, maxPixelCount: maxPixelCount)
        #endif
    }
}

// MARK: - stb_image Backend (non-Apple platforms)

#if !canImport(AppKit)
    extension PlatformImageLoader {

        /// Decodes a file with stb_image into straight-alpha, row-major RGBA.
        private func decodeWithSTB(path: String, maxPixelCount: Int?) throws -> RGBAImage {
            var width: Int32 = 0
            var height: Int32 = 0
            var channels: Int32 = 0

            guard let rawPixels = stbi_load(path, &width, &height, &channels, 4) else {
                let reason = String(cString: stbi_failure_reason())
                throw ImageLoadError.decodingFailed("stb_image: \(reason)")
            }
            defer { stbi_image_free(rawPixels) }

            let pixelCount = Int(width) * Int(height)
            if let limit = maxPixelCount, pixelCount > limit {
                throw ImageLoadError.imageTooLarge(pixelCount: pixelCount, limit: limit)
            }

            return pixelsFromRaw(rawPixels, width: Int(width), height: Int(height))
        }

        /// Decodes in-memory data with stb_image into straight-alpha, row-major RGBA.
        private func decodeWithSTB(data: Data, maxPixelCount: Int?) throws -> RGBAImage {
            var width: Int32 = 0
            var height: Int32 = 0
            var channels: Int32 = 0

            let rawPixels: UnsafeMutablePointer<UInt8>? = data.withUnsafeBytes { buffer in
                guard let baseAddress = buffer.baseAddress else { return nil }
                return stbi_load_from_memory(
                    baseAddress.assumingMemoryBound(to: UInt8.self),
                    Int32(data.count),
                    &width,
                    &height,
                    &channels,
                    4
                )
            }

            guard let pixels = rawPixels else {
                let reason = String(cString: stbi_failure_reason())
                throw ImageLoadError.decodingFailed("stb_image: \(reason)")
            }
            defer { stbi_image_free(pixels) }

            let pixelCount = Int(width) * Int(height)
            if let limit = maxPixelCount, pixelCount > limit {
                throw ImageLoadError.imageTooLarge(pixelCount: pixelCount, limit: limit)
            }

            return pixelsFromRaw(pixels, width: Int(width), height: Int(height))
        }

        /// Converts raw stb_image RGBA output to an `RGBAImage`.
        private func pixelsFromRaw(
            _ rawPixels: UnsafeMutablePointer<UInt8>,
            width: Int,
            height: Int
        ) -> RGBAImage {
            let count = width * height
            var pixels = [RGBA](repeating: RGBA(r: 0, g: 0, b: 0), count: count)

            for pixelIndex in 0..<count {
                let offset = pixelIndex * 4
                pixels[pixelIndex] = RGBA(
                    r: rawPixels[offset],
                    g: rawPixels[offset + 1],
                    b: rawPixels[offset + 2],
                    a: rawPixels[offset + 3]
                )
            }

            return RGBAImage(width: width, height: height, pixels: pixels)
        }
    }
#endif

// MARK: - NSImage Backend (Apple platforms)

#if canImport(AppKit)
    extension PlatformImageLoader {

        /// Decodes an `NSImage` into straight-alpha, row-major RGBA (row 0 = top)
        /// via a CoreGraphics bitmap context, matching the stb_image fallback's
        /// pixel contract so the two backends are interchangeable.
        private func decodeWithNSImage(_ image: NSImage, maxPixelCount: Int?) throws -> RGBAImage {
            var proposedRect = CGRect(origin: .zero, size: image.size)
            guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
                throw ImageLoadError.decodingFailed("NSImage has no CoreGraphics representation")
            }

            let width = cgImage.width
            let height = cgImage.height
            let pixelCount = width * height
            if let limit = maxPixelCount, pixelCount > limit {
                throw ImageLoadError.imageTooLarge(pixelCount: pixelCount, limit: limit)
            }
            guard width > 0, height > 0 else {
                return RGBAImage(width: width, height: height, pixels: [])
            }

            // Render into a known RGBA8, premultiplied-last, top-left-origin buffer.
            let bytesPerRow = width * 4
            var premultiplied = [UInt8](repeating: 0, count: height * bytesPerRow)
            let drew: Bool = premultiplied.withUnsafeMutableBytes { raw in
                guard let context = CGContext(
                    data: raw.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard drew else {
                throw ImageLoadError.decodingFailed("Could not create RGBA bitmap context")
            }

            return RGBAImage(
                width: width,
                height: height,
                pixels: Self.straightAlphaPixels(from: premultiplied, count: pixelCount)
            )
        }

        /// Converts a premultiplied-last RGBA byte buffer to straight-alpha pixels.
        private static func straightAlphaPixels(from buffer: [UInt8], count: Int) -> [RGBA] {
            var pixels = [RGBA](repeating: RGBA(r: 0, g: 0, b: 0), count: count)
            for index in 0..<count {
                let offset = index * 4
                let alpha = buffer[offset + 3]
                switch alpha {
                case 0:
                    pixels[index] = RGBA(r: 0, g: 0, b: 0, a: 0)
                case 255:
                    pixels[index] = RGBA(
                        r: buffer[offset],
                        g: buffer[offset + 1],
                        b: buffer[offset + 2],
                        a: 255
                    )
                default:
                    let a = Int(alpha)
                    pixels[index] = RGBA(
                        r: UInt8(min(255, (Int(buffer[offset]) * 255 + a / 2) / a)),
                        g: UInt8(min(255, (Int(buffer[offset + 1]) * 255 + a / 2) / a)),
                        b: UInt8(min(255, (Int(buffer[offset + 2]) * 255 + a / 2) / a)),
                        a: alpha
                    )
                }
            }
            return pixels
        }
    }
#endif

// MARK: - URL Image Cache

/// A session-scoped cache for images downloaded from URLs.
///
/// Cached entries persist for the lifetime of the application.
/// Thread-safe via an internal lock.
public final class URLImageCache: @unchecked Sendable {
    /// Shared session cache.
    public static let shared = URLImageCache()

    private var cache: [String: RGBAImage] = [:]
    private let lock = NSLock()

    private init() {}

    /// Returns a cached image for the given URL string, or nil.
    public func get(_ urlString: String) -> RGBAImage? {
        lock.lock()
        defer { lock.unlock() }
        return cache[urlString]
    }

    /// Stores an image in the cache for the given URL string.
    public func set(_ urlString: String, image: RGBAImage) {
        lock.lock()
        defer { lock.unlock() }
        cache[urlString] = image
    }
}

// MARK: - URL Image Loading

extension PlatformImageLoader {

    /// Loads an image from a URL, using the session cache.
    ///
    /// On first access the image is downloaded synchronously and cached.
    /// Subsequent calls for the same URL return the cached copy.
    ///
    /// - Parameters:
    ///   - urlString: The URL to download.
    ///   - cache: The image cache to use.
    ///   - timeout: The download timeout in seconds (default: 30).
    ///   - maxPixelCount: The maximum allowed total pixel count, or `nil` for no limit.
    /// - Returns: The decoded image.
    /// - Throws: `ImageLoadError` on network or decoding failure, or if image exceeds size limit.
    public func loadImage(
        from urlString: String,
        cache: URLImageCache = .shared,
        timeout: TimeInterval = 30,
        maxPixelCount: Int? = nil
    ) throws -> RGBAImage {
        if let cached = cache.get(urlString) {
            return cached
        }

        guard let url = URL(string: urlString) else {
            throw ImageLoadError.downloadFailed("Invalid URL: \(urlString)")
        }

        let data: Data
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = timeout

            nonisolated(unsafe) var responseData: Data?
            nonisolated(unsafe) var responseError: Error?
            let semaphore = DispatchSemaphore(value: 0)

            let task = URLSession.shared.dataTask(with: request) { d, _, error in
                responseData = d
                responseError = error
                semaphore.signal()
            }
            task.resume()
            semaphore.wait()

            if let error = responseError {
                throw error
            }
            guard let downloaded = responseData else {
                throw ImageLoadError.downloadFailed("No data received")
            }
            data = downloaded
        } catch let error as ImageLoadError {
            throw error
        } catch {
            throw ImageLoadError.downloadFailed(error.localizedDescription)
        }

        let image = try loadImage(from: data, maxPixelCount: maxPixelCount)
        cache.set(urlString, image: image)
        return image
    }
}
