//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalImageStore.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - The images this app has put in the terminal

/// Owns every image TUIkit has transmitted to the terminal, and is the only
/// thing that deletes one.
///
/// A Kitty image is **retained**: it is transmitted once, given an id, and
/// then drawn as many times as you like by writing cells that name that id.
/// That is what makes the feature affordable — a picture costs its bytes once
/// rather than once a frame — and it is also the catch, because those bytes
/// now live in the terminal and nothing in the terminal will ever free them.
/// A view that renders an image and goes away has leaked until this store
/// deletes it.
///
/// So there is exactly one owner, keyed by the view's identity path, and it
/// answers three questions:
///
/// - **What do I draw?** ``placeholderRows(token:signature:columns:rows:pixelWidth:pixelHeight:pixels:)``
///   returns the cells, transmitting first if this is a new image or a new
///   size.
/// - **What do I still owe the terminal?** ``takePending()`` hands back the
///   escapes that have to reach it before the frame those cells are in.
/// - **What can go?** ``release(token:)``, from the view's disappear handler.
///
/// ## Why the escapes are queued rather than written
///
/// They are produced during the render pass, by a `Renderable` that has a
/// `RenderContext` and no terminal — and must be *written* before the frame
/// that refers to them, which is a different moment. Queuing here and
/// draining at `beginFrame` is the seam. It also means a measure pass that
/// renders (a Card measuring its container, a Table probing a multi-line
/// cell) transmits nothing, because it never asks.
/// ## Isolation
///
/// `@unchecked Sendable`, exactly as ``LifecycleManager`` is, and for the same
/// reason: it is reached from `Renderable.renderToBuffer`, which is not
/// actor-isolated, and from the run loop, which is — but both run on the run
/// loop's own thread, one render pass at a time. There is no concurrency here
/// to check; there is a compiler that cannot see that.
final class TerminalImageStore: @unchecked Sendable {

    /// One image in the terminal, and the cells that draw it.
    private struct Entry {
        var id: KittyGraphics.ImageID
        /// Everything about the request that, if changed, means a different
        /// picture: the source, the decoded size, the cell box, and the cell's
        /// pixel size. Equal signature, same bytes already in the terminal.
        var signature: String
        var rows: [String]
    }

    private var entries: [String: Entry] = [:]
    private var pending = ""
    private var nextID: KittyGraphics.ImageID = 1

    /// How many images this app currently has in the terminal. For tests and
    /// diagnostics — a number that only ever grows is the leak this type
    /// exists to prevent.
    var imageCount: Int { entries.count }

    // MARK: - Drawing

    /// The placeholder rows for `token`'s image, transmitting it first if the
    /// terminal does not already have exactly this picture at exactly this
    /// size.
    ///
    /// - Parameters:
    ///   - token: The owning view's identity. One image per token; a second
    ///     call with a different `signature` replaces the first rather than
    ///     adding to it, which is what stops a resize leaking an image a
    ///     frame.
    ///   - signature: Everything that decides the picture's content. Compared,
    ///     not parsed.
    ///   - columns: Width of the placement, in cells.
    ///   - rows: Height of the placement, in cells.
    ///   - pixelWidth: Width of `pixels`.
    ///   - pixelHeight: Height of `pixels`.
    ///   - pixels: 8-bit RGBA, row-major. **Only evaluated on a miss** — it is
    ///     a resample of the decoded image and megabytes of it, and the common
    ///     case by a wide margin is that nothing has changed since last frame.
    /// - Returns: the rows, or `nil` for a request the protocol cannot express
    ///   — at which point the caller draws the picture out of glyphs, as it
    ///   always has.
    func placeholderRows(
        token: String, signature: String,
        columns: Int, rows: Int,
        pixelWidth: Int, pixelHeight: Int,
        pixels: () -> [UInt8]
    ) -> [String]? {
        guard columns > 0, rows > 0, pixelWidth > 0, pixelHeight > 0,
            columns <= KittyGraphics.maximumCellExtent,
            rows <= KittyGraphics.maximumCellExtent
        else { return nil }

        if let existing = entries[token], existing.signature == signature {
            return existing.rows
        }

        let id = entries[token]?.id ?? claimID()
        let cells = KittyGraphics.placeholderRows(id: id, columns: columns, rows: rows)
        guard !cells.isEmpty else { return nil }

        let payload = pixels()
        let transmit = KittyGraphics.transmit(
            rgba: payload, width: pixelWidth, height: pixelHeight, id: id)
        guard !transmit.isEmpty else { return nil }

        // Delete first, on the same id. Re-transmitting over a live id is
        // documented to replace it, but "documented to replace it" is a claim
        // about five terminals of which one has been measured, and the cost of
        // being wrong is an image store that grows every time a window is
        // resized. Twenty bytes buys not having to find out.
        if entries[token] != nil { pending += KittyGraphics.delete(id: id) }
        pending += transmit
        pending += KittyGraphics.placement(id: id, columns: columns, rows: rows)
        entries[token] = Entry(id: id, signature: signature, rows: cells)
        return cells
    }

    // MARK: - Owning

    /// Gives back `token`'s image, if it has one.
    ///
    /// Called from the view's disappear handler, which is the only moment
    /// anything knows the picture is not coming back.
    func release(token: String) {
        guard let entry = entries.removeValue(forKey: token) else { return }
        pending += KittyGraphics.delete(id: entry.id)
    }

    /// Gives back every image, for a shutdown that wants to leave the terminal
    /// as it found it.
    func releaseAll() {
        for entry in entries.values { pending += KittyGraphics.delete(id: entry.id) }
        entries.removeAll()
    }

    /// The escapes owed to the terminal, and clears them.
    ///
    /// Written at `beginFrame`, before the frame's cells: a placeholder naming
    /// an image the terminal has not been given yet draws nothing.
    func takePending() -> String {
        defer { pending = "" }
        return pending
    }

    // MARK: - Ids

    /// The next id nothing is using.
    ///
    /// Counts up and wraps, skipping ids in use and the one the startup
    /// handshake borrows (``TerminalGraphicsQuery/probeID``, the top of the
    /// range). Sixteen million ids and a handful of images means the wrap is
    /// unreachable in practice; it is handled because "unreachable in
    /// practice" is how an id gets reused underneath a live picture.
    private func claimID() -> KittyGraphics.ImageID {
        let live = Set(entries.values.map(\.id))
        for _ in 0..<KittyGraphics.maximumImageID {
            let candidate = nextID
            nextID = candidate >= KittyGraphics.maximumImageID - 1 ? 1 : candidate + 1
            if !live.contains(candidate) { return candidate }
        }
        return 1
    }
}
