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

    /// Renders `view`, activates the auto-focused link with Enter, and renders
    /// again — the buffer that would carry a popover the activation raised.
    private func activated(_ view: some View) -> FrameBuffer {
        let tui = TUIContext()
        let manager = FocusManager()
        var environment = EnvironmentValues()
        environment.focusManager = manager
        environment.applyRuntimeServices(from: tui)
        environment.terminalWidth = 70
        environment.terminalHeight = 8
        environment.overlayContentHeight = 6
        let context = RenderContext(
            availableWidth: 70, availableHeight: 8, environment: environment, tuiContext: tui)
        func pass(_ body: () -> Void) {
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            manager.beginRenderPass()
            body()
            tui.stateStorage.endRenderPass()
            manager.endRenderPass()
        }
        pass {
            _ = renderToBuffer(view, context: context)
            _ = manager.dispatchKeyEvent(KeyEvent(key: .enter))
        }
        var result = FrameBuffer()
        pass { result = renderToBuffer(view, context: context) }
        return result
    }

    /// A presented popover grabs the keyboard until Escape. In the two URL
    /// modes the destination is already on the row, so the popover repeated
    /// it — and took the arrow keys — for nothing.
    @Test("Only the popover mode raises a popover; the URL modes already show the destination")
    func onlyPopoverModePresents() {
        let link = Link("Docs", destination: url).environment(\.openURL, OpenURLAction { _ in })
        #expect(!activated(link.linkDisplay(.popover)).overlays.isEmpty)
        #expect(activated(link.linkDisplay(.urlOnly)).overlays.isEmpty)
        #expect(activated(link.linkDisplay(.urlInParentheses)).overlays.isEmpty)
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

    /// `.popover` is the default, and the default is what an app that writes
    /// `Link(...)` and nothing else gets. There is no `automatic` beside it:
    /// a case that resolved to "clean label plus OSC 8" on one host and to
    /// this on another was the same thing twice — the label is identical, the
    /// escape is emitted either way, and the popover is needed either way
    /// because no terminal gesture reaches the keyboard.
    @Test("popover is the default")
    func popoverIsTheDefault() {
        #expect(EnvironmentValues().linkDisplay == .popover)
        #expect(rendered(Link("language guide", destination: url)) == "language guide")
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
