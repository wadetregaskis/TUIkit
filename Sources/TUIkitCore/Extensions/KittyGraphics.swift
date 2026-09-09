//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KittyGraphics.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - The Kitty graphics protocol

/// As much of the Kitty graphics protocol as TUIkit uses: put an image in the
/// terminal's store, declare how many cells it covers, and draw it by writing
/// **text**.
///
/// ## Why this protocol and not the other two
///
/// Sixel and iTerm2's inline images both draw pixels at the cursor. That is a
/// position the cell grid knows nothing about: such an image does not scroll
/// with its row, is not clipped by the container that clips its cells, is not
/// covered by a modal composited over it, and cannot be diffed. Kitty's
/// *virtual placements* dissolve the problem instead of working around it —
/// the picture is drawn wherever cells carrying its id appear, so it IS cells,
/// and every part of this framework that already handles cells handles it.
///
/// It is also the only one of the three with a capability handshake, which
/// matters more than it sounds: Warp answers the protocol query `OK` and then
/// refuses virtual placements *by name*, so a host table written from its
/// feature list would have been wrong. The full comparison, and the
/// measurements behind it, are in
/// `Documentation/Terminal graphics protocols.md`.
///
/// ## The three steps
///
/// ```swift
/// terminal.write(KittyGraphics.transmit(pixels: bytes, width: w, height: h, id: 7))
/// terminal.write(KittyGraphics.placement(id: 7, columns: 20, rows: 8))
/// buffer = FrameBuffer(lines: KittyGraphics.placeholderRows(id: 7, columns: 20, rows: 8))
/// ```
///
/// The first two produce no cells and are written once; the third produces the
/// rows the renderer draws every frame. An image transmitted this way is
/// *retained* — transmit once, place many — and must be deleted by id when
/// nothing refers to it any more (``delete(id:)``), or the terminal's image
/// store grows without bound.
///
/// ## `q=2` is on every command, and it is not tidiness
///
/// Every graphics command is acknowledged with `ESC _ G …;OK ESC \` unless
/// suppressed. In an application those bytes arrive on **stdin**, where the
/// input parser reads them as keystrokes. `q=2` suppresses both the OK and the
/// errors, which is the right trade on a render path: there is no reader for
/// them, and the alternative is the terminal typing at the user.
public enum KittyGraphics {

    /// A handle for an image in the terminal's store.
    ///
    /// Capped at 24 bits (``maximumImageID``) because the id travels in the
    /// **foreground colour** of every placeholder cell, and its most
    /// significant byte in a third combining mark — which, capped this way, is
    /// always the mark for zero. A wider id would have to vary that mark per
    /// image instead of stating the same thing on every cell. Sixteen
    /// million concurrent images is not the constraint anyone will meet.
    public typealias ImageID = UInt32

    /// The largest id that fits a direct-colour foreground, so no cell needs a
    /// high-byte diacritic. Ids start at 1: `0` means "no id" to the protocol.
    public static let maximumImageID: ImageID = 0xFF_FFFF

    /// The base64 payload each escape carries. The protocol caps a single
    /// command's payload, and 4096 is the value its own documentation uses.
    static let chunkSize = 4096

    // MARK: - Transmit

    /// How many bytes a pixel takes on the wire, which is also the protocol's
    /// `f` key.
    ///
    /// Both are 8-bit and row-major, so either is a straight copy out of
    /// ``RGBAImage``. The choice is worth making rather than always sending
    /// the wider one: a photograph has no transparency, and a quarter of a
    /// multi-megabyte transmission is a quarter of the time the app spends
    /// not drawing the frame that shows it.
    public enum PixelFormat: Int, Sendable {
        /// Opaque — three bytes a pixel.
        case rgb = 24
        /// With an alpha channel — four bytes a pixel. The terminal
        /// composites the image over whatever the cells' background is, which
        /// is the only way a picture with transparency can sit on a themed
        /// page.
        case rgba = 32

        /// Bytes per pixel.
        public var stride: Int { self == .rgb ? 3 : 4 }
    }

    /// The escape (or escapes) that put `pixels` in the terminal's store under
    /// `id`, and nothing else — no placement, no pixels on screen.
    ///
    /// Chunked at `chunkSize`, because one escape cannot carry a whole
    /// image: `m=1` says another chunk follows and `m=0` ends the run, with
    /// the control keys on the first chunk only. A payload that fits in one
    /// escape omits `m` entirely — the protocol reads its absence as "not
    /// chunked", which is a different statement from "the last chunk of one".
    ///
    /// - Parameters:
    ///   - pixels: The picture, row-major and 8-bit, `format.stride` bytes a
    ///     pixel with nothing between rows. Flat bytes rather than a pixel
    ///     type because a full-screen picture is millions of pixels and the
    ///     caller packs them once per image — an `RGBAImage`'s `[RGBA]` is NOT
    ///     this layout. The whole array is then sent, so bytes past the stated
    ///     size are wire cost for nothing; fewer than the size claims is
    ///     refused outright, because the terminal decodes by the geometry it
    ///     was given and would draw the garbled remainder rather than nothing.
    ///   - format: Whether those bytes carry alpha, which is also the
    ///     protocol's `f` key — ``PixelFormat`` says why the narrower one is
    ///     worth choosing rather than always sending `rgba`.
    ///   - width: The picture's width in pixels. The payload carries no shape
    ///     of its own, which is why the size is stated here and why it is
    ///     checked against `pixels.count`.
    ///   - height: Its height in pixels.
    ///   - id: The store slot it occupies, `1` through ``maximumImageID``. `0`
    ///     is not an id but the protocol's word for "none", and the ceiling is
    ///     what a direct-colour foreground carries whole — which is why the
    ///     third mark every placeholder cell spells, the id's high byte, is
    ///     always the mark for zero rather than absent. An id outside that
    ///     range is refused rather than stored under a name no placement could
    ///     spell.
    ///   - compressed: Whether to deflate the pixels first and say so with
    ///     `o=z`. Only where the terminal answered the compression probe
    ///     (``isCompressionSupported``) — a host that does not understand
    ///     `o=z` draws nothing, silently, under `q=2`. The bytes go through
    ///     ``SystemZlib``, so a host with no zlib sends them raw whatever is
    ///     asked; so does a payload deflate makes no smaller. The chunking is
    ///     the same either way: the protocol compresses BEFORE base64, and
    ///     chunks after.
    /// - Returns: the escapes, or `""` for a request that cannot be honoured
    ///   (a non-positive size, an id outside `1...maximumImageID`, or fewer
    ///   pixels than the size claims).
    public static func transmit(
        pixels: [UInt8], format: PixelFormat = .rgba, width: Int, height: Int, id: ImageID,
        compressed: Bool = false
    ) -> String {
        guard width > 0, height > 0, id > 0, id <= maximumImageID,
            pixels.count >= width * height * format.stride
        else { return "" }

        var payload = pixels
        var deflated = false
        if compressed, let smaller = SystemZlib.compress(pixels), smaller.count < pixels.count {
            payload = smaller
            deflated = true
        }

        var encoded: [UInt8] = []
        encoded.reserveCapacity(4 * ((payload.count + 2) / 3))
        base64(payload, into: &encoded)

        let chunks = (encoded.count + chunkSize - 1) / chunkSize
        var out: [UInt8] = []
        out.reserveCapacity(encoded.count + 64 * chunks + 64)

        var start = 0
        var index = 0
        while start < encoded.count {
            let end = min(start + chunkSize, encoded.count)
            let head: String
            if index == 0 {
                let chunked = chunks > 1 ? ",m=1" : ""
                head = "a=t,q=2,f=\(format.rawValue),t=d,s=\(width),v=\(height),i=\(id)"
                    + (deflated ? ",o=z" : "") + chunked
            } else {
                // `q=2` on EVERY chunk, not just the first. The terminal's
                // acknowledgement is emitted when the transmission COMPLETES,
                // which is the last chunk — and a last chunk that carries no
                // `q` is a last chunk that may be answered out loud. Four
                // bytes per chunk against a reply arriving on the
                // application's stdin, where the input parser would read it as
                // typing.
                head = (end < encoded.count ? "m=1" : "m=0") + ",q=2"
            }
            out.append(contentsOf: introducer)
            out.append(contentsOf: head.utf8)
            out.append(0x3B)  // ;
            out.append(contentsOf: encoded[start..<end])
            out.append(contentsOf: terminator)
            start = end
            index += 1
        }
        return ascii(out)
    }

    // MARK: - Place

    /// The escape that declares a **virtual** placement: image `id` covers
    /// `columns` × `rows` cells, wherever its placeholder cells are written.
    ///
    /// `U=1` is the whole point — it asks for a placement with no position of
    /// its own, which is what lets the picture be addressed as text. Without
    /// it the terminal would draw the image at the cursor and the grid would
    /// know nothing about it.
    ///
    /// Sent once per (image, size); a resize needs a new one, which replaces
    /// the old placement for that id.
    public static func placement(id: ImageID, columns: Int, rows: Int) -> String {
        guard id > 0, id <= maximumImageID, columns > 0, rows > 0 else { return "" }
        return "\u{1B}_Ga=p,U=1,q=2,i=\(id),c=\(columns),r=\(rows)\u{1B}\\"
    }

    /// The escape that deletes image `id` and frees its data.
    ///
    /// `d=I` — the capital — deletes the image itself; the lower-case form
    /// removes only its placements and leaves the pixels in the store. An
    /// application that never sends this leaks the terminal's memory for as
    /// long as the terminal runs, which is a resource TUIkit now owns and
    /// nothing else will clean up.
    public static func delete(id: ImageID) -> String {
        guard id > 0, id <= maximumImageID else { return "" }
        return "\u{1B}_Ga=d,d=I,q=2,i=\(id)\u{1B}\\"
    }

    // MARK: - Ask

    /// The protocol's own capability query: a one-pixel transmit with `a=q`,
    /// which a terminal implementing the protocol answers and one that does
    /// not ignores.
    ///
    /// Deliberately NOT `q=2`: this is the one command whose reply is the
    /// point. Whoever sends it must be reading the answer.
    public static func query(id: ImageID) -> String {
        "\u{1B}_Gi=\(id),a=q,t=d,f=24,s=1,v=1;AAAA\u{1B}\\"
    }

    // MARK: - Bytes

    /// `ESC _ G` — the APC introducer plus the protocol's own key.
    static let introducer: [UInt8] = [0x1B, 0x5F, 0x47]

    /// `ESC \` — the string terminator.
    static let terminator: [UInt8] = [0x1B, 0x5C]

    /// A run of ASCII bytes as a `String`, written straight into the string's
    /// own storage.
    ///
    /// Every byte an escape is built from is ASCII by construction — the
    /// protocol's keys, the digits, and the base64 alphabet — so there is no
    /// decoding to get wrong. Written this way rather than through a decoding
    /// initializer because an image's payload is megabytes and this is the one
    /// place it is copied.
    package static func ascii(_ bytes: [UInt8]) -> String {
        String(unsafeUninitializedCapacity: bytes.count) { buffer in
            _ = buffer.initialize(fromContentsOf: bytes)
            return bytes.count
        }
    }

    private static let base64Alphabet: [UInt8] = Array(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)

    /// Standard base64, appended to `out`.
    ///
    /// Hand-rolled rather than routed through `Data`: this module does not
    /// import Foundation for it, an image is megabytes and every intermediate
    /// copy is one too many, and the whole thing is fifteen lines that a test
    /// can pin against known vectors.
    package static func base64(_ bytes: [UInt8], into out: inout [UInt8]) {
        let alphabet = base64Alphabet
        var index = 0
        while index + 2 < bytes.count {
            let triple =
                (UInt32(bytes[index]) << 16) | (UInt32(bytes[index + 1]) << 8)
                | UInt32(bytes[index + 2])
            out.append(alphabet[Int((triple >> 18) & 0x3F)])
            out.append(alphabet[Int((triple >> 12) & 0x3F)])
            out.append(alphabet[Int((triple >> 6) & 0x3F)])
            out.append(alphabet[Int(triple & 0x3F)])
            index += 3
        }
        let remaining = bytes.count - index
        guard remaining > 0 else { return }
        let second = remaining > 1 ? UInt32(bytes[index + 1]) : 0
        let triple = (UInt32(bytes[index]) << 16) | (second << 8)
        out.append(alphabet[Int((triple >> 18) & 0x3F)])
        out.append(alphabet[Int((triple >> 12) & 0x3F)])
        out.append(remaining > 1 ? alphabet[Int((triple >> 6) & 0x3F)] : 0x3D)  // =
        out.append(0x3D)  // =
    }
}

// MARK: - Whether this terminal has it

extension KittyGraphics {

    /// Whether the terminal painting this app's output supports the one
    /// feature TUIkit needs — a **virtual placement**, drawn through Unicode
    /// placeholders — published from `TerminalClient.applyGraphicsSupport()`.
    ///
    /// The same shape as ``TerminalHyperlink/isSupported``, and read from the
    /// same place: a render path that is not main-actor isolated and cannot go
    /// asking the terminal anything.
    ///
    /// What it is NOT the same as is where the answer comes from. A hyperlink
    /// is looked up in a table of hosts somebody measured, because no query
    /// reports it. This one is **asked**: the terminal is handed an image and
    /// a placement request at startup and either says `OK` or does not, so an
    /// unknown terminal that supports the protocol gets pictures without
    /// anybody adding it to a list, and Warp — which answers the protocol
    /// query `OK` and refuses the placement by name — is excluded by its own
    /// answer rather than by a maintainer noticing.
    ///
    /// **Defaults to `false`**, which is what makes the whole feature safe to
    /// add: every path that reads this falls back to the glyph renderer, which
    /// has drawn every image in this framework until now and still draws them
    /// on two of the four hosts (Apple Terminal and Warp).
    public static var isSupported: Bool {
        get { taskSupported ?? processSupported }
        set { processSupported = newValue }
    }

    /// `nonisolated(unsafe)` for the reason ``TerminalHyperlink/isSupported``
    /// gives: written during startup, before the render loop exists, and only
    /// read after.
    nonisolated(unsafe) private static var processSupported = false

    /// A task-scoped pin, bound by ``withSupport(_:compression:operation:)``.
    @TaskLocal private static var taskSupported: Bool?

    /// Whether the terminal also takes a transmission deflated (`o=z`) — asked
    /// at startup alongside the placement, and ANDed with ``SystemZlib``
    /// having found a zlib to deflate with. Read by the callers of
    /// ``transmit(pixels:format:width:height:id:compressed:)`` to decide what
    /// to ask for; a transmission never compresses on its own.
    ///
    /// A separate answer from ``isSupported`` because it is a separate
    /// question: every host that draws a placement takes raw pixels, and
    /// nothing in the protocol says one that draws them takes them deflated.
    /// Under `q=2` an unsupported `o=z` is a picture that never appears, so
    /// this is `false` until the terminal said otherwise.
    public static var isCompressionSupported: Bool {
        get { taskCompressionSupported ?? processCompressionSupported }
        set { processCompressionSupported = newValue }
    }

    nonisolated(unsafe) private static var processCompressionSupported = false

    @TaskLocal private static var taskCompressionSupported: Bool?

    /// Runs `operation` with ``isSupported`` — and, when given,
    /// ``isCompressionSupported`` — pinned on this task only.
    ///
    /// Task-local rather than a mutate-and-restore global because Swift
    /// Testing runs suites in parallel, and a test that pinned the flag
    /// globally would put placeholder cells into another test's rendering —
    /// where they would be invisible, because no terminal is drawing them.
    @discardableResult
    public static func withSupport<T>(
        _ supported: Bool, compression: Bool? = nil, operation: () throws -> T
    ) rethrows -> T {
        try $taskSupported.withValue(supported) {
            try $taskCompressionSupported.withValue(
                compression ?? taskCompressionSupported, operation: operation)
        }
    }
}
