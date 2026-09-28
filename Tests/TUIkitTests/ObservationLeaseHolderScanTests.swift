//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ObservationLeaseHolderScanTests.swift
//
//  The one kind of kept result observation leases cannot find for
//  themselves: one kept OUTSIDE the render cache that learns of a change only
//  from the size clear an observed write makes. Every other kept result is
//  stored in the cache, and a store there cannot compile without saying what
//  lease it keeps (`RenderCache.store`'s `recorded`, `storeSize`'s and
//  `storeMeasure`'s `lease:`). A record in `@State` that watches
//  `sizeClearGeneration` is right only while the scopes it depends on live —
//  and nothing holds them unless it holds the leases of the walks that
//  measured it, as the content-width ladder's record does. Unwired, the ladder
//  loses a write to a row it measured off the window (`ObservationLeaseTests`,
//  hole 3, perturbed).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@Suite("Observation leases: every holder outside the render cache keeps its leases")
struct ObservationLeaseHolderScanTests {
    private static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources")

    /// Files that read the size-clear signal and need no lease, with why.
    /// Empty: the ladder, the one reader today, holds its walks' leases.
    private static let exempt: [String: String] = [:]

    /// Every Swift file under `Sources/` outside the render cache's own
    /// directory, with its comments dropped: a file that only mentions the
    /// signal in a comment neither reads it nor needs a lease.
    private static func codeOutsideTheCache() throws -> [(name: String, code: String)] {
        let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        var files: [(name: String, code: String)] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift", !url.path.contains("/TUIkitView/Rendering/") else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            let code = text.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            files.append((url.lastPathComponent, code))
        }
        return files
    }

    @Test("Every reader of the size-clear signal outside the render cache opens a lease computation")
    func sizeClearReadersHoldLeases() throws {
        let files = try Self.codeOutsideTheCache()
        #expect(files.count > 100, "the scan found the sources: \(files.count) files")
        let readers = files.filter { $0.code.contains("sizeClearGeneration") }
        #expect(readers.map(\.name).contains("StackContentWidth.swift"), "the scan finds the ladder: \(readers.map(\.name))")
        let unwired = readers.filter { Self.exempt[$0.name] == nil && !$0.code.contains("leases.beginComputation") }
            .map(\.name)
        #expect(unwired.isEmpty, "kept across frames, told stale by a size clear, and holding no observation lease")
    }
}
