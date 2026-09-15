//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalImageStoreTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// The store owns a resource that lives in another process and that nothing
/// else will ever clean up, so every one of these is about the arithmetic of
/// transmit and delete rather than about what a picture looks like.
@MainActor
@Suite("Terminal image store")
struct TerminalImageStoreTests {

    private func pixels(_ count: Int) -> [UInt8] {
        [UInt8](repeating: 0x80, count: count * 4)
    }

    /// A signature that differs only where a test says it does. The fields are
    /// compared, not parsed, so anything unique will do for "a different
    /// picture" — `label` is the knob each test turns.
    private func signature(_ label: String, pixelWidth: Int = 8, pixelHeight: Int = 8)
        -> TerminalImageSignature
    {
        TerminalImageSignature(
            source: .file(label), rawWidth: 8, rawHeight: 8,
            pixelWidth: pixelWidth, pixelHeight: pixelHeight,
            colorMode: .trueColor, toneCurve: nil, edgeContrast: 0, dithering: .none,
            monoInk: RGBA(r: 255, g: 255, b: 255), monoPaper: RGBA(r: 0, g: 0, b: 0),
            terminalColors: .unknown)
    }

    @Test("A first draw transmits the image and places it")
    func firstDrawTransmitsAndPlaces() {
        let store = TerminalImageStore()
        let rows = store.placeholderRows(
            token: "a", signature: signature("one"), columns: 4, rows: 2,
            pixels: { (pixels(64), .rgba, 8, 8) })
        #expect(rows?.count == 2)
        #expect(rows?.first?.strippedLength == 4)

        let pending = store.takePending()
        #expect(pending.contains("a=t,q=2,f=32,t=d,s=8,v=8"))
        #expect(pending.contains("a=p,U=1,q=2"))
        #expect(!pending.contains("a=d"), "nothing to delete on a first draw")
        #expect(store.takePending().isEmpty, "taking it clears it")
        #expect(store.imageCount == 1)
    }

    /// The property that makes the whole feature affordable: a picture costs
    /// its bytes once, not once a frame. An `Image` on screen re-renders many
    /// times a second — spinner pulses, focus animations — and every one of
    /// those must send nothing.
    @Test("Drawing the same image again sends nothing")
    func unchangedDrawIsFree() {
        let store = TerminalImageStore()
        var built = 0
        for _ in 0..<5 {
            _ = store.placeholderRows(
                token: "a", signature: signature("one"), columns: 4, rows: 2,
                pixels: {
                    built += 1
                    return (pixels(64), .rgba, 8, 8)
                })
        }
        _ = store.takePending()
        #expect(built == 1, "the resample ran once, not five times")
        #expect(store.takePending().isEmpty)
        #expect(store.imageCount == 1)
    }

    /// A resize that lands on a NEW resolution is a different picture, and the
    /// old one has to go — the leak that would otherwise happen once per drag
    /// of a window edge. A resize that does not change the resolution is the
    /// test below this one, and costs no bytes at all.
    @Test("A resize to a new resolution deletes the old image before transmitting the new")
    func resizeReplacesRatherThanAccumulates() {
        let store = TerminalImageStore()
        _ = store.placeholderRows(
            token: "a", signature: signature("a"), columns: 4, rows: 2,
            pixels: { (pixels(64), .rgba, 8, 8) })
        _ = store.takePending()

        _ = store.placeholderRows(
            token: "a", signature: signature("a", pixelWidth: 16, pixelHeight: 16),
            columns: 8, rows: 4, pixels: { (pixels(256), .rgba, 16, 16) })
        let pending = store.takePending()
        #expect(pending.contains("a=d,d=I"), "the old bytes are freed")
        #expect(pending.contains("s=16,v=16"), "…and the new ones sent")
        #expect(store.imageCount == 1, "one view still holds exactly one image")
        // The delete comes first: transmitting over a live id is documented to
        // replace it, but only one terminal has been measured doing so.
        let deleteAt = pending.range(of: "a=d,d=I")?.lowerBound
        let transmitAt = pending.range(of: "a=t,")?.lowerBound
        #expect(deleteAt != nil && transmitAt != nil && deleteAt! < transmitAt!)
    }

    /// The point of splitting the signature: a box change that resamples to
    /// the SAME resolution is not a new picture, and must not cost bytes.
    ///
    /// This is the common case during a resize drag once the placement wants
    /// more pixels than the source has — past that point the transmitted size
    /// pins to the source and stops tracking the box, so step after step of
    /// the drag asks for pixels the terminal already holds.
    @Test("A box change at the same resolution re-places instead of re-transmitting")
    func boxChangeCostsAPlacementNotATransmission() {
        let store = TerminalImageStore()
        let first = store.placeholderRows(
            token: "a", signature: signature("a"), columns: 4, rows: 2,
            pixels: { (pixels(64), .rgba, 8, 8) })
        #expect(first?.count == 2)
        _ = store.takePending()

        var resampled = false
        let second = store.placeholderRows(
            token: "a", signature: signature("a"), columns: 8, rows: 4,
            pixels: {
                resampled = true
                return (pixels(64), .rgba, 8, 8)
            })

        #expect(!resampled, "the megabyte-producing closure must not even be called")
        let pending = store.takePending()
        #expect(pending.contains("a=p,U=1,q=2"), "the new box is declared")
        #expect(!pending.contains("a=t"), "…and nothing is transmitted")
        #expect(!pending.contains("a=d"), "…and nothing is deleted")
        #expect(store.imageCount == 1)

        // The cells are rebuilt for the new box, or the picture would go on
        // drawing at the old size whatever the placement said.
        #expect(second?.count == 4)
        #expect(second?.first?.strippedLength == 8)
    }

    /// An unchanged request still says nothing at all — the case that has to
    /// survive a middle branch being added above it.
    @Test("An unchanged request stays free")
    func unchangedRequestEmitsNothing() {
        let store = TerminalImageStore()
        _ = store.placeholderRows(
            token: "a", signature: signature("a"), columns: 4, rows: 2,
            pixels: { (pixels(64), .rgba, 8, 8) })
        _ = store.takePending()

        for _ in 0..<3 {
            _ = store.placeholderRows(
                token: "a", signature: signature("a"), columns: 4, rows: 2,
                pixels: {
                    Issue.record("resampled a picture nothing asked to change")
                    return (pixels(64), .rgba, 8, 8)
                })
        }
        #expect(store.takePending().isEmpty)
    }

    @Test("Releasing a view gives the terminal its memory back")
    func releaseDeletes() {
        let store = TerminalImageStore()
        _ = store.placeholderRows(
            token: "a", signature: signature("one", pixelWidth: 4, pixelHeight: 4),
            columns: 2, rows: 1, pixels: { (pixels(16), .rgba, 4, 4) })
        _ = store.takePending()

        store.release(token: "a")
        #expect(store.takePending().contains("a=d,d=I"))
        #expect(store.imageCount == 0)
        // Releasing something that was never there is not an error and sends
        // nothing — a disappear handler runs for views that never drew.
        store.release(token: "never")
        #expect(store.takePending().isEmpty)
    }

    @Test("Two views get two ids")
    func distinctViewsGetDistinctImages() {
        let store = TerminalImageStore()
        for token in ["a", "b"] {
            _ = store.placeholderRows(
                token: token, signature: signature(token, pixelWidth: 4, pixelHeight: 4),
                columns: 2, rows: 1, pixels: { (pixels(16), .rgba, 4, 4) })
        }
        let pending = store.takePending()
        #expect(pending.contains("i=1"))
        #expect(pending.contains("i=2"))
        #expect(store.imageCount == 2)

        store.releaseAll()
        #expect(store.imageCount == 0)
        let deletes = store.takePending().components(separatedBy: "a=d,d=I").count - 1
        #expect(deletes == 2)
    }

    /// The startup handshake borrows an id of its own, and the last thing it
    /// does is delete it. If the store ever handed the same one out, the first
    /// image an app drew would be deleted by the tail of the exchange that
    /// established it could be drawn at all.
    @Test("The store never hands out the id the handshake borrows")
    func storeAvoidsTheProbeID() {
        let store = TerminalImageStore()
        for index in 0..<8 {
            _ = store.placeholderRows(
                token: "t\(index)", signature: signature("s", pixelWidth: 1, pixelHeight: 1),
                columns: 1, rows: 1, pixels: { ([0, 0, 0, 255], .rgba, 1, 1) })
        }
        let pending = store.takePending()
        #expect(!pending.contains("i=\(TerminalGraphicsQuery.probeID)"))
    }

    /// There is no combining mark for the 298th column, so an image that would
    /// need one is not drawn this way at all — the caller falls back to glyphs
    /// rather than drawing a truncated picture.
    @Test("A store transmits deflated exactly when the terminal said it would take it")
    func transmitsDeflatedOnlyWhereSupported() throws {
        try #require(SystemZlib.isAvailable, "no libz here; there is no compressed path to take")
        let bytes = [UInt8](repeating: 0x40, count: 16 * 16 * 4)
        func pending(compression: Bool) -> String {
            KittyGraphics.withSupport(true, compression: compression) {
                let store = TerminalImageStore()
                _ = store.placeholderRows(
                    token: "v", signature: signature("a", pixelWidth: 16, pixelHeight: 16),
                    columns: 2, rows: 1, pixels: { (bytes, .rgba, 16, 16) })
                return store.takePending()
            }
        }
        let raw = pending(compression: false)
        let deflated = pending(compression: true)
        #expect(!raw.contains("o=z"))
        #expect(deflated.contains("o=z"))
        #expect(deflated.count < raw.count / 4, "\(deflated.count) against \(raw.count)")
    }

    // MARK: - One picture, many views

    @Test("Two views asking for the same picture in the same box share one image")
    func identicalRequestsShareOneImage() {
        let store = TerminalImageStore()
        var built = 0
        let first = store.placeholderRows(
            token: "a", signature: signature("shared"), columns: 4, rows: 2,
            pixels: {
                built += 1
                return (pixels(64), .rgba, 8, 8)
            })
        let second = store.placeholderRows(
            token: "b", signature: signature("shared"), columns: 4, rows: 2,
            pixels: {
                built += 1
                return (pixels(64), .rgba, 8, 8)
            })
        #expect(built == 1, "one resample, one transmission")
        #expect(first == second, "the same cells, naming the same id")
        #expect(store.imageCount == 1)
        let pending = store.takePending()
        #expect(pending.components(separatedBy: "a=t,").count - 1 == 1)
        // The first to leave frees nothing; the last frees the image.
        store.release(token: "a")
        #expect(store.takePending().isEmpty, "b is still drawing it")
        #expect(store.imageCount == 1)
        store.release(token: "b")
        #expect(store.takePending().contains("a=d,d=I"))
        #expect(store.imageCount == 0)
    }

    @Test("A shared picture asked for in a new box gets its own image rather than moving everyone's")
    func sharedImageIsNotReplacedUnderOthers() {
        let store = TerminalImageStore()
        for token in ["a", "b"] {
            _ = store.placeholderRows(
                token: token, signature: signature("shared"), columns: 4, rows: 2,
                pixels: { (pixels(64), .rgba, 8, 8) })
        }
        _ = store.takePending()
        let moved = store.placeholderRows(
            token: "b", signature: signature("shared"), columns: 8, rows: 4,
            pixels: { (pixels(64), .rgba, 8, 8) })
        let pending = store.takePending()
        #expect(moved?.count == 4)
        #expect(pending.contains("a=t,"), "a second image, transmitted")
        #expect(!pending.contains("a=d"), "a still draws the first; nothing is deleted")
        #expect(store.imageCount == 2)
        // And b's old holding is gone: releasing a now frees the first image.
        store.release(token: "a")
        #expect(store.takePending().contains("a=d,d=I"))
        #expect(store.imageCount == 1)
    }

    @Test("A view that changes picture leaves a shared one for the others and frees an unshared one")
    func changingPictureFreesOnlyWhatNobodyElseHolds() {
        let store = TerminalImageStore()
        for token in ["a", "b"] {
            _ = store.placeholderRows(
                token: token, signature: signature("shared"), columns: 4, rows: 2,
                pixels: { (pixels(64), .rgba, 8, 8) })
        }
        _ = store.takePending()
        _ = store.placeholderRows(
            token: "b", signature: signature("other"), columns: 4, rows: 2,
            pixels: { (pixels(64), .rgba, 8, 8) })
        var pending = store.takePending()
        #expect(!pending.contains("a=d"), "the shared picture stays for a")
        #expect(pending.contains("a=t,"))
        #expect(store.imageCount == 2)
        // Now b is alone on "other": changing again frees it, on the same id.
        _ = store.placeholderRows(
            token: "b", signature: signature("third"), columns: 4, rows: 2,
            pixels: { (pixels(64), .rgba, 8, 8) })
        pending = store.takePending()
        #expect(pending.contains("a=d,d=I,q=2,i=2"), "other is freed…")
        #expect(pending.contains("i=2,"), "…and its id reused for third")
        #expect(store.imageCount == 2)
    }

    // MARK: - Finding a picture among many

    /// A view alone on its image that asks for a new box gets a placement, and
    /// the image is then in THAT box: a view asking for the picture there
    /// shares it, and one asking for the old box gets an image of its own.
    @Test("A picture re-placed in a new box is shared in that box, and not in the old one")
    func replacedImageIsSharedInItsNewBox() {
        let store = TerminalImageStore()
        var built = 0
        func draw(_ token: String, columns: Int, rows: Int) -> [String]? {
            store.placeholderRows(
                token: token, signature: signature("s"), columns: columns, rows: rows,
                pixels: {
                    built += 1
                    return (pixels(64), .rgba, 8, 8)
                })
        }
        let first = draw("a", columns: 4, rows: 2)
        let moved = draw("a", columns: 8, rows: 4)
        #expect(built == 1, "the move was a placement")
        _ = store.takePending()

        let shared = draw("b", columns: 8, rows: 4)
        #expect(built == 1, "b shares a's image in its new box")
        #expect(shared == moved)
        #expect(store.takePending().isEmpty)
        #expect(store.imageCount == 1)

        let fresh = draw("c", columns: 4, rows: 2)
        #expect(built == 2, "nothing is drawn in the old box any more, so c transmits")
        #expect(fresh != first, "c's cells name a new id")
        #expect(store.imageCount == 2)
    }

    /// Two images can hold one picture in one box. b transmits the picture in a
    /// box a is not in, then a, alone on its own image, moves to b's box with a
    /// placement. A view that arrives after that shares the OLDER image, a's.
    @Test("Of two images of one picture in one box, a view that arrives later shares the older")
    func duplicateImagesShareTheOlder() {
        let store = TerminalImageStore()
        func draw(_ token: String, columns: Int, rows: Int) -> [String]? {
            store.placeholderRows(
                token: token, signature: signature("s"), columns: columns, rows: rows,
                pixels: { (pixels(64), .rgba, 8, 8) })
        }
        _ = draw("a", columns: 4, rows: 2)
        let newer = draw("b", columns: 8, rows: 4)
        let older = draw("a", columns: 8, rows: 4)
        #expect(store.imageCount == 2)
        #expect(older != newer, "two images, two ids")
        _ = store.takePending()

        #expect(draw("c", columns: 8, rows: 4) == older)
        #expect(store.takePending().isEmpty, "shared, not transmitted")
        #expect(store.imageCount == 2)
    }

    /// Nothing in the terminal cares what order a shutdown's deletes come in,
    /// but the bytes should be the same on every run. So they come in the order
    /// the images were put in: a re-placed image keeps its place, and an image
    /// transmitted after one was freed goes last.
    @Test("Releasing everything deletes each image once, in the order they were put in")
    func releaseAllDeletesInOrderOfArrival() {
        let store = TerminalImageStore()
        func draw(_ token: String, _ label: String, columns: Int = 4, rows: Int = 2) {
            _ = store.placeholderRows(
                token: token, signature: signature(label), columns: columns, rows: rows,
                pixels: { (pixels(64), .rgba, 8, 8) })
        }
        for index in 0..<10 { draw("t\(index)", "s\(index)") }
        draw("t0", "s0", columns: 8, rows: 4)
        store.release(token: "t3")
        draw("t10", "s10")
        _ = store.takePending()

        store.releaseAll()
        let deleted = store.takePending().components(separatedBy: "a=d,d=I,q=2,i=").dropFirst()
            .map { Int($0.prefix(while: \.isNumber)) }
        #expect(deleted == [1, 2, 3, 5, 6, 7, 8, 9, 10, 11])
        #expect(store.imageCount == 0)
    }

    @Test("An extent the protocol cannot address is declined, not truncated")
    func oversizeRequestsAreDeclined() {
        let store = TerminalImageStore()
        var built = false
        let rows = store.placeholderRows(
            token: "a", signature: signature("huge", pixelWidth: 4, pixelHeight: 4),
            columns: KittyGraphics.maximumCellExtent + 1, rows: 1,
            pixels: {
                built = true
                return (pixels(16), .rgba, 4, 4)
            })
        #expect(rows == nil)
        #expect(!built, "and nothing was resampled for it")
        #expect(store.takePending().isEmpty)
        #expect(store.imageCount == 0)
    }
}
