//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ModalBackdropStateTests.swift
//
//  What a presented modal does to the page BENEATH it. Like
//  `ListReorderResumeTests`, these renders drive `StateStorage`'s pass
//  boundaries the way the run loop does — without that bracketing the prune
//  never runs and the whole question under test is invisible, which is exactly
//  why `ModalFocusRestorationTests` (focus pass only) could pass while the
//  page's `@State` was being thrown away underneath it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// The page under the modal. Its counter is `@State`, deliberately: the
/// backdrop renders through an isolated context, and the question is whether
/// the REAL storage still holds this box afterwards.
private struct CounterPage: View {
    @State private var count = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("count=\(count)")
            Button("Bump") { count += 1 }.focusID("bump")
        }
    }
}

@MainActor
@Suite("Modal backdrop: the page's state")
struct ModalBackdropStateTests {

    private final class BoolBox {
        var v = false
        var binding: Binding<Bool> { Binding(get: { self.v }, set: { self.v = $0 }) }
    }

    /// A frame with the real pass bracketing: `StateStorage.endRenderPass()`
    /// prunes every entry whose identity was not marked active during the
    /// pass, so a subtree rendered into a THROWAWAY storage looks departed to
    /// the real one.
    private func render(
        _ view: some View, tui: TUIContext, fm: FocusManager
    ) -> [String] {
        var env = EnvironmentValues()
        env.focusManager = fm
        env.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 24, availableHeight: 10, environment: env, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        fm.beginRenderPass()
        let lines = renderToBuffer(view, context: context).lines.map(\.stripped)
        fm.endRenderPass()
        tui.stateStorage.endRenderPass()
        return lines
    }

    private func countLine(_ lines: [String]) -> String? {
        lines.first { $0.contains("count=") }?.trimmingCharacters(in: .whitespaces)
    }

    /// The headline: a page's `@State` must survive being the backdrop.
    ///
    /// The backdrop renders through `isolatedForBackground()`, whose throwaway
    /// `StateStorage` is what keeps the page's scroll position from being
    /// overwritten by the auto-focus reveal. But the real storage never sees
    /// those identities marked active, so its own entries for the whole
    /// subtree were pruned at the end of the first presented frame — the page
    /// came back re-hydrated to its defaults. Focus memory + the reveal made
    /// this LOOK fine for scroll position, which is why it survived the
    /// earlier round of modal fixes.
    @Test("The page's @State survives being the backdrop of a presented modal")
    func pageStateSurvivesPresentation() {
        let presented = BoolBox()
        let tui = TUIContext()
        let fm = FocusManager()
        let view = CounterPage().modal(isPresented: presented.binding) { Text("THEMODAL") }

        _ = render(view, tui: tui, fm: fm)
        // Move the counter off its default so a re-hydration is detectable.
        fm.focus(id: "bump")
        _ = render(view, tui: tui, fm: fm)
        _ = fm.dispatchKeyEvent(KeyEvent(key: .enter))
        let bumped = render(view, tui: tui, fm: fm)
        #expect(countLine(bumped) == "count=8", "the bump landed: \(bumped)")

        presented.v = true
        let overlaid = render(view, tui: tui, fm: fm)
        #expect(
            overlaid.contains { $0.contains("THEMODAL") } || !overlaid.isEmpty,
            "the modal frame rendered")

        presented.v = false
        let dismissed = render(view, tui: tui, fm: fm)
        #expect(
            countLine(dismissed) == "count=8",
            "the page came back with its state, not re-hydrated to the default: \(dismissed)")
    }

    /// The same prune, seen from the other side: while presented, the backdrop
    /// itself must show the page's CURRENT state. Rendering it against empty
    /// storage drew the page at its defaults behind the dim.
    @Test("The dimmed backdrop shows the page's current state, not its defaults")
    func backdropShowsCurrentState() {
        let presented = BoolBox()
        let tui = TUIContext()
        let fm = FocusManager()
        let view = CounterPage().modal(isPresented: presented.binding) { Text("THEMODAL") }

        _ = render(view, tui: tui, fm: fm)
        fm.focus(id: "bump")
        _ = render(view, tui: tui, fm: fm)
        _ = fm.dispatchKeyEvent(KeyEvent(key: .enter))
        _ = render(view, tui: tui, fm: fm)

        presented.v = true
        let overlaid = render(view, tui: tui, fm: fm)
        #expect(
            countLine(overlaid) == "count=8",
            "the backdrop draws the page as it is, not as it started: \(overlaid)")
    }
}
