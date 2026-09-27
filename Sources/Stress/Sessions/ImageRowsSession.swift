//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageRowsSession.swift
//
//  Rows whose values are heavy: each holds a decoded picture, and draws a
//  line of shading from it. The row's value is what a value memo keeps to
//  compare against, so this is the session that prices keeping it: a memo
//  that holds each drawn row's value between frames holds a picture per row.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import TUIkit

// MARK: - The model

/// A gallery: pictures that arrive, leave and are replaced, and which one is
/// selected.
@Observable
@MainActor
final class Gallery {
    /// One picture, decoded: its pixels are part of its value.
    struct Picture: Identifiable {
        let id: Int
        /// Bumped when the picture is replaced, so two values of one picture
        /// compare equal exactly when they hold the same pixels.
        var version: Int
        var pixels: RGBAImage
    }

    var pictures: [Picture]
    var selection: Int?
    private(set) var nextID: Int

    init(pictures: [Picture]) {
        self.pictures = pictures
        nextID = pictures.count
    }

    /// A new picture's id, never used before.
    func makeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    /// A picture of `Gallery.pictureSize`, its pixels a function of `seed`.
    static func picture(id: Int, version: Int, seed: UInt64) -> Picture {
        let (width, height) = pictureSize
        let pixels = (0..<(width * height)).map { index -> RGBA in
            let h = mix(seed, index)
            return RGBA(r: UInt8(truncatingIfNeeded: h), g: UInt8(truncatingIfNeeded: h >> 8), b: UInt8(truncatingIfNeeded: h >> 16))
        }
        return Picture(id: id, version: version, pixels: RGBAImage(width: width, height: height, pixels: pixels))
    }

    /// 64 × 32 pixels: 8 KB a picture.
    static let pictureSize = (64, 32)
}

extension Gallery.Picture: Equatable {
    /// By id and version, which stand for the pixels: comparing 2,048 pixels
    /// per row per frame is not what an app's `==` does.
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id && lhs.version == rhs.version }
}

// MARK: - The page

/// A count over a list of pictures, each drawn as a line of shading.
struct GalleryPage: View {
    let gallery: Gallery

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "\(gallery.pictures.count) pictures")
            List(selection: Binding(get: { gallery.selection }, set: { gallery.selection = $0 })) {
                ForEach(gallery.pictures) { picture in PictureRow(picture: picture) }
            }
        }
    }
}

/// A picture's number, version and a 32-cell line of shading, one cell per
/// two columns of pixels, from their mean brightness.
private struct PictureRow: View, Equatable {
    let picture: Gallery.Picture

    var body: some View {
        Text(verbatim: "#\(picture.id).\(picture.version) " + shading)
    }

    private var shading: String {
        let image = picture.pixels
        let shades: [Character] = [" ", "░", "▒", "▓", "█"]
        return String(
            (0..<(image.width / 2)).map { cell -> Character in
                var total = 0
                for y in 0..<image.height {
                    for x in (cell * 2)..<(cell * 2 + 2) {
                        let pixel = image.pixels[y * image.width + x]
                        total += Int(pixel.r) + Int(pixel.g) + Int(pixel.b)
                    }
                }
                let mean = total / (image.height * 2 * 3)
                return shades[min(shades.count - 1, mean * shades.count / 256)]
            })
    }
}

// MARK: - The script

/// Someone going through a gallery while pictures arrive, leave and are
/// replaced underneath.
@MainActor
final class ImageRowsSession: StressSession {
    private let gallery: Gallery
    private var random: SessionRandom

    init(config: StressConfig) {
        let seed = config.seed
        gallery = Gallery(pictures: (0..<config.sized(300)).map { Gallery.picture(id: $0, version: 0, seed: mix(seed, $0)) })
        random = SessionRandom(seed: seed ^ 0x1A6E)
    }

    var page: GalleryPage { GalleryPage(gallery: gallery) }

    func step(_ index: Int) -> SessionStep {
        if index == 0 { return SessionStep(action: "focus", keys: [KeyEvent(key: .tab)]) }
        switch random.pick([("down", 30), ("page", 8), ("replace", 20), ("arrive", 12), ("leave", 8), ("quiet", 22)]) {
        case "down":
            return SessionStep(action: "select", keys: Array(repeating: KeyEvent(key: .down), count: random.within(1...3)))
        case "page":
            return SessionStep(action: "page", keys: [KeyEvent(key: random.below(3) == 0 ? .pageUp : .pageDown)])
        case "replace":
            let at = random.below(gallery.pictures.count)
            let old = gallery.pictures[at]
            gallery.pictures[at] = Gallery.picture(id: old.id, version: old.version + 1, seed: random.next())
            return SessionStep(action: "replace")
        case "arrive":
            let picture = Gallery.picture(id: gallery.makeID(), version: 0, seed: random.next())
            gallery.pictures.insert(picture, at: random.below(gallery.pictures.count + 1))
            return SessionStep(action: "arrive")
        case "leave":
            guard gallery.pictures.count > 1 else { return SessionStep(action: "quiet") }
            gallery.pictures.remove(at: random.below(gallery.pictures.count))
            return SessionStep(action: "leave")
        default:
            return SessionStep(action: "quiet")
        }
    }

    /// The count is the model's.
    func check(_ screen: [String], after index: Int) -> String? {
        let count = "\(gallery.pictures.count) pictures"
        return screen.contains { $0.hasPrefix(count) } ? nil : "the header does not say \(count)"
    }

    static let descriptor = SessionDescriptor(
        id: "image-rows",
        summary: "a list of rows each holding a decoded 64×32 picture, which arrive, leave and are replaced",
        exercises:
            "row values that are heavy — 8 KB of pixels each — under the row memo, List windowing and "
            + "selection: the resident size of what a memo keeps of a row's value",
        make: { config, width, height, cold in
            DrivenSession(ImageRowsSession(config: config), width: width, height: height, cold: cold)
        })
}
