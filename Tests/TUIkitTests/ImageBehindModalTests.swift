//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageBehindModalTests.swift
//
//  A terminal-graphics image is drawn by CELLS: U+10EEEE placeholders whose
//  FOREGROUND COLOUR carries the image id, and whose two combining marks carry
//  the row and column. Everything about that is ordinary text, which is the
//  whole point of the design — until something treats it as ordinary text and
//  throws the styling away.
//
//  `dimmedAsBackdrop` does exactly that: it flattens every line behind a modal
//  to plain characters. For a picture that is not dimming, it is erasure — the
//  id goes with the SGR, and cells naming no image draw nothing at all.
//
//  Created by Testing
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("An image behind a modal")
struct ImageBehindModalTests {

    private let id: KittyGraphics.ImageID = 0xAB_CDEF

    /// The id travels in the foreground colour, so this is what "the terminal
    /// still knows which picture" looks like in the bytes.
    private var idEscape: String {
        "38;2;\((id >> 16) & 0xFF);\((id >> 8) & 0xFF);\(id & 0xFF)"
    }

    private func imageBuffer(columns: Int = 6, rows: Int = 2) -> FrameBuffer {
        FrameBuffer(lines: KittyGraphics.placeholderRows(id: id, columns: columns, rows: rows))
    }

    /// The control: before anything dims it, every row names the image.
    @Test("A placeholder row carries the image id")
    func placeholderCarriesTheID() {
        let buffer = imageBuffer()
        #expect(buffer.lines.allSatisfy { $0.contains(idEscape) })
    }

    /// The defect. A modal dims what is behind it, and the dim flattens the
    /// row — taking the foreground that names the picture with it. What is
    /// left is placeholder cells belonging to no image, which is not a dimmed
    /// picture but no picture.
    @Test("Dimming as a backdrop must not strip the image's identity")
    func dimmedBackdropKeepsTheID() {
        let dimmed = imageBuffer().dimmedAsBackdrop(
            foreground: .rgb(120, 120, 120), background: .rgb(0, 0, 0))
        #expect(
            dimmed.lines.allSatisfy { $0.contains(idEscape) },
            "the foreground carrying the image id was stripped: \(dimmed.lines)")
    }

    /// …and the placeholder cells themselves must survive, for the same
    /// reason. A picture behind a sheet should recede, not vanish.
    @Test("Dimming as a backdrop keeps the placeholder cells")
    func dimmedBackdropKeepsThePlaceholders() {
        let dimmed = imageBuffer().dimmedAsBackdrop(
            foreground: .rgb(120, 120, 120), background: .rgb(0, 0, 0))
        #expect(
            dimmed.lines.allSatisfy { $0.unicodeScalars.contains(.terminalImagePlaceholder) },
            "the placeholder cells were replaced: \(dimmed.lines)")
    }
}
