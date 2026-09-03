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
            monoInk: RGBA(r: 255, g: 255, b: 255), monoPaper: RGBA(r: 0, g: 0, b: 0))
    }

    @Test("A first draw transmits the image and places it")
    func firstDrawTransmitsAndPlaces() {
        let store = TerminalImageStore()
        let rows = store.placeholderRows(
            token: "a", signature: signature("one"), columns: 4, rows: 2,
            pixels: { (pixels(64), .rgba) })
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
                    return (pixels(64), .rgba)
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
            pixels: { (pixels(64), .rgba) })
        _ = store.takePending()

        _ = store.placeholderRows(
            token: "a", signature: signature("a", pixelWidth: 16, pixelHeight: 16),
            columns: 8, rows: 4, pixels: { (pixels(256), .rgba) })
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
            pixels: { (pixels(64), .rgba) })
        #expect(first?.count == 2)
        _ = store.takePending()

        var resampled = false
        let second = store.placeholderRows(
            token: "a", signature: signature("a"), columns: 8, rows: 4,
            pixels: {
                resampled = true
                return (pixels(64), .rgba)
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
            pixels: { (pixels(64), .rgba) })
        _ = store.takePending()

        for _ in 0..<3 {
            _ = store.placeholderRows(
                token: "a", signature: signature("a"), columns: 4, rows: 2,
                pixels: {
                    Issue.record("resampled a picture nothing asked to change")
                    return (pixels(64), .rgba)
                })
        }
        #expect(store.takePending().isEmpty)
    }

    @Test("Releasing a view gives the terminal its memory back")
    func releaseDeletes() {
        let store = TerminalImageStore()
        _ = store.placeholderRows(
            token: "a", signature: signature("one", pixelWidth: 4, pixelHeight: 4),
            columns: 2, rows: 1, pixels: { (pixels(16), .rgba) })
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
                columns: 2, rows: 1, pixels: { (pixels(16), .rgba) })
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
                columns: 1, rows: 1, pixels: { ([0, 0, 0, 255], .rgba) })
        }
        let pending = store.takePending()
        #expect(!pending.contains("i=\(TerminalGraphicsQuery.probeID)"))
    }

    /// There is no combining mark for the 298th column, so an image that would
    /// need one is not drawn this way at all — the caller falls back to glyphs
    /// rather than drawing a truncated picture.
    @Test("An extent the protocol cannot address is declined, not truncated")
    func oversizeRequestsAreDeclined() {
        let store = TerminalImageStore()
        var built = false
        let rows = store.placeholderRows(
            token: "a", signature: signature("huge", pixelWidth: 4, pixelHeight: 4),
            columns: KittyGraphics.maximumCellExtent + 1, rows: 1,
            pixels: {
                built = true
                return (pixels(16), .rgba)
            })
        #expect(rows == nil)
        #expect(!built, "and nothing was resampled for it")
        #expect(store.takePending().isEmpty)
        #expect(store.imageCount == 0)
    }
}
