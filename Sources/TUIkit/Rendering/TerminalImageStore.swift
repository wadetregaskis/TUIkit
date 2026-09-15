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

    /// The two colours ``ASCIIColorMode/mono`` is painted in (the view's
    /// `.foregroundStyle` and `.backgroundStyle`, the palette's where unstated),
    /// which for pixels are baked into the picture rather than stated around it.
    /// So a style or theme change makes a mono image a genuinely different
    /// picture, and has to re-transmit.
    ///
    /// Ignored by every other mode, so there they are PINNED to
    /// `recoloured`'s defaults (white ink, black paper) rather than omitted:
    /// `_ImageCore` makes the same test on the same requested mode that
    /// `recoloured` makes before painting them. A field that is sometimes
    /// MISSING costs a picture that will not update. A field that carries a
    /// value nothing reads costs a re-transmission for nothing: read from the
    /// palette whatever the mode, these re-sent every true-colour picture on a
    /// theme change.
    ///
    /// ## A changing ink is followed, frame by frame
    ///
    /// A mono picture re-sends whenever its ink or paper changes in 8-bit RGB,
    /// and that includes every frame of a `.foregroundStyle` fading under
    /// `withAnimation`. Each alternative is wrong somewhere worse:
    ///
    /// - Snapping to the end colour needs the animation's target, and that
    ///   belongs to the style view's store entry. The image sees only the
    ///   interpolated paint.
    /// - Holding the old picture while the ink moves cannot tell the last frame
    ///   of a fade from any other, and there is no frame after the last to send
    ///   the settled colour on.
    /// - Quantising the ink draws the settled picture in a colour nobody stated.
    ///
    /// The cost is bounded. Only `.mono` pays it (above). Only an RGB change
    /// counts: alpha is dropped, so a fade that moves only alpha is the same
    /// picture. A fade costs one re-send per frame for its length; a hover, a
    /// menu highlight or a disabled dim costs one. And the store frees a token's
    /// previous image before transmitting its next, so nothing accumulates in
    /// the terminal.
    ///
    /// **A focus breath is not followed.** A `.link` button's breath renders its
    /// label once per frame in ONE pass, each time under that frame's
    /// `.foregroundStyle` and at one identity
    /// (`BreathingLabel.draw(ends:cycle:indicating:isMeasuring:render:)`), and
    /// the runs that replay those frames repeat one image id. Followed, a mono
    /// picture there was sent once per frame on every pass that re-rendered the
    /// label, and left in the last frame's ink. So the breath publishes a
    /// ``PictureInkHold``, and the picture keeps the breath's bright end, the
    /// label's resting colour, for the whole breath. Its glyphs still breathe.
    var monoInk: RGBA
    var monoPaper: RGBA

    /// The colours the terminal had reported when the picture was recoloured.
    ///
    /// A mode that names the terminal's slots — `.ansi16`, or a `.palette` of
    /// `.ansi(_:)` entries — paints each pixel in the colour the terminal
    /// reported for its slot, or in xterm's value while it has reported none.
    /// A palette mode compares equal by its colours whatever they measure as,
    /// so without this a report arriving after the picture was sent changed the
    /// pixels and not the signature, and the terminal kept the old picture.
    ///
    /// Every mode carries it, so a report re-sends a picture that does not name
    /// a slot too. That costs one transmission per picture per report, which
    /// is rare, where leaving it out of the modes that do name one would be a
    /// picture that never updates.
    var terminalColors: TerminalColors
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

// MARK: - Where the store files a signature

/// A signature the store can file, so that finding a picture among many does
/// not mean comparing it against every picture the terminal holds.
///
/// Not a hash of the whole signature. Most of what decides a picture (a paint,
/// a configuration, a colour mode) is `Equatable` and not `Hashable`, and
/// making it hashable would add a conformance to about ten public types for
/// one internal lookup. ``storeBucket`` is a cheap projection of some of the fields
/// `==` compares instead. The store files each image under its bucket and its
/// cell box, and compares a request only against the images filed there.
///
/// The one rule: **two signatures that compare equal give equal buckets.**
/// Break it and a view asking for a picture the terminal already holds looks
/// in the wrong place, transmits a second copy, and shares nothing. Built from
/// fields that `==` compares with their own synthesised equality, it holds by
/// construction. A field left out only makes a bucket hold more pictures, and
/// a bucket every picture shares makes each lookup a search of them all.
protocol ImageStoreSignature: Equatable {
    associatedtype StoreBucket: Hashable
    /// Some of the fields `==` compares, as a key the store can hash.
    var storeBucket: StoreBucket { get }
}

extension TerminalImageSignature: ImageStoreSignature {
    /// Which file or address: a list of different icons at one size is as
    /// many buckets as icons.
    var storeBucket: String {
        switch source {
        case .file(let path): path
        case .url(let address): address
        }
    }
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
/// the others rather than deleting it under them. Finding the image to share
/// does not compare the request against every image the terminal holds; see
/// ``ImageStoreSignature``.
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
        /// Where the image is filed: its signature's bucket, and the cell box
        /// declared to the terminal, so a box-only change can be spotted and
        /// answered with a placement alone.
        var slot: Slot
        /// When the image was put in the terminal, counting up. Two images can
        /// hold one picture in one box (``sharedImage(of:in:)`` says how), and
        /// a view that asks for that picture then shares the older one. A
        /// shutdown deletes in this order too (``releaseAll()``).
        let arrival: Int
        /// The placeholder cells, which are a function of the id and the box.
        var cells: [String]
        /// The tokens currently drawing this image. Empty means nobody, and
        /// nobody means deleted — an image is never kept on the chance that
        /// someone comes back for it.
        var holders: Set<String>
    }

    /// Where an image is filed: its signature's
    /// ``ImageStoreSignature/storeBucket`` and its cell box. Two requests for
    /// one picture in one box always come to the same slot, and a slot almost
    /// always holds one image.
    private struct Slot: Hashable {
        let bucket: AnyHashable
        let columns: Int
        let rows: Int
    }

    private var images: [KittyGraphics.ImageID: Image] = [:]
    /// The images filed in each slot.
    private var slots: [Slot: [KittyGraphics.ImageID]] = [:]
    /// Which image each token is drawing.
    private var entries: [String: KittyGraphics.ImageID] = [:]
    private var pending = ""
    private var nextID: KittyGraphics.ImageID = 1
    /// The next image's arrival.
    private var nextArrival = 0

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
    func placeholderRows<Signature: ImageStoreSignature>(
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
        if let id = entries[token], let image = images[id], image.signature == wanted {
            if image.slot.columns == columns, image.slot.rows == rows {
                return image.cells
            }
            // The same picture in a DIFFERENT box. Alone on the image, this
            // needs no bytes: an `a=p` replaces the placement for that id and
            // the terminal refits the picture to the new rectangle. Without
            // this case every step of a resize drag ran delete + transmit +
            // place — megabytes, per step, to end up with the pixels already
            // in the store. Shared, the box belongs to the others too, so the
            // token moves on to an image of its own instead.
            if image.holders == [token] {
                let cells = KittyGraphics.placeholderRows(id: id, columns: columns, rows: rows)
                guard !cells.isEmpty else { return nil }
                pending += KittyGraphics.placement(id: id, columns: columns, rows: rows)
                refile(id, in: Slot(bucket: image.slot.bucket, columns: columns, rows: rows), cells: cells)
                return cells
            }
        }

        // Somebody else's image of exactly this picture in exactly this box:
        // share it, and let go of whatever this token was drawing before.
        let slot = Slot(bucket: AnyHashable(signature.storeBucket), columns: columns, rows: rows)
        if let id = sharedImage(of: wanted, in: slot) {
            if entries[token] != id { release(token: token) }
            // `release` frees only an image this token was drawing, and this
            // one was not, so it is still here. Checked rather than assumed.
            guard images[id] != nil else { return nil }
            images[id]?.holders.insert(token)
            entries[token] = id
            return images[id]?.cells
        }

        // A picture the terminal does not have. The token's previous image is
        // freed first if this was its only holder — reusing the id, so a view
        // that changes picture every frame does not walk the id space.
        var reusableID: KittyGraphics.ImageID?
        if let previous = entries[token], images[previous] != nil {
            // Delete first, on the same id. Re-transmitting over a live id
            // is documented to replace it, but "documented to replace it"
            // is a claim about five terminals of which one has been
            // measured, and the cost of being wrong is an image store that
            // grows every time a window is resized. Twenty bytes buys not
            // having to find out.
            if letGo(of: previous, by: token) { reusableID = previous }
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
        file(Image(id: id, signature: wanted, slot: slot, arrival: nextArrival, cells: cells, holders: [token]))
        nextArrival += 1
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
        guard let id = entries.removeValue(forKey: token) else { return }
        letGo(of: id, by: token)
    }

    /// Gives back every image, for a shutdown that wants to leave the terminal
    /// as it found it.
    func releaseAll() {
        // In the order the images were put in, so a shutdown writes the same
        // bytes on every run. A dictionary's order is not that: it changes
        // from one process to the next.
        for image in images.values.sorted(by: { $0.arrival < $1.arrival }) {
            pending += KittyGraphics.delete(id: image.id)
        }
        images.removeAll()
        slots.removeAll()
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

    // MARK: - Filing

    /// The image of `wanted` in `slot`'s box, or `nil` if the terminal holds
    /// none.
    ///
    /// The older, if two do. Two can: a view alone on its image that asks for
    /// a new box moves the image there with a placement, and another view may
    /// already have transmitted the same picture in that box.
    private func sharedImage(of wanted: AnyImageSignature, in slot: Slot) -> KittyGraphics.ImageID? {
        var oldest: Image?
        for id in slots[slot] ?? [] {
            guard let image = images[id], image.signature == wanted else { continue }
            if let current = oldest, current.arrival < image.arrival { continue }
            oldest = image
        }
        return oldest?.id
    }

    /// Takes `token` off image `id`, and gives the image back to the terminal
    /// if nobody else is drawing it. Returns whether the image went.
    @discardableResult
    private func letGo(of id: KittyGraphics.ImageID, by token: String) -> Bool {
        guard images[id] != nil else { return false }
        images[id]?.holders.remove(token)
        guard images[id]?.holders.isEmpty == true else { return false }
        pending += KittyGraphics.delete(id: id)
        unfile(id)
        return true
    }

    private func file(_ image: Image) {
        images[image.id] = image
        slots[image.slot, default: []].append(image.id)
    }

    @discardableResult
    private func unfile(_ id: KittyGraphics.ImageID) -> Image? {
        guard let image = images.removeValue(forKey: id) else { return nil }
        slots[image.slot]?.removeAll { $0 == id }
        if slots[image.slot]?.isEmpty == true { slots.removeValue(forKey: image.slot) }
        return image
    }

    /// Moves image `id` to `slot`, drawn by `cells`: the same picture, placed
    /// in a new box.
    private func refile(_ id: KittyGraphics.ImageID, in slot: Slot, cells: [String]) {
        guard var image = unfile(id) else { return }
        image.slot = slot
        image.cells = cells
        file(image)
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
        for _ in 0..<KittyGraphics.maximumImageID {
            let candidate = nextID
            nextID = candidate >= KittyGraphics.maximumImageID - 2 ? 1 : candidate + 1
            if images[candidate] == nil { return candidate }
        }
        return 1
    }
}
