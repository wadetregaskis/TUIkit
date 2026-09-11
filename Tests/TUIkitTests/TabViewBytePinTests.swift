//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TabViewBytePinTests.swift
//
//  The exact bytes a TabView draws under a shipped (opaque) palette, pinned
//  before its strips move onto `ClaimingRow`. That conversion must not change a
//  single byte where nothing is translucent, and nothing else in the suite can
//  see a byte: the golden snapshots and every TabView test compare stripped text.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A TabView's bytes under an opaque palette")
struct TabViewBytePinTests {

    enum Shape: String, CaseIterable, Sendable {
        case bordered, compact
    }

    /// The digests recorded on the commit before the strips were converted, keyed
    /// "shape/focused-or-still/depth". A mismatch prints the new digest and the
    /// frame, so an INTENDED change re-records by copying them here.
    private static let pinned: [String: String] = [
        "bordered/focused/truecolor": "b16a85cdec8ea9bb",
        "bordered/focused/palette256": "32c737f4a0f84066",
        "bordered/still/truecolor": "392a58fe53a0a44b",
        "bordered/still/palette256": "ad2b0523c3d359f",
        "compact/focused/truecolor": "e7e2fd8b278f6930",
        "compact/focused/palette256": "ecd0cc54b58baea9",
        "compact/still/truecolor": "64297951fe7ee4e8",
        "compact/still/palette256": "b5f87ea22cb046f6",
    ]

    @Test("A TabView draws the bytes it drew before", arguments: Shape.allCases, [true, false])
    func bytesUnchanged(shape: Shape, focused: Bool) {
        for depth in [ColorDepth.truecolor, .palette256] {
            let drawn = withColorDepth(depth) { render(shape: shape, focused: focused) }
            let key = "\(shape.rawValue)/\(focused ? "focused" : "still")/\(depth)"
            #expect(drawn.opacityRegions.isEmpty, "\(key): an opaque palette claims nothing")
            let digest = Self.digest(drawn.lines)
            #expect(
                Self.pinned[key] == digest,
                """
                \(key) draws \(digest):
                \(drawn.lines.map(\.stripped).joined(separator: "\n"))
                """)
        }
    }

    /// Six tabs whose labels outrun a 30-cell box, so the strip wraps: the folder
    /// style draws an upper row as well as the active row that opens into the
    /// panel. Focused, the active chip breathes, and the frame drawn is the cycle's
    /// first — deterministic, since no cursor timer is running.
    private func render(shape: Shape, focused: Bool) -> FrameBuffer {
        let view = TabView(selection: .constant(4)) {
            Tab("Alpha", value: 0) { Text("alpha body") }
            Tab("Bravo", value: 1) { Text("bravo body") }
            Tab("Charlie", value: 2) { Text("charlie body") }
            Tab("Delta", value: 3) { Text("delta body") }
            Tab("Echo", value: 4) { Text("echo body") }
            Tab("Foxtrot", value: 5) { Text("foxtrot body") }
        }
        let context = makeRenderContext(width: 30, height: 12) { environment, _ in
            environment.palette = SystemPalette.default
        }
        // A sentinel registered first holds the focus, so the strip rests.
        if !focused { context.environment.focusManager?.register(FocusSentinel()) }
        switch shape {
        case .bordered: return renderToBuffer(view.tabViewStyle(.bordered), context: context)
        case .compact: return renderToBuffer(view.tabViewStyle(.compact), context: context)
        }
    }

    /// FNV-1a over the lines' UTF-8, in hex: stable across runs, processes and
    /// platforms, where `hashValue` is seeded per process.
    private static func digest(_ lines: [String]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in lines.joined(separator: "\n").utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
