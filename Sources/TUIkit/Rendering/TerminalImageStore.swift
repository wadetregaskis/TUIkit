//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalImageStore.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - What decides whether a picture has changed

/// Everything about a request that, if it changed, means the terminal is
/// holding the wrong picture.
///
/// A typed value rather than a formatted string: the fields are already
/// `Equatable`, and comparing them directly cannot go stale the way a
/// hand-written description does when somebody adds a knob and forgets to put
/// it in the format. Getting this wrong is invisible in the good direction and
/// unmissable in the bad one — a missing field means turning a knob changes
/// nothing on screen, because the store believes it already sent this picture.
struct TerminalImageSignature: Equatable {
    /// Which picture, and at what decoded size — a source change resets the
    /// loading phase, so within one view these cannot disagree.
    var source: ImageSource
    var rawWidth: Int
    var rawHeight: Int

    /// The resolution the picture is transmitted AT — which is what decides
    /// the bytes, and is not the same question as where it goes.
    ///
    /// This used to be the cell box (`columns`, `rows`, `cellWidth`,
    /// `cellHeight`), and that made a resize a new picture: every step of a
    /// drag ran delete + transmit + place over bytes the terminal already
    /// held. The four are not dropped so much as *resolved* — `pixelWidth` and
    /// `pixelHeight` are computed from all four (`_ImageCore`: box times cell,
    /// clamped so the transmission never exceeds the source), so keying on
    /// them is strictly more precise rather than less. Two boxes that resample
    /// to the same resolution ARE the same picture, and the clamped regime
    /// makes that the common case: past the point where the placement wants
    /// more pixels than the source has, the transmitted size stops tracking
    /// the box on the binding axis and pins to the source.
    ///
    /// Where the picture GOES is the placement, and a placement is twenty
    /// bytes — see ``TerminalImageStore/placeholderRows(token:signature:columns:rows:pixels:)``.
    var pixelWidth: Int
    var pixelHeight: Int

    /// The settings `ASCIIConverter.recoloured(_:width:height:)` consults —
    /// and only those. A charset or a supersampling factor changes which
    /// GLYPH would be chosen, and there are no glyphs here, so re-transmitting
    /// megabytes for one would be work with no effect.
    var colorMode: ASCIIColorMode
    var toneCurve: ASCIIToneCurve?
    var edgeContrast: Double
    var dithering: DitheringMode

    /// The two colours ``ASCIIColorMode/mono`` is painted in, which for pixels
    /// are baked into the picture rather than stated around it — so a theme
    /// change makes a mono image a genuinely different picture, and has to
    /// re-transmit. Ignored by every other mode, and carried anyway: a field
    /// that is sometimes irrelevant costs a comparison, and a field that is
    /// sometimes MISSING costs a picture that will not update.
    var monoInk: RGBA
    var monoPaper: RGBA
}

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
/// - **What do I draw?** ``placeholderRows(token:signature:columns:rows:pixels:)``
///   returns the cells — transmitting first if this is a picture the terminal
///   does not have, and sending a placement alone if it is one it does at a
///   size it was not told about.
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
/// `@unchecked Sendable`, exactly as `LifecycleManager` is, and for the same
/// reason: it is reached from `Renderable.renderToBuffer`, which is not
/// actor-isolated, and from the run loop, which is — but both run on the run
/// loop's own thread, one render pass at a time. There is no concurrency here
/// to check; there is a compiler that cannot see that.
final class TerminalImageStore: @unchecked Sendable {

    /// One image in the terminal, and the cells that draw it.
    private struct Entry {
        var id: KittyGraphics.ImageID
        var signature: TerminalImageSignature
        /// The cell box currently declared to the terminal, so a box-only
        /// change can be spotted and answered with a placement alone.
        var columns: Int
        var rows: Int
        /// The placeholder cells, which are a function of the id and the box.
        var cells: [String]
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
    ///   - signature: Everything that decides the picture's content — and
    ///     deliberately nothing about where it goes, so a move or a resize
    ///     that resamples to the same resolution costs a placement rather
    ///     than a re-transmission.
    ///   - columns: Width of the placement, in cells.
    ///   - rows: Height of the placement, in cells.
    ///   - pixels: 8-bit pixel bytes and their format, row-major, at the
    ///     signature's `pixelWidth` × `pixelHeight`. **Only evaluated when the
    ///     terminal does not already hold this picture** — it is a resample of
    ///     the decoded image and megabytes of it, and the common case by a
    ///     wide margin is that nothing has changed since last frame.
    /// - Returns: the rows, or `nil` for a request the protocol cannot express
    ///   — at which point the caller draws the picture out of glyphs, as it
    ///   always has.
    func placeholderRows(
        token: String, signature: TerminalImageSignature,
        columns: Int, rows: Int,
        pixels: () -> (bytes: [UInt8], format: KittyGraphics.PixelFormat)
    ) -> [String]? {
        let pixelWidth = signature.pixelWidth
        let pixelHeight = signature.pixelHeight
        guard columns > 0, rows > 0, pixelWidth > 0, pixelHeight > 0,
            columns <= KittyGraphics.maximumCellExtent,
            rows <= KittyGraphics.maximumCellExtent
        else { return nil }

        // Three cases, not two, and the middle one is the point of splitting
        // the signature. A picture the terminal already holds, asked for in a
        // DIFFERENT box, needs no bytes: an `a=p` replaces the placement for
        // that id, and the picture is refit to the new rectangle by the
        // terminal. Without this case every step of a resize drag ran
        // delete + transmit + place — megabytes, per step, to end up with the
        // pixels already in the store.
        if let existing = entries[token], existing.signature == signature {
            if existing.columns == columns, existing.rows == rows { return existing.cells }
            let cells = KittyGraphics.placeholderRows(id: existing.id, columns: columns, rows: rows)
            guard !cells.isEmpty else { return nil }
            pending += KittyGraphics.placement(id: existing.id, columns: columns, rows: rows)
            entries[token] = Entry(
                id: existing.id, signature: signature,
                columns: columns, rows: rows, cells: cells)
            return cells
        }

        let id = entries[token]?.id ?? claimID()
        let cells = KittyGraphics.placeholderRows(id: id, columns: columns, rows: rows)
        guard !cells.isEmpty else { return nil }

        let payload = pixels()
        let transmit = KittyGraphics.transmit(
            pixels: payload.bytes, format: payload.format,
            width: pixelWidth, height: pixelHeight, id: id)
        guard !transmit.isEmpty else { return nil }

        // Delete first, on the same id. Re-transmitting over a live id is
        // documented to replace it, but "documented to replace it" is a claim
        // about five terminals of which one has been measured, and the cost of
        // being wrong is an image store that grows every time a window is
        // resized. Twenty bytes buys not having to find out.
        if entries[token] != nil { pending += KittyGraphics.delete(id: id) }
        pending += transmit
        pending += KittyGraphics.placement(id: id, columns: columns, rows: rows)
        entries[token] = Entry(
            id: id, signature: signature, columns: columns, rows: rows, cells: cells)
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
