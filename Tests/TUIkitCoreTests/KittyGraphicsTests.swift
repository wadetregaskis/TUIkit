//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KittyGraphicsTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

/// The wire format. Nothing here needs a terminal: the escapes are strings
/// with a specification, and the specification is what these pin.
@Suite("Kitty graphics: the escapes")
struct KittyGraphicsEscapeTests {

    @Test("base64 matches the RFC 4648 vectors, padding included")
    func base64Vectors() {
        func encode(_ text: String) -> String {
            var out: [UInt8] = []
            KittyGraphics.base64(Array(text.utf8), into: &out)
            return KittyGraphics.ascii(out)
        }
        #expect(encode("").isEmpty)
        #expect(encode("f") == "Zg==")
        #expect(encode("fo") == "Zm8=")
        #expect(encode("foo") == "Zm9v")
        #expect(encode("foob") == "Zm9vYg==")
        #expect(encode("fooba") == "Zm9vYmE=")
        #expect(encode("foobar") == "Zm9vYmFy")
    }

    /// The distinction the protocol draws and a naive encoder loses: no `m` at
    /// all means "this is the whole image", `m=0` means "the last chunk of
    /// several". A single-escape transmit that says `m=0` is claiming to end a
    /// run it never started.
    @Test("A one-escape transmit carries no chunk marker")
    func singleChunkOmitsTheMarker() {
        let pixels = [UInt8](repeating: 0x40, count: 2 * 2 * 4)
        let escape = KittyGraphics.transmit(pixels: pixels, width: 2, height: 2, id: 7)
        #expect(escape.hasPrefix("\u{1B}_Ga=t,q=2,f=32,t=d,s=2,v=2,i=7;"))
        #expect(escape.hasSuffix("\u{1B}\\"))
        #expect(!escape.contains("m="))
        // One escape, so exactly one terminator.
        #expect(escape.components(separatedBy: "\u{1B}\\").count == 2)
    }

    @Test("A large transmit chunks, and only the first chunk carries the keys")
    func chunkingIsWellFormed() {
        // Comfortably past one chunk: 4096 base64 characters is 3072 bytes.
        let pixels = [UInt8](repeating: 0x11, count: 64 * 64 * 4)
        let escape = KittyGraphics.transmit(pixels: pixels, width: 64, height: 64, id: 3)
        let chunks = escape.components(separatedBy: "\u{1B}_G").dropFirst()
        #expect(chunks.count > 1)
        #expect(chunks.first?.hasPrefix("a=t,q=2,f=32,t=d,s=64,v=64,i=3,m=1;") == true)
        for chunk in chunks.dropFirst().dropLast() {
            #expect(chunk.hasPrefix("m=1,q=2;"), "a middle chunk says only that more follow")
        }
        #expect(chunks.last?.hasPrefix("m=0,q=2;") == true, "the last chunk ends the run")
        // Every chunk is quiet, not just the first: the acknowledgement is
        // emitted when the transmission completes, and the last chunk is what
        // completes it.
        for chunk in chunks {
            #expect(chunk.contains("q=2"))
        }
        // Every chunk's payload is within the protocol's cap.
        for chunk in chunks {
            let payload = chunk.drop { $0 != ";" }.dropFirst().dropLast(2)
            #expect(payload.count <= KittyGraphics.chunkSize)
        }
    }

    /// Every command that is not a question suppresses its reply, because in
    /// an application the reply arrives on stdin and is read as typing.
    @Test("Everything but the query is quiet")
    func commandsAreQuiet() {
        let pixels = [UInt8](repeating: 0, count: 4)
        #expect(KittyGraphics.transmit(pixels: pixels, width: 1, height: 1, id: 1).contains("q=2"))
        #expect(KittyGraphics.placement(id: 1, columns: 2, rows: 2).contains("q=2"))
        #expect(KittyGraphics.delete(id: 1).contains("q=2"))
        #expect(!KittyGraphics.query(id: 1).contains("q=2"), "the query's reply is the point")
    }

    @Test("A placement is virtual, or it is not a cell")
    func placementIsVirtual() {
        #expect(
            KittyGraphics.placement(id: 9, columns: 20, rows: 8)
                == "\u{1B}_Ga=p,U=1,q=2,i=9,c=20,r=8\u{1B}\\")
    }

    /// `d=I` frees the pixels; `d=i` would drop the placements and leave the
    /// image in the terminal's store, which is the leak this call exists to
    /// prevent.
    @Test("Delete frees the image, not just its placements")
    func deleteFreesTheImage() {
        #expect(KittyGraphics.delete(id: 4) == "\u{1B}_Ga=d,d=I,q=2,i=4\u{1B}\\")
    }

    @Test("A request the protocol cannot express produces nothing")
    func unexpressibleRequestsAreEmpty() {
        let pixels = [UInt8](repeating: 0, count: 16)
        #expect(KittyGraphics.transmit(pixels: pixels, width: 0, height: 2, id: 1).isEmpty)
        #expect(KittyGraphics.transmit(pixels: pixels, width: 2, height: 2, id: 0).isEmpty)
        #expect(
            KittyGraphics.transmit(pixels: pixels, width: 2, height: 2, id: 0x100_0000).isEmpty,
            "an id past 24 bits would need a fourth mark on every cell")
        #expect(
            KittyGraphics.transmit(pixels: [1, 2, 3], width: 4, height: 4, id: 1).isEmpty,
            "fewer pixels than the declared size")
        #expect(KittyGraphics.placement(id: 0, columns: 2, rows: 2).isEmpty)
        #expect(KittyGraphics.delete(id: 0).isEmpty)
    }
}

/// The half that becomes cells.
@Suite("Kitty graphics: placeholder rows")
struct KittyGraphicsPlaceholderTests {

    @Test("A row is exactly as many cells as it claims")
    func rowMeasuresItsColumns() {
        let rows = KittyGraphics.placeholderRows(id: 5, columns: 20, rows: 3)
        #expect(rows.count == 3)
        for row in rows {
            #expect(row.strippedLength == 20)
        }
    }

    @Test("The id travels in the foreground, split across the three channels")
    func idIsTheForeground() {
        let row = KittyGraphics.placeholderRows(id: 0x01_2345, columns: 1, rows: 1)[0]
        #expect(row.hasPrefix("\u{1B}[38;2;1;35;69m"))
        #expect(row.hasSuffix("\u{1B}[39m"), "and it stops at the end of the row")
    }

    /// Row and column are position in the table, not codepoint, so the first
    /// cell of the first row carries the first entry twice.
    @Test("Every cell spells out its own row and column")
    func everyCellNamesItself() {
        let rows = KittyGraphics.placeholderRows(id: 1, columns: 3, rows: 2)
        let second = Array(rows[1].unicodeScalars.drop(while: { $0 != "\u{10EEEE}" }))
        // placeholder, row mark, column mark — three scalars per cell, and the
        // row mark repeats while the column mark advances.
        #expect(second[0] == "\u{10EEEE}")
        #expect(second[1] == KittyGraphics.diacritic(1))
        #expect(second[2] == KittyGraphics.diacritic(0))
        #expect(second[3] == "\u{10EEEE}")
        #expect(second[4] == KittyGraphics.diacritic(1), "same row")
        #expect(second[5] == KittyGraphics.diacritic(1), "next column")
        #expect(second[7] == KittyGraphics.diacritic(1))
        #expect(second[8] == KittyGraphics.diacritic(2))
    }

    /// The run-length form is not used, and this is what says so: no cell
    /// after the first is a bare placeholder.
    @Test("No cell relies on the one before it")
    func noRunLengthElision() {
        let row = KittyGraphics.placeholderRows(id: 1, columns: 8, rows: 1)[0]
        let scalars = Array(row.unicodeScalars.drop(while: { $0 != "\u{10EEEE}" }))
        // 8 cells x 3 scalars, plus the four-scalar `ESC [ 3 9 m` reset.
        #expect(scalars.prefix(24).filter { $0 == "\u{10EEEE}" }.count == 8)
        for cell in 0..<8 {
            #expect(scalars[cell * 3] == "\u{10EEEE}")
        }
    }

    @Test("A request past what the protocol can address produces nothing")
    func boundsAreRefused() {
        #expect(KittyGraphics.placeholderRows(id: 1, columns: 0, rows: 1).isEmpty)
        #expect(KittyGraphics.placeholderRows(id: 0, columns: 1, rows: 1).isEmpty)
        #expect(
            KittyGraphics.placeholderRows(
                id: 1, columns: KittyGraphics.maximumCellExtent + 1, rows: 1
            ).isEmpty,
            "there is no mark for the 298th column")
        #expect(
            !KittyGraphics.placeholderRows(
                id: 1, columns: KittyGraphics.maximumCellExtent, rows: 1
            ).isEmpty,
            "…and the 297th is fine")
    }
}

/// The table is the protocol. A wrong entry tears one stripe out of a picture
/// and changes nothing else, so its invariants are asserted rather than
/// trusted.
@Suite("Kitty graphics: the diacritics table")
struct KittyGraphicsDiacriticTests {

    /// The one test in this file whose oracle is not this codebase.
    ///
    /// Transcribed from kitty's `docs/graphics-protocol.rst`, which prints a
    /// 2x2 placeholder for image id 42 as:
    ///
    ///     printf "\e[38;5;42m\U10EEEE\U0305\U0305\U10EEEE\U0305\U030D\e[39m\n"
    ///     printf "\e[38;5;42m\U10EEEE\U030D\U0305\U10EEEE\U030D\U030D\e[39m\n"
    ///
    /// and states that U+0305 means 0, U+030D means 1 and U+030E means 2.
    ///
    /// This exists because the first version of this file used **U+10EFFF**,
    /// and every test passed: they all compared the encoder against the
    /// encoder's own constant. A terminal drew a grid of missing-glyph boxes
    /// and nothing else was wrong. A constant taken from a specification has
    /// to be checked against that specification, spelled out, or the tests
    /// only prove the code is self-consistent.
    @Test("the placeholder and the first three marks are the spec's own")
    func matchesTheSpecificationsExample() {
        #expect(Unicode.Scalar.terminalImagePlaceholder == "\u{10EEEE}")
        #expect(KittyGraphics.diacritic(0) == "\u{0305}")
        #expect(KittyGraphics.diacritic(1) == "\u{030D}")
        #expect(KittyGraphics.diacritic(2) == "\u{030E}")

        // The cells of the spec's own 2x2 example, foreground aside — this
        // encoder spells the id as a direct-colour triple where the example
        // uses the 256-colour form, which the spec allows either way.
        let rows = KittyGraphics.placeholderRows(id: 42, columns: 2, rows: 2)
        let cells = rows.map { row in
            String(row.unicodeScalars.drop(while: { $0 != "\u{10EEEE}" }).prefix(6))
        }
        #expect(cells[0] == "\u{10EEEE}\u{0305}\u{0305}\u{10EEEE}\u{0305}\u{030D}")
        #expect(cells[1] == "\u{10EEEE}\u{030D}\u{0305}\u{10EEEE}\u{030D}\u{030D}")
    }

    @Test("297 marks, in the order the protocol reads them")
    func tableShape() {
        #expect(KittyGraphics.rowColumnDiacritics.count == 297)
        #expect(KittyGraphics.rowColumnDiacritics.first == 0x0305)
        #expect(KittyGraphics.rowColumnDiacritics.last == 0x1D244)
        // Position is meaning, so a duplicate is two cells claiming one column.
        #expect(Set(KittyGraphics.rowColumnDiacritics).count == 297)
        // The published table is sorted, and staying sorted is the cheapest
        // check that nothing was inserted or reordered by hand.
        #expect(KittyGraphics.rowColumnDiacritics == KittyGraphics.rowColumnDiacritics.sorted())
    }

    /// The invariant that ties the table to the rest of the framework: a mark
    /// adds no cells. One that did would make every image row measure wider
    /// than the picture, and every layout around it would be wrong.
    @Test("Every mark is zero cells wide")
    func marksAddNoWidth() {
        for value in KittyGraphics.rowColumnDiacritics {
            guard let scalar = Unicode.Scalar(value) else {
                Issue.record("\(String(value, radix: 16)) is not a scalar")
                continue
            }
            #expect(
                scalar.loneTerminalWidth == 0,
                "U+\(String(value, radix: 16, uppercase: true)) must add no width")
        }
    }

    /// …and that they really do combine, rather than breaking into cells of
    /// their own. `terminalWidth` is asked of the CLUSTER, so a mark that did
    /// not combine would make a one-cell placeholder measure two or three.
    @Test("A placeholder plus its two marks is one grapheme cluster")
    func marksCombineWithThePlaceholder() {
        for index in [0, 1, 42, 128, 296] {
            var cell = String(Unicode.Scalar.terminalImagePlaceholder)
            cell.unicodeScalars.append(KittyGraphics.diacritic(index))
            cell.unicodeScalars.append(KittyGraphics.diacritic(index))
            #expect(cell.count == 1, "index \(index) broke the cluster")
            #expect(cell.strippedLength == 1)
        }
    }
}
