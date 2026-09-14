//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DiagnosticChannelTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitCore

/// Pins the file half of the channel every framework diagnostic reports through.
/// The stderr half is pinned where it is used, by an exit test that reads the
/// child's stderr (`BodyMutationDiagnosticTests`).
@Suite("Diagnostic channel")
struct DiagnosticChannelTests {

    @Test("A named file is created by the first report and appended to by the next")
    func fileIsCreatedThenAppended() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("tuikit-diagnostic-channel-\(UUID().uuidString).log").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(!FileManager.default.fileExists(atPath: path))

        DiagnosticChannel.emit("first\n", to: path)
        DiagnosticChannel.emit("second\n", to: path)

        let written = try String(contentsOfFile: path, encoding: .utf8)
        #expect(written == "first\nsecond\n")
    }
}
