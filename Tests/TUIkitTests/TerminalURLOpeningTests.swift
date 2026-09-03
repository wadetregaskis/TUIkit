//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalURLOpeningTests.swift
//
//  `OpenURLAction`'s system opener runs on the machine the APPLICATION is on.
//  Over ssh that is the server: either headless, where the launch is a silent
//  no-op, or somebody's desktop, where the URL lands in front of a person who
//  did not ask for it. The framework cannot tell which — `SSH_*` is reliable
//  when present and proves nothing when absent, and a multiplexer session
//  outlives the hop that started it — so it declines by default.
//
//  These pin the default and the two ways of changing it. They cannot assert
//  what a browser did, so they assert the DECISION, which is the whole of what
//  this code contributes.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

@MainActor
@Suite("Opening a URL is off unless something says this machine is the user's", .serialized)
struct TerminalURLOpeningTests {

    /// Leaves the override as it found it — it is process-wide, and a test
    /// that set it would otherwise decide the answer for every test after it.
    private func withOverride(_ value: Bool?, _ body: () -> Void) {
        let saved = TerminalClient.urlOpeningSupport
        TerminalClient.urlOpeningSupport = value
        defer {
            TerminalClient.urlOpeningSupport = saved
            TerminalClient.applyURLOpeningSupport()
        }
        body()
    }

    @Test("The default is off")
    func defaultIsOff() {
        withOverride(nil) {
            #expect(!TerminalClient.urlOpeningEnabled)
        }
    }

    @Test("An app can turn it on, and off again")
    func overrideWins() {
        withOverride(true) { #expect(TerminalClient.urlOpeningEnabled) }
        withOverride(false) { #expect(!TerminalClient.urlOpeningEnabled) }
    }

    /// The published flag is what the activation path actually reads — it is
    /// `nonisolated`, because that path has no actor — so setting the override
    /// and not publishing it would change nothing where it counts.
    @Test("Setting the override publishes it to the path that reads it")
    func overridePublishes() {
        withOverride(true) {
            #expect(TerminalURLOpening.isEnabled)
        }
        withOverride(false) {
            #expect(!TerminalURLOpening.isEnabled)
        }
    }

    /// A handler that does the work itself is NOT gated. What is gated is only
    /// the framework launching a process on the user's behalf; an app that
    /// knows how it wants to open a URL was never the risk.
    @Test("A handler that handles the URL itself still runs")
    func customHandlerIsNotGated() {
        withOverride(false) {
            let sink = OpenedURL()
            let action = OpenURLAction { sink.url = $0 }
            action(URL(string: "https://swift.org")!)
            #expect(sink.url?.absoluteString == "https://swift.org")
        }
    }

    private final class OpenedURL: @unchecked Sendable {
        var url: URL?
    }
}
