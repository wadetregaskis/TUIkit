//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollAnchorRoleTests.swift
//
//  `defaultScrollAnchor(_:for:)` — the two questions the unlabelled modifier
//  answers at once, asked separately.
//
//  The most important tests here are the NEGATIVE ones: the split must be
//  invisible to everything written before it. `Documentation/Scroll-anchoring.md`
//  §1.1's behaviour was iterated on at length and is not up for renegotiation,
//  so a role overload that changed it — even in a corner — would be a
//  regression wearing a feature's clothes.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("ScrollAnchorRole")
struct ScrollAnchorRoleTests {

    private static let viewport = 8

    /// Renders one frame of a `.bottom`-ish log through `configure`, which
    /// applies whatever anchoring the case under test is about.
    private func frame(
        items: [Int], tui: TUIContext, focusManager: FocusManager,
        configure: (AnyView) -> AnyView
    ) -> [Int] {
        let content = AnyView(
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items, id: \.self) { Text("row \($0)").frame(height: 1) }
                }
            }
            .frame(height: Self.viewport))

        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 30, availableHeight: Self.viewport,
            environment: environment, tuiContext: tui)

        tui.preferences.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        let buffer = renderToBuffer(configure(content), context: context)
        focusManager.endRenderPass()
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()

        return buffer.lines.compactMap { line in
            let text = line.stripped
            guard let marker = text.range(of: "row ") else { return nil }
            return Int(text[marker.upperBound...].prefix { $0.isNumber })
        }
    }

    /// Opens a log of 0..<40, settles, then appends 100..<105 — reporting the
    /// last row visible before and after.
    private func openThenAppend(_ configure: @escaping (AnyView) -> AnyView) -> (
        opened: Int?, afterAppend: Int?
    ) {
        let tui = TUIContext()
        let focusManager = FocusManager()
        var items = Array(0..<40)
        for _ in 0..<3 {
            _ = frame(items: items, tui: tui, focusManager: focusManager, configure: configure)
        }
        let opened = frame(
            items: items, tui: tui, focusManager: focusManager, configure: configure
        ).last
        items.append(contentsOf: 100..<105)
        let after = frame(
            items: items, tui: tui, focusManager: focusManager, configure: configure
        ).last
        return (opened, after)
    }

    // MARK: - The unlabelled form answers both (the control)

    /// Not a new behaviour — the shipped one, restated here so the two
    /// single-role cases below have something to differ from in the same
    /// harness rather than across files.
    @Test("Unlabelled .bottom opens at the tail AND follows appends")
    func unlabelledDoesBoth() {
        let result = openThenAppend { AnyView($0.defaultScrollAnchor(.bottom)) }
        #expect(result.opened == 39, "opened at the tail")
        #expect(result.afterAppend == 104, "and followed the new tail")
    }

    // MARK: - One role at a time

    /// "Join the log at the end, then leave me alone." Opens at the tail like
    /// the unlabelled form, and then does NOT chase appends — which is the
    /// whole point, and the thing there was no way to say before.
    @Test(".initialOffset opens at the tail and then stops following")
    func initialOffsetOpensThenReleases() {
        let result = openThenAppend {
            AnyView($0.defaultScrollAnchor(.bottom, for: .initialOffset))
        }
        #expect(result.opened == 39, "opened at the tail")
        // Not `== 39`: once there are rows below, the viewport spends a line on
        // the "N more below" indicator, so the last CONTENT row visible is one
        // earlier. The claim is that the view did not chase the new tail.
        #expect((result.afterAppend ?? 0) < 100, "stayed put as rows arrived: \(result)")
    }

    /// The mirror image, and the case that decided how the split is
    /// implemented. A `.sizeChanges` anchor must NOT place the opening frame —
    /// but the opening placement is not a separate step in this design, it is
    /// the follow rule's own first frame (an empty view is at its own bottom).
    /// So the opening frame has to consult the OPENING anchor, which here is
    /// unanchored.
    @Test(".sizeChanges does not place the opening frame")
    func sizeChangesLeavesTheOpeningFrameAlone() {
        let result = openThenAppend {
            AnyView($0.defaultScrollAnchor(.bottom, for: .sizeChanges))
        }
        #expect(result.opened != 39, "opened at the top, not the tail: \(result)")
    }

    // MARK: - Composition

    /// Both roles, stated separately, must compose — and in EITHER order. The
    /// environment resolves inside-out, so a `.sizeChanges` call that ASSIGNED
    /// "no opening anchor" would swallow an `.initialOffset` call further out
    /// in one of the two orders. It transforms instead, stating none only where
    /// none was stated, which is why both orders agree here.
    @Test("The two roles compose in either order", arguments: [false, true])
    func rolesComposeEitherOrder(initialFirst: Bool) {
        let result = openThenAppend { view in
            initialFirst
                ? AnyView(
                    view.defaultScrollAnchor(.bottom, for: .initialOffset)
                        .defaultScrollAnchor(nil, for: .sizeChanges))
                : AnyView(
                    view.defaultScrollAnchor(nil, for: .sizeChanges)
                        .defaultScrollAnchor(.bottom, for: .initialOffset))
        }
        #expect(result.opened == 39, "the opening anchor survived: \(result)")
        #expect((result.afterAppend ?? 0) < 100, "and the standing one is still none")
    }

    // MARK: - The split is inert for everything that predates it

    /// The public `\.defaultScrollAnchor` environment key predates the roles,
    /// and writing it directly — which the rest of the suite does, and an app
    /// may — must keep meaning what it always did: both roles.
    ///
    /// That is what the doubly-optional opening key buys. Were it a plain
    /// `UnitPoint?`, an unstated opening role would read as "no anchor" and
    /// every direct writer would silently stop opening at its edge.
    @Test("Writing the environment key directly still opens at the edge")
    func directEnvironmentWriteIsUnchanged() {
        let result = openThenAppend { view in
            AnyView(view.transformEnvironment(\.defaultScrollAnchor) { $0 = .bottom })
        }
        #expect(result.opened == 39, "opened at the tail: \(result)")
        #expect(result.afterAppend == 104, "and followed, exactly as before")
    }

    /// The same deferral one layer down, at the handler. A caller that sets
    /// only `declaredAnchorMode` — every test in `ListEdgeAnchorTests`, and any
    /// future one — must be unaffected, which is why the handler's opening mode
    /// is Optional rather than defaulting to `.window`.
    @Test("An unstated opening mode defers to the standing one")
    func governingDefersWhenUnstated() {
        #expect(
            ScrollAnchorMode.governing(opening: nil, standing: .bottom, hasOpened: false)
                == .bottom)
        #expect(
            ScrollAnchorMode.governing(opening: .window, standing: .bottom, hasOpened: false)
                == .window, "a STATED opening anchor is honoured")
        #expect(
            ScrollAnchorMode.governing(opening: .window, standing: .bottom, hasOpened: true)
                == .bottom, "and only governs the opening frame")
    }
}
