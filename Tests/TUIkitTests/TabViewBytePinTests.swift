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
    ///
    /// Re-recorded 2026-09-14, when the active chip's resting label became the
    /// palette's readable ink rather than white: on Green, the foreground at rest and
    /// a loud end that stands off it. Nothing else in these frames moved.
    private static let pinned: [String: String] = [
        "bordered/focused/truecolor": "1523692c1fa8a363",
        "bordered/focused/palette256": "dac9a90360d23de6",
        "bordered/still/truecolor": "cf6dd306fc21fcf7",
        "bordered/still/palette256": "2299a062731a5d41",
        "compact/focused/truecolor": "cd79d6474278ab50",
        "compact/focused/palette256": "f4fff09187eedb3b",
        "compact/still/truecolor": "23b164d3aae272b0",
        "compact/still/palette256": "81f6af1a13ccf52a",
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
