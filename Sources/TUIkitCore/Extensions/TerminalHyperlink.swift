//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalHyperlink.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - OSC 8 hyperlinks

/// A destination the terminal itself can open — the OSC 8 hyperlink, which
/// attaches a URI to a run of cells the way SGR attaches a colour to them.
///
/// ```swift
/// let link = TerminalHyperlink(destination: "https://example.com")
/// let styled = "Documentation".hyperlinked(to: link)
/// ```
///
/// ## What it buys, given that TUIkit already handles clicks
///
/// A ``Link`` is focusable and clickable without any of this: Tab to it and
/// press Return, or click it, and the app opens the URL. What the escape adds
/// is that **the terminal now knows where those cells point** — so the URL
/// becomes something the terminal can show and offer to copy even though the
/// label says "Documentation" and the destination appears nowhere on screen.
/// Nothing an application can do gives it that; a click it handles itself
/// leaves the URL as invisible as it was.
///
/// What a person can then DO with it is the terminal's business, and only some
/// of it is independent of the application. Hover previews (Ghostty's
/// `link-previews`, iTerm2's underline-on-hover) and right-click → Copy Link
/// are the terminal's own chrome. **Click-to-open is not**: a TUIkit app holds
/// mouse reporting open, and a terminal that forwards the modified click to
/// the application cannot also act on it. iTerm2 is measured to do exactly
/// that — ⌘-click arrives as the protocol's meta bit
/// (`Documentation/Terminal-compatibility.md`, iTerm2 Input behaviour) — so
/// ⌘-click there reaches the app rather than the link. Shift is the
/// conventional bypass for mouse reporting and is the gesture to try, but it
/// is UNVERIFIED here and Ghostty's modifier-clicks are not captured at all.
/// The visible-and-copyable half is what this is for; treat opening as a
/// bonus that varies by host.
///
/// ## The shape of the sequence
///
/// `ESC ] 8 ; <params> ; <URI> ST` opens; `ESC ] 8 ; ; ST` closes; the cells
/// in between carry the link. The terminator is `ST` (`ESC \`) rather than the
/// `BEL` xterm also accepts — that is the form the specification gives, it is
/// what tmux writes, and all four measured hosts swallow both (see
/// `Documentation/Terminal-compatibility.md`). `BEL` would additionally put a
/// C0 control inside every link, which is a byte the row sanitiser has to
/// reason about for no gain.
///
/// ## Why the destination is re-encoded rather than trusted
///
/// The sequence ends at an `ESC` or a `BEL`, so a destination containing
/// either does not merely render oddly — it ENDS THE SEQUENCE, and everything
/// after it is text the terminal draws. A URL is exactly the kind of value an
/// application builds out of data it did not author, so ``opening`` percent-
/// encodes every byte outside printable ASCII rather than assuming the caller
/// did. That is the same reasoning as ``Swift/String/sanitizedForTerminal``:
/// the gate belongs where the escape is written, not in each caller.
public struct TerminalHyperlink: Sendable, Equatable {

    /// Where the link points. Encoded on the way out, so it may be given as
    /// written.
    public let destination: String

    /// An optional identity, shared by every run belonging to the same link.
    ///
    /// A hyperlink is a property of CELLS, so a link whose label wraps, or is
    /// split by a column of something else, is several runs. A host that
    /// implements the parameter treats runs sharing an `id` as one link and
    /// highlights them together on hover; without it they are separate links
    /// that happen to point to the same place, which looks wrong exactly when
    /// the label was long enough to wrap.
    public let id: String?

    /// Creates a hyperlink.
    ///
    /// - Parameters:
    ///   - destination: The URI to open. Encoded by ``opening``.
    ///   - id: An identity shared by every run of one logical link.
    public init(destination: String, id: String? = nil) {
        self.destination = destination
        self.id = id
    }

    /// The sequence that opens this link — everything after it, up to a
    /// ``closing``, carries the destination.
    public var opening: String {
        let parameters = id.map { "id=" + Self.encoded($0) } ?? ""
        return Self.introducer + parameters + ";" + Self.encoded(destination) + Self.terminator
    }

    /// The sequence that closes whatever link is open. A link with no
    /// destination is how OSC 8 spells "no link from here on".
    public static let closing = introducer + ";" + terminator

    /// `ESC ] 8 ;` — the introducer, without the parameter field.
    static let introducer = "\u{1B}]8;"

    /// `ST` — `ESC \`.
    static let terminator = "\u{1B}\\"

    /// `value` with every byte that is not a printable, non-blank ASCII
    /// character percent-encoded.
    ///
    /// OSC 8 requires only that bytes outside 32…126 be encoded, and this
    /// encodes the space (32) as well, because the value is a **URI**: a raw
    /// space is not one, and `%20` is what every host will resolve to the same
    /// place. Nothing else printable is touched — `#`, `?`, `&` and `=` are
    /// URI syntax and encoding them would change where the link points.
    ///
    /// `;` is deliberately not encoded in the URI either: the URI is the LAST
    /// field, so a semicolon in a path or a query cannot be mistaken for a
    /// field separator. In an `id` it is encoded, because there the field
    /// boundary is real.
    static func encoded(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.utf8.count)
        for byte in value.utf8 {
            if byte > 0x20, byte < 0x7F, byte != 0x25 {  // printable ASCII, not ' ' or '%'
                result.unicodeScalars.append(Unicode.Scalar(byte))
            } else {
                // '%' itself is encoded so the encoding round-trips: a
                // destination that already contained "%41" must reach the host
                // as "%41" and not as "A".
                //
                // Hand-rolled rather than `String(format:)`, which is
                // Foundation — and this module deliberately has no Foundation
                // dependency, so that one import would be paid by every
                // platform TUIkitCore builds for.
                result.unicodeScalars.append("%")
                result.unicodeScalars.append(Self.hexDigits[Int(byte >> 4)])
                result.unicodeScalars.append(Self.hexDigits[Int(byte & 0x0F)])
            }
        }
        return result
    }

    private static let hexDigits: [Unicode.Scalar] = Array("0123456789ABCDEF".unicodeScalars)

    /// Whether `sequence` is an OSC 8 introducer at all — the test every
    /// escape walk applies before asking which of the two it is.
    static func isHyperlink(_ sequence: String) -> Bool {
        sequence.hasPrefix(introducer)
    }

    /// Whether `sequence` OPENS a link rather than closing one.
    ///
    /// The difference is the URI field: `ESC]8;;ST` names no destination, and
    /// that is precisely how the sequence says "the link ends here". So the
    /// question is not which sequence was written but whether the field after
    /// the parameters has anything in it.
    static func opensLink(_ sequence: String) -> Bool {
        guard isHyperlink(sequence) else { return false }
        var body = sequence.dropFirst(introducer.count)
        if body.hasSuffix(terminator) {
            body = body.dropLast(terminator.count)
        } else if body.hasSuffix("\u{07}") {
            body = body.dropLast()
        }
        // Everything after the FIRST `;` is the URI, semicolons included.
        guard let separator = body.firstIndex(of: ";") else { return false }
        return body.index(after: separator) < body.endIndex
    }
}

// MARK: - Whether to emit them at all

extension TerminalHyperlink {

    /// Whether the terminal painting this app's output honours OSC 8 — the
    /// answer the render path reads, published from
    /// `TerminalClient.applyHyperlinkSupport()`.
    ///
    /// The same shape as ``TerminalWidthTraits/current``, and for the same
    /// reason: the question is answered once, up in the umbrella module where
    /// the host is identified, and READ from a render path that is not
    /// main-actor isolated and cannot ask. Splitting the two keeps the
    /// measured table and its overrides in one place while leaving this a
    /// `Bool` load.
    ///
    /// **Defaults to `false`.** A capability is not a defect: emitting a
    /// sequence the host ignores costs a link that does nothing, so the safe
    /// answer before anybody has published one is "no links", not "links".
    public static var isSupported: Bool {
        get { taskSupported ?? processSupported }
        set { processSupported = newValue }
    }

    /// `nonisolated(unsafe)` for the reason ``ColorDepth/current`` gives: set
    /// during startup, before the render loop exists, and only read after.
    nonisolated(unsafe) private static var processSupported = false

    /// A task-scoped pin, bound by ``withSupport(_:operation:)``.
    @TaskLocal private static var taskSupported: Bool?

    /// Runs `operation` with ``isSupported`` pinned on this task only.
    ///
    /// Task-local rather than a mutate-and-restore global because Swift
    /// Testing runs suites in parallel: a test that pinned the flag globally
    /// would put links into another test's rendering.
    @discardableResult
    public static func withSupport<T>(
        _ supported: Bool, operation: () throws -> T
    ) rethrows -> T {
        try $taskSupported.withValue(supported, operation: operation)
    }
}

// MARK: - Applying one

extension String {
    /// This string with `link` attached to every cell of it.
    ///
    /// The pair is balanced and self-contained, so the result can be placed
    /// wherever the unlinked string could: nothing after it inherits the link,
    /// and its width is unchanged — the sequences are escapes, and every scan
    /// in this framework counts them as the zero cells they paint.
    ///
    /// - Parameter link: Where the cells point.
    /// - Returns: The string wrapped in the opening and closing sequences.
    public func hyperlinked(to link: TerminalHyperlink) -> String {
        link.opening + self + TerminalHyperlink.closing
    }
}

// MARK: - Carrying one across a cut

/// Whether an OSC 8 hyperlink is open at the point a segment walk has reached,
/// and what opened it.
///
/// A hyperlink is state that spans cells, exactly as an SGR colour is, so a cut
/// through a line carrying one has the same two obligations the splitters
/// already meet for styling — and neither is optional here:
///
/// - **The near side must close it.** A prefix that keeps the opening sequence
///   and loses the closing one does not merely lose the link: on a host that
///   honours OSC 8, every cell drawn after the cut joins it. That is the rest
///   of the row, the padding included, and then whatever the next row's first
///   sequence does not happen to close.
/// - **The far side must re-open it.** A suffix that begins inside a link and
///   does not restate it drops the link from cells that are supposed to carry
///   it, which is the quiet half — nothing looks broken, the link is simply
///   shorter than the label.
///
/// The two are not symmetric in consequence, and the asymmetry is worth
/// remembering when deciding what to test: forgetting to close is a visible
/// defect that spreads, forgetting to re-open is an invisible one that does not.
struct HyperlinkScan {

    /// The sequence that opened the link in force, or `nil` when none is.
    private(set) var opening: String?

    /// Note an escape sequence the walk has just passed. Anything that is not
    /// an OSC 8 introducer leaves the state alone.
    mutating func note(_ sequence: String) {
        guard TerminalHyperlink.isHyperlink(sequence) else { return }
        opening = TerminalHyperlink.opensLink(sequence) ? sequence : nil
    }

    /// What a cut here owes the near side.
    var closingIfOpen: String { opening == nil ? "" : TerminalHyperlink.closing }

    /// What a resumption here owes the far side.
    var reopening: String { opening ?? "" }
}
