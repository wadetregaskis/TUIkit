//  🖥️ TUIKit — Terminal UI Kit for Swift
//  NavigationSplitViewResizeDisableTests.swift
//
//  A split view is resizable by default — including under a size-to-fit style,
//  where the columns fit their content until the user drags/keys one, which pins
//  it. `navigationSplitViewResizable(false)` is the only thing that removes the
//  divider grip and its focus section, whatever the style.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("NavigationSplitView resize-disabled dividers")
struct NavigationSplitViewResizeDisableTests {

    private func resizeContext(width: Int = 80, height: Int = 12) -> RenderContext {
        let tui = TUIContext()
        var env = EnvironmentValues()
        env.focusManager = FocusManager()
        return RenderContext(
            availableWidth: width, availableHeight: height, environment: env, tuiContext: tui)
    }

    /// The visible column of the divider grip (a `◦` dot) on the centre row,
    /// or nil when no grip is drawn.
    private func gripX(_ buffer: FrameBuffer) -> Int? {
        guard buffer.height > 0 else { return nil }
        let mid = buffer.lines[buffer.height / 2].stripped
        guard let r = mid.firstIndex(of: "◦") else { return nil }
        return mid.distance(from: mid.startIndex, to: r)
    }

    /// Two resizable splits in one frame each own their divider. The section id
    /// was keyed on the divider INDEX alone, so both registered into one shared
    /// "nav-split-divider-0": focusing either made both look focused, and the
    /// section's cycling walked the other split's handle. Every other
    /// per-instance section (`modal-`, `alert-`, `contextmenu-`) namespaces
    /// itself with the identity path; this one now does too.
    @Test("Two splits in one frame get distinct divider sections")
    func siblingSplitsDoNotShareADividerSection() {
        let context = resizeContext(width: 120)
        let fm = context.environment.focusManager!
        let view = HStack {
            NavigationSplitView { Text("A-SIDE") } detail: { Text("A-DETAIL") }
            NavigationSplitView { Text("B-SIDE") } detail: { Text("B-DETAIL") }
        }

        _ = renderToBuffer(view, context: context)

        let dividerSections = fm.sectionIDs.filter { $0.hasPrefix("nav-split-divider-0") }
        #expect(
            dividerSections.count == 2,
            "each split registers its own divider section, got \(dividerSections)")
        #expect(Set(dividerSections).count == 2, "…under distinct ids")
    }

    @Test("A size-to-fit style is resizable: it keeps its handle and focus section")
    func sizeToFitIsResizable() {
        // Size-to-fit fits the columns to content, but a drag/keyboard resize
        // pins a column so the user can still tune the layout — so the divider
        // draws its grip and registers a focus section like any resizable split.
        let context = resizeContext()
        let fm = context.environment.focusManager!
        let view = NavigationSplitView { Text("SIDEBAR") } detail: { Text("DETAIL") }
            .navigationSplitViewStyle(.sizeToFitFromLeft)

        let buffer = renderToBuffer(view, context: context)
        #expect(gripX(buffer) != nil, "size-to-fit draws its resize grip")
        #expect(
            fm.section(withPrefix: "nav-split-divider-0") != nil,
            "size-to-fit registers a divider focus section")
    }

    @Test("resizable(false) removes the divider even under a size-to-fit style")
    func resizableFalseDisablesSizeToFitDivider() {
        let context = resizeContext()
        let fm = context.environment.focusManager!
        let view = NavigationSplitView { Text("SIDEBAR") } detail: { Text("DETAIL") }
            .navigationSplitViewStyle(.sizeToFitFromLeft)
            .navigationSplitViewResizable(false)

        let buffer = renderToBuffer(view, context: context)
        #expect(gripX(buffer) == nil, "resizable(false) draws no grip under size-to-fit")
        #expect(
            fm.section(withPrefix: "nav-split-divider-0") == nil,
            "resizable(false) registers no divider focus section under size-to-fit")
    }

    @Test("The default (proportional) style keeps its resize handle and focus section")
    func proportionalStyleStillResizable() {
        // Guard the gate is scoped to size-to-fit: the balanced/proportional
        // style must still expose a draggable, focusable divider.
        let context = resizeContext()
        let fm = context.environment.focusManager!
        let view = NavigationSplitView { Text("SIDEBAR") } detail: { Text("DETAIL") }
            .navigationSplitViewStyle(.balanced)

        let buffer = renderToBuffer(view, context: context)
        #expect(gripX(buffer) != nil, "a resizable split draws its grip handle")
        #expect(
            fm.section(withPrefix: "nav-split-divider-0") != nil,
            "a resizable split registers a divider focus section")
    }

    @Test("navigationSplitViewResizable(false) disables a resizable style's divider")
    func resizableFalseDisablesBalancedDivider() {
        // The DIRECT modifier, not the style gate: .balanced is resizable by
        // default, so the modifier alone must remove the grip and the focus
        // section — and flipping it back to true must restore both.
        let offContext = resizeContext()
        let offFM = offContext.environment.focusManager!
        let off = NavigationSplitView { Text("SIDEBAR") } detail: { Text("DETAIL") }
            .navigationSplitViewStyle(.balanced)
            .navigationSplitViewResizable(false)
        let offBuffer = renderToBuffer(off, context: offContext)
        #expect(gripX(offBuffer) == nil, "resizable(false) draws no grip handle")
        #expect(
            offFM.section(withPrefix: "nav-split-divider-0") == nil,
            "resizable(false) registers no divider focus section")

        let onContext = resizeContext()
        let onFM = onContext.environment.focusManager!
        let on = NavigationSplitView { Text("SIDEBAR") } detail: { Text("DETAIL") }
            .navigationSplitViewStyle(.balanced)
            .navigationSplitViewResizable(true)
        let onBuffer = renderToBuffer(on, context: onContext)
        #expect(gripX(onBuffer) != nil, "resizable(true) restores the grip handle")
        #expect(
            onFM.section(withPrefix: "nav-split-divider-0") != nil,
            "resizable(true) restores the divider focus section")
    }
}

/// The persisted column-width store's pin + reset semantics, which are what let
/// a size-to-fit split honour a manual resize and then release it on a token
/// change (`.navigationSplitViewColumnWidthReset`).
@MainActor
@Suite("SplitViewWidths pinning + reset")
struct SplitViewWidthsTests {
    @Test("A user resize pins the width; a clamped write-back keeps it pinned")
    func userResizePins() {
        let widths = SplitViewWidths()
        #expect(widths.isUserSet(0) == false)
        widths.set(30, for: 0)
        #expect(widths.isUserSet(0) == true)
        #expect(widths.value(for: 0) == 30)
        // The per-frame clamp write-back updates the width without un-pinning.
        widths.setClamped(28, for: 0)
        #expect(widths.isUserSet(0) == true, "a clamped write-back does not un-pin")
        #expect(widths.value(for: 0) == 28)
    }

    @Test("The reset token releases pins only when it changes; the first is recorded")
    func resetTokenReleasesOnChange() {
        let widths = SplitViewWidths()
        widths.set(30, for: 0)
        // First observation of any token records it WITHOUT resetting, so a stable
        // token applied on every render never wipes a resize the user just made.
        widths.applyResetToken(AnyHashable(0))
        #expect(widths.isUserSet(0) == true, "the first token seen never resets")
        widths.applyResetToken(AnyHashable(0))
        #expect(widths.isUserSet(0) == true, "the same token again still doesn't reset")
        // A changed token releases every pin, so the columns re-flow to defaults.
        widths.applyResetToken(AnyHashable(1))
        #expect(widths.isUserSet(0) == false, "a changed token releases the pin")
        #expect(widths.value(for: 0) == nil)
    }

    @Test("A constant (nil) token stream never resets")
    func nilTokenNeverResets() {
        let widths = SplitViewWidths()
        widths.set(30, for: 0)
        widths.applyResetToken(nil)
        widths.applyResetToken(nil)
        #expect(widths.isUserSet(0) == true, "no reset modifier (nil token) never releases a pin")
    }
}
