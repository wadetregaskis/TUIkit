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

    @Test("A first draw transmits the image and places it")
    func firstDrawTransmitsAndPlaces() {
        let store = TerminalImageStore()
        let rows = store.placeholderRows(
            token: "a", signature: "one", columns: 4, rows: 2,
            pixelWidth: 8, pixelHeight: 8, pixels: { pixels(64) })
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
                token: "a", signature: "one", columns: 4, rows: 2,
                pixelWidth: 8, pixelHeight: 8,
                pixels: {
                    built += 1
                    return pixels(64)
                })
        }
        _ = store.takePending()
        #expect(built == 1, "the resample ran once, not five times")
        #expect(store.takePending().isEmpty)
        #expect(store.imageCount == 1)
    }

    /// A resize is a different picture, and the old one has to go — this is
    /// the leak that would otherwise happen once per drag of a window edge.
    @Test("A resize deletes the old image before transmitting the new")
    func resizeReplacesRatherThanAccumulates() {
        let store = TerminalImageStore()
        _ = store.placeholderRows(
            token: "a", signature: "4x2", columns: 4, rows: 2,
            pixelWidth: 8, pixelHeight: 8, pixels: { pixels(64) })
        _ = store.takePending()

        _ = store.placeholderRows(
            token: "a", signature: "8x4", columns: 8, rows: 4,
            pixelWidth: 16, pixelHeight: 16, pixels: { pixels(256) })
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

    @Test("Releasing a view gives the terminal its memory back")
    func releaseDeletes() {
        let store = TerminalImageStore()
        _ = store.placeholderRows(
            token: "a", signature: "one", columns: 2, rows: 1,
            pixelWidth: 4, pixelHeight: 4, pixels: { pixels(16) })
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
                token: token, signature: token, columns: 2, rows: 1,
                pixelWidth: 4, pixelHeight: 4, pixels: { pixels(16) })
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
                token: "t\(index)", signature: "s", columns: 1, rows: 1,
                pixelWidth: 1, pixelHeight: 1, pixels: { [0, 0, 0, 255] })
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
            token: "a", signature: "huge",
            columns: KittyGraphics.maximumCellExtent + 1, rows: 1,
            pixelWidth: 4, pixelHeight: 4,
            pixels: {
                built = true
                return pixels(16)
            })
        #expect(rows == nil)
        #expect(!built, "and nothing was resampled for it")
        #expect(store.takePending().isEmpty)
        #expect(store.imageCount == 0)
    }
}
