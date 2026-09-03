//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LinkDisplayTests.swift
//
//  A link in a terminal cannot rely on being opened: `OpenURLAction` runs the
//  system opener on the machine the APP is on, which over ssh is the server,
//  and a terminal that honours OSC 8 opens a link only on a gesture it chooses
//  — which a keyboard user never makes. So the destination has to be something
//  the user can see and copy. `LinkDisplay` is the choice of how, and these
//  pin each mode's visible text plus the one rule `automatic` encodes.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Link display modes")
struct LinkDisplayTests {

    private let url = URL(string: "https://swift.org/documentation/")!

    private func rendered(_ view: some View, width: Int = 70) -> String {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: width, availableHeight: 4, environment: environment,
            tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        environment.focusManager?.beginRenderPass()
        defer {
            tui.stateStorage.endRenderPass()
            environment.focusManager?.endRenderPass()
        }
        return renderToBuffer(view, context: context).lines.first?.stripped ?? ""
    }

    private func link(_ display: LinkDisplay) -> some View {
        Link("language guide", destination: url).linkDisplay(display)
    }

    @Test("urlOnly replaces the label with the URL")
    func urlOnlyShowsTheURL() {
        #expect(rendered(link(.urlOnly)) == "https://swift.org/documentation/")
    }

    @Test("urlInParentheses keeps the label and appends the URL")
    func parenthesesShowsBoth() {
        #expect(rendered(link(.urlInParentheses)) == "language guide (https://swift.org/documentation/)")
    }

    @Test("popover shows the label alone")
    func popoverShowsTheLabel() {
        #expect(rendered(link(.popover)) == "language guide")
    }

    /// `automatic` is the label either way — the difference it makes is which
    /// FALLBACK applies, not what is drawn — so this pins the drawn form and
    /// the resolution rule separately.
    @Test("automatic shows the label alone")
    func automaticShowsTheLabel() {
        #expect(rendered(link(.automatic)) == "language guide")
    }

    /// The one rule `automatic` encodes: on a terminal that will not be sent
    /// an OSC 8 escape, a bare label says nothing about where it goes, so it
    /// falls back to the popover. On one that will, the escape carries the
    /// destination and the label stays clean.
    @Test("automatic falls back to popover exactly when OSC 8 is not sent")
    func automaticResolution() {
        #expect(LinkDisplay.automatic.resolved(hyperlinksSupported: true) == .automatic)
        #expect(LinkDisplay.automatic.resolved(hyperlinksSupported: false) == .popover)
    }

    /// Every other mode is already concrete and must not be re-decided by the
    /// terminal's capabilities — an app that asked for the URL inline gets it
    /// on a host that would have linkified the label anyway.
    @Test(
        "Explicit modes ignore the terminal's capabilities",
        arguments: [LinkDisplay.popover, .urlInParentheses, .urlOnly])
    func explicitModesAreNotResolved(_ display: LinkDisplay) {
        #expect(display.resolved(hyperlinksSupported: true) == display)
        #expect(display.resolved(hyperlinksSupported: false) == display)
    }

    /// A URL is content, not a localization key. Rendering one through
    /// `Text(_:)` would look it up and print the key on a miss — which for a
    /// URL is the URL, so the bug would be invisible until a table happened to
    /// contain one.
    @Test("A URL that looks like a key is still shown verbatim")
    func urlIsNotLocalized() {
        LocalizationService.shared.register(translations: [
            "en": ["https://swift.org/documentation/": "SOMETHING ELSE ENTIRELY"]
        ])
        #expect(rendered(link(.urlOnly)) == "https://swift.org/documentation/")
    }
}
