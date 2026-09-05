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

// MARK: - Any signature at all

/// A signature the store can compare without knowing what it signs.
///
/// A picture's signature (``TerminalImageSignature``) and a gradient's
/// (`GradientImageSignature`) have nothing in common but the one thing the
/// store needs — equality — so the store holds this and asks that. Erasing
/// the type here, rather than making the store generic or the signatures an
/// enum, keeps each caller's signature its own ordinary struct: every field
/// that decides a picture is still a typed, `Equatable` field on a type that
/// says what it is for.
struct AnyImageSignature: Equatable {
    private let value: Any
    private let equals: (Any) -> Bool

    init<S: Equatable>(_ value: S) {
        self.value = value
        self.equals = { ($0 as? S) == value }
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.equals(rhs.value) }
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
/// ## One picture, many views
///
/// Two views asking for the same picture in the same box get the same image:
/// the store transmits once and hands both the same cells, and the terminal
/// keeps the bytes until the LAST of them lets go. A list of one icon, or a
/// column of progress bars sharing one gradient, costs one transmission
/// rather than one per row. Sharing is by content — a signature and a cell
/// box that compare equal — so it never depends on which view asked first,
/// and a view that moves on to a different picture leaves the shared one for
/// the others rather than deleting it under them.
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

    /// One image in the terminal, the cells that draw it, and who is drawing
    /// them.
    private struct Image {
        let id: KittyGraphics.ImageID
        let signature: AnyImageSignature
        /// The cell box declared to the terminal, so a box-only change can be
        /// spotted and answered with a placement alone.
        var columns: Int
        var rows: Int
        /// The placeholder cells, which are a function of the id and the box.
        var cells: [String]
        /// The tokens currently drawing this image. Empty means nobody, and
        /// nobody means deleted — an image is never kept on the chance that
        /// someone comes back for it.
        var holders: Set<String>
    }

    private var images: [Image] = []
    /// Which image each token is drawing, by position in `images`.
    private var entries: [String: KittyGraphics.ImageID] = [:]
    private var pending = ""
    private var nextID: KittyGraphics.ImageID = 1

    /// How many images this app currently has in the terminal. For tests and
    /// diagnostics — a number that only ever grows is the leak this type
    /// exists to prevent.
    var imageCount: Int { images.count }

    // MARK: - Drawing

    /// The placeholder rows for `token`'s image, transmitting it first if the
    /// terminal does not already have exactly this picture at exactly this
    /// size.
    ///
    /// - Parameters:
    ///   - token: The owning view's identity. One image per token; a second
    ///     call with a different `signature` moves the token to the new
    ///     picture and frees the old one if nobody else is drawing it, which
    ///     is what stops a resize leaking an image a frame.
    ///   - signature: Everything that decides the picture's content — and
    ///     deliberately nothing about where it goes, so a move or a resize
    ///     that resamples to the same resolution costs a placement rather
    ///     than a re-transmission. Two tokens whose signatures compare equal
    ///     share one image.
    ///   - columns: Width of the placement, in cells.
    ///   - rows: Height of the placement, in cells.
    ///   - pixels: 8-bit pixel bytes and their format, row-major, at the
    ///     resolution the signature names. **Only evaluated when the terminal
    ///     does not already hold this picture** — it is a resample of the
    ///     decoded image and megabytes of it, and the common case by a wide
    ///     margin is that nothing has changed since last frame.
    /// - Returns: the rows, or `nil` for a request the protocol cannot express
    ///   — at which point the caller draws the picture out of glyphs, as it
    ///   always has.
    func placeholderRows<Signature: Equatable>(
        token: String, signature: Signature,
        columns: Int, rows: Int,
        pixels: () -> (bytes: [UInt8], format: KittyGraphics.PixelFormat, width: Int, height: Int)
    ) -> [String]? {
        guard columns > 0, rows > 0,
            columns <= KittyGraphics.maximumCellExtent,
            rows <= KittyGraphics.maximumCellExtent
        else { return nil }
        let wanted = AnyImageSignature(signature)

        // The token's own image, if it still is this picture.
        if let id = entries[token], let index = images.firstIndex(where: { $0.id == id }),
            images[index].signature == wanted
        {
            if images[index].columns == columns, images[index].rows == rows {
                return images[index].cells
            }
            // The same picture in a DIFFERENT box. Alone on the image, this
            // needs no bytes: an `a=p` replaces the placement for that id and
            // the terminal refits the picture to the new rectangle. Without
            // this case every step of a resize drag ran delete + transmit +
            // place — megabytes, per step, to end up with the pixels already
            // in the store. Shared, the box belongs to the others too, so the
            // token moves on to an image of its own instead.
            if images[index].holders == [token] {
                let cells = KittyGraphics.placeholderRows(id: id, columns: columns, rows: rows)
                guard !cells.isEmpty else { return nil }
                pending += KittyGraphics.placement(id: id, columns: columns, rows: rows)
                images[index].columns = columns
                images[index].rows = rows
                images[index].cells = cells
                return cells
            }
        }

        // Somebody else's image of exactly this picture in exactly this box:
        // share it, and let go of whatever this token was drawing before.
        if let index = images.firstIndex(where: {
            $0.signature == wanted && $0.columns == columns && $0.rows == rows
        }) {
            let id = images[index].id
            if entries[token] != id { release(token: token) }
            // `release` may have removed an image BEFORE this one, so find it
            // again rather than trusting the index.
            guard let found = images.firstIndex(where: { $0.id == id }) else { return nil }
            images[found].holders.insert(token)
            entries[token] = id
            return images[found].cells
        }

        // A picture the terminal does not have. The token's previous image is
        // freed first if this was its only holder — reusing the id, so a view
        // that changes picture every frame does not walk the id space.
        var reusableID: KittyGraphics.ImageID?
        if let previous = entries[token], let index = images.firstIndex(where: { $0.id == previous }) {
            images[index].holders.remove(token)
            if images[index].holders.isEmpty {
                // Delete first, on the same id. Re-transmitting over a live id
                // is documented to replace it, but "documented to replace it"
                // is a claim about five terminals of which one has been
                // measured, and the cost of being wrong is an image store that
                // grows every time a window is resized. Twenty bytes buys not
                // having to find out.
                pending += KittyGraphics.delete(id: previous)
                images.remove(at: index)
                reusableID = previous
            }
            entries.removeValue(forKey: token)
        }
        let id = reusableID ?? claimID()
        let cells = KittyGraphics.placeholderRows(id: id, columns: columns, rows: rows)
        guard !cells.isEmpty else { return nil }

        let payload = pixels()
        // Deflated where the terminal said it would take it — a photograph
        // gains a little, a gradient rendered as pixels gains an order of
        // magnitude — and raw everywhere else. See ``KittyGraphics/isCompressionSupported``.
        let transmit = KittyGraphics.transmit(
            pixels: payload.bytes, format: payload.format,
            width: payload.width, height: payload.height, id: id,
            compressed: KittyGraphics.isCompressionSupported)
        guard !transmit.isEmpty else { return nil }
        pending += transmit
        pending += KittyGraphics.placement(id: id, columns: columns, rows: rows)
        images.append(
            Image(id: id, signature: wanted, columns: columns, rows: rows, cells: cells, holders: [token]))
        entries[token] = id
        return cells
    }

    // MARK: - Owning

    /// Gives back `token`'s image — to the terminal, if nobody else is
    /// drawing it.
    ///
    /// Called from the view's disappear handler, which is the only moment
    /// anything knows the picture is not coming back.
    func release(token: String) {
        guard let id = entries.removeValue(forKey: token),
            let index = images.firstIndex(where: { $0.id == id })
        else { return }
        images[index].holders.remove(token)
        guard images[index].holders.isEmpty else { return }
        pending += KittyGraphics.delete(id: id)
        images.remove(at: index)
    }

    /// Gives back every image, for a shutdown that wants to leave the terminal
    /// as it found it.
    func releaseAll() {
        for image in images { pending += KittyGraphics.delete(id: image.id) }
        images.removeAll()
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
    /// Counts up and wraps, skipping ids in use and the two the startup
    /// handshake borrows (``TerminalGraphicsQuery/probeID`` and
    /// ``TerminalGraphicsQuery/compressionProbeID``, the top of the range).
    /// Sixteen million ids and a handful of images means the wrap is
    /// unreachable in practice; it is handled because "unreachable in
    /// practice" is how an id gets reused underneath a live picture.
    private func claimID() -> KittyGraphics.ImageID {
        let live = Set(images.map(\.id))
        for _ in 0..<KittyGraphics.maximumImageID {
            let candidate = nextID
            nextID = candidate >= KittyGraphics.maximumImageID - 2 ? 1 : candidate + 1
            if !live.contains(candidate) { return candidate }
        }
        return 1
    }
}
