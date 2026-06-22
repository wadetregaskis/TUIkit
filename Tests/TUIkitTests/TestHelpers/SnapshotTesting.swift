//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SnapshotTesting.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

// MARK: - Golden-snapshot harness

/// A change-detection corpus: representative views are rendered deterministically
/// and compared against committed golden snapshots, so a layout-affecting change
/// (notably the flexibility-contract work) surfaces *every* affected view for
/// case-by-case review rather than silently shifting output.
///
/// Snapshots capture **layout, not colour**: the ANSI-stripped glyph grid plus a
/// `# WxH` dimensions header. Stripping makes focus/pulse colour irrelevant (so
/// the files are stable and diffable) while preserving exactly what the layout
/// engine controls — widths, heights, and where each glyph lands.
///
/// To accept intended changes, re-run with `TUIKIT_RECORD_SNAPSHOTS=1`, which
/// (over)writes the goldens instead of comparing.

/// The committed golden directory (`Tests/TUIkitTests/__Snapshots__`).
private func snapshotsDirectory() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // TestHelpers/
        .deletingLastPathComponent()  // TUIkitTests/
        .appendingPathComponent("__Snapshots__")
}

private var isRecordingSnapshots: Bool {
    ProcessInfo.processInfo.environment["TUIKIT_RECORD_SNAPSHOTS"] != nil
}

/// Serialises a buffer to its reviewable snapshot form: a `# WxH` header (so a
/// width/height change is caught even where a line's trailing padding is trimmed)
/// then the ANSI-stripped lines, right-trimmed to keep the files free of trailing
/// whitespace.
@MainActor
func snapshotText(_ buffer: FrameBuffer) -> String {
    func rtrim(_ s: String) -> String {
        var s = s
        while s.hasSuffix(" ") { s.removeLast() }
        return s
    }
    let body = buffer.lines.map { rtrim($0.stripped) }.joined(separator: "\n")
    return "# \(buffer.width)x\(buffer.height)\n\(body)"
}

/// Renders `view` deterministically (fixed size, fresh focus manager, isolated
/// render cache) and compares it to its golden snapshot, recording an issue with
/// a line diff on any change. In record mode it (over)writes the golden. A
/// missing golden is recorded for convenience and flagged so it gets reviewed.
@MainActor
func assertSnapshot(
    _ name: String,
    width: Int,
    height: Int,
    of view: some View
) {
    let actual = snapshotText(renderToBuffer(view, context: makeRenderContext(width: width, height: height)))
    let dir = snapshotsDirectory()
    let url = dir.appendingPathComponent("\(name).txt")
    let actualURL = dir.appendingPathComponent("\(name).actual.txt")

    func write(_ text: String, to target: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? text.write(to: target, atomically: true, encoding: .utf8)
    }

    if isRecordingSnapshots {
        write(actual, to: url)
        try? FileManager.default.removeItem(at: actualURL)
        return
    }

    guard let golden = try? String(contentsOf: url, encoding: .utf8) else {
        write(actual, to: url)
        Issue.record("No golden snapshot for '\(name)' — recorded one; review it and re-run.")
        return
    }

    if golden == actual {
        try? FileManager.default.removeItem(at: actualURL)  // clear any stale failure artefact
    } else {
        write(actual, to: actualURL)
        let message =
            "Snapshot '\(name)' changed (accept with TUIKIT_RECORD_SNAPSHOTS=1):\n"
            + snapshotDiff(golden: golden, actual: actual)
        Issue.record("\(message)")
    }
}

/// A compact line-by-line diff (`-` golden, `+` actual) for the failure message.
func snapshotDiff(golden: String, actual: String) -> String {
    let g = golden.split(separator: "\n", omittingEmptySubsequences: false)
    let a = actual.split(separator: "\n", omittingEmptySubsequences: false)
    var out: [String] = []
    for i in 0..<max(g.count, a.count) {
        let gl = i < g.count ? String(g[i]) : "·(none)"
        let al = i < a.count ? String(a[i]) : "·(none)"
        if gl != al {
            out.append("  - \(gl)")
            out.append("  + \(al)")
        }
    }
    return out.prefix(60).joined(separator: "\n")
}
