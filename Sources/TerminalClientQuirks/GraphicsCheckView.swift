//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GraphicsCheckView.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkit

/// Whether this terminal will draw a real picture — the answer TUIkit is using,
/// and, unusually for this app, where it came from.
///
/// Every other screen here reports a MEASUREMENT: somebody ran a probe, wrote
/// the number down, and the framework looks the host up in a table. This one
/// reports a CONVERSATION. At startup the app hands the terminal one pixel and
/// asks it to place the image in its cell grid; `OK` means pictures, anything
/// else means glyphs. So a terminal nobody has ever measured gets pictures
/// simply by being able to draw them, and Warp — which answers the protocol
/// query `OK` and then refuses the placement by name — is excluded by its own
/// answer rather than by a maintainer noticing.
///
/// The picture itself is on the Example app's image pages, which have a
/// **Terminal graphics** toggle: turning it off draws the same picture out of
/// characters, which is the comparison worth looking at. This screen answers
/// the question that comes first — whether the terminal said yes, and what it
/// said its cells were.
struct GraphicsCheckView: View {

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Terminal graphics (Kitty protocol)").bold()
            verdict
            geometry
            note
        }
        .padding(1)
        .border(.palette.border)
    }

    // MARK: - What TUIkit decided

    private var verdict: some View {
        let drawing = TerminalClient.graphicsSupported
        return HStack(spacing: 1) {
            Text("Drawing pictures:").foregroundStyle(.palette.foregroundSecondary)
            Text(drawing ? "yes" : "no").bold()
                .foregroundStyle(drawing ? .palette.success : .palette.foregroundTertiary)
            Text("— \(reason)").foregroundStyle(.palette.foregroundTertiary)
        }
    }

    /// Which of the three sources gave the answer, in the order they are
    /// consulted — and, for the handshake, what it was actually told. "Not
    /// asked" and "asked and refused" are different facts about a terminal and
    /// worth telling apart on screen.
    private var reason: String {
        if TerminalClient.graphicsSupport != nil { return "set in code this session" }
        switch ProcessInfo.processInfo.environment["TUIKIT_GRAPHICS"] {
        case "1": return "TUIKIT_GRAPHICS=1 — the handshake was skipped"
        case "0": return "TUIKIT_GRAPHICS=0 — the handshake was skipped"
        default:
            switch TerminalClient.detectedGraphics {
            case true: return "the terminal acknowledged a virtual placement"
            case false: return "asked, and the terminal did not acknowledge one"
            case nil: return "never asked — no terminal, or a host that prints APC"
            }
        }
    }

    // MARK: - What it said its cells were

    /// The number an image is resampled to. Wrong here costs sharpness rather
    /// than shape — a virtual placement declares its size in CELLS and the
    /// terminal fits the picture into them — which is why a terminal that
    /// reports nothing still gets a picture.
    ///
    /// From the RENDER environment, where the run loop publishes what the
    /// terminal reported. A fresh `EnvironmentValues()` has only the key's
    /// default, and this screen printed 8×16 on every host.
    @Environment(\.imageCellPixels) private var cells

    private var geometry: some View {
        HStack(spacing: 1) {
            Text("Cell size:").foregroundStyle(.palette.foregroundSecondary)
            Text("\(cells.width)×\(cells.height) px").bold()
            Text("— what an image is resampled to before it is sent")
                .foregroundStyle(.palette.foregroundTertiary)
        }
    }

    // MARK: - Why being wrong here is not cheap the way a link is

    private var note: some View {
        Text(
            "Unlike the hyperlink above, this one is NOT safe to force blindly. The protocol "
                + "rides an APC sequence and Apple Terminal does not parse APC — it prints the "
                + "payload, which for a full-screen image is megabytes of base64 across the "
                + "screen. TUIKIT_GRAPHICS=1 is for a terminal you know implements Kitty "
                + "placements and that the handshake could not reach (inside a multiplexer "
                + "that swallows it, say). TUIKIT_GRAPHICS=0 is always safe: it draws the "
                + "picture out of characters, as this framework always has."
        )
        .foregroundStyle(.palette.foregroundSecondary)
    }
}
