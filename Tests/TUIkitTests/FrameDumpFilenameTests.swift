//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FrameDumpFilenameTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

/// The debug frame dump's filename carried a locale-formatted date, and in
/// European Portuguese (and a handful of others) that date has `/` in it —
/// a directory separator, so the write targeted a directory that did not
/// exist and the dump silently never happened.
@MainActor
@Suite("Frame dump filename")
struct FrameDumpFilenameTests {

    @Test("The name is a fixed pattern in a fixed locale, with no separator in it")
    func nameIsLocaleIndependent() throws {
        let name = Terminal.frameDumpFilename(for: Date(timeIntervalSince1970: 1_788_000_000))
        #expect(!name.contains("/"))
        #expect(name.wholeMatch(of: /tuikit-frame \(\d{8}-\d{6}\)\.ansi/) != nil, "\(name)")
        let url = URL(fileURLWithPath: name)
        #expect(url.lastPathComponent == name, "every byte of the name is the file's own")
    }
}
