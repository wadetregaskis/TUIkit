//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContentWidthTestSupport.swift
//
//  The fixtures `ContentWidthChallengeTests` and `ContentWidthNaturalAskTests`
//  share: boxes a row's closure reads besides its element, a two-axis
//  `ScrollView` driven frame after frame the way the render loop drives it, and
//  the content-width ladder asked directly.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// What a row's closure reads besides its element — a units toggle, a "show
/// details" — so a test can change what rows draw without changing their data.
@MainActor
final class WidthBox {
    var cells: Int
    init(cells: Int) { self.cells = cells }
}

/// A two-axis `ScrollView` over a `LazyVStack` — or, `eager`, a `VStack` — of
/// `rows()` rows, scrolled to its end when `atBottom`, driven frame after
/// frame through ONE cache as the render loop drives it — pass tracker and
/// all — returning each
/// frame's bottom line — the horizontal bar, when there is one — with its
/// styling, which is where the thumb is: stripped, a bar is its two arrows and
/// blanks. The view is rebuilt each frame, as a body is, so a count read from a
/// box is a collection that grows.
@MainActor
func twoAxisFrames<Row: View>(
    tuiContext: TUIContext, rows: @escaping () -> Int = { 400 }, width: Int = 40,
    eager: Bool = false, atBottom: Bool = false, row: @escaping (Int) -> Row
) -> () -> String {
    {
        let scroll = ScrollView([.horizontal, .vertical]) {
            if eager {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<rows(), id: \.self) { index in row(index) }
                }
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<rows(), id: \.self) { index in row(index) }
                }
            }
        }
        let view = atBottom ? AnyView(scroll.defaultScrollAnchor(.bottom)) : AnyView(scroll)
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        // What `RenderLoop.renderContent` installs every frame, and what turns
        // on the per-pass measure memo; without it that half of the cache is
        // never exercised at all.
        environment.installVolatileReadTracker(VolatileReadTracker())
        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        let buffer = renderToBuffer(
            view,
            context: RenderContext(
                availableWidth: width, availableHeight: 12,
                environment: environment, tuiContext: tuiContext))
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return buffer.lines.last ?? ""
    }
}

/// The content-width ladder asked directly, one width at a time, as the
/// horizontal probe asks it: under the ideal-width mark with no proposal, and
/// classified by `contentWidthAsk` as the arms classify it. So an ask at a
/// rung is `.probe` and may walk, and an ask of 40 is a probe under a real
/// bound — `.serve` — which may read the kept answer but never start a walk. One
/// `StackWindowState` across every ask, so the record carries from one to the
/// next as it does in a frame. One pass tracker and no `beginRenderPass()`
/// between asks, so every ask is in ONE pass, as a frame's rungs and probes
/// are: the per-pass measure memo is on, and nothing prunes either table. `underInvalidatedMemo`
/// asks from beneath a container that called `invalidatingMeasureMemo()`, whose
/// per-pass entries are keyed differently.
@MainActor
func contentWidthAsks<Row: View>(
    tuiContext: TUIContext, rows: @escaping () -> Int = { 400 },
    underInvalidatedMemo: Bool = false, row: @escaping (Int) -> Row
) -> (Int) -> Int? {
    let state = StackWindowState()
    let pass = VolatileReadTracker()
    return { limit in
        // `content: row`, not a closure around it: a row's per-pass memo key
        // includes the row VALUE, which holds its builder, so one builder for
        // every ask is what lets the asks share one pass the way a frame's
        // rungs and probes do.
        let stack = _VStackCore(
            alignment: .leading, spacing: 0, overflow: .window,
            content: ForEach(0..<rows(), id: \.self, content: row))
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        environment.installVolatileReadTracker(pass)
        // Under the horizontal probe's own mark, as `measureNaturalExtent`
        // asks; the production classifier then decides what the ask may do.
        var context = RenderContext(
            availableWidth: limit, availableHeight: 4_096,
            environment: environment, tuiContext: tuiContext
        ).askingIdealWidth()
        if underInvalidatedMemo { context = context.invalidatingMeasureMemo() }
        let children = resolveChildViewCollection(from: stack.content, context: context)
        let proposal = ProposedSize(width: nil, height: nil)
        return stack.contentWidthOverAllRows(
            children, widthLimit: limit,
            ask: context.contentWidthAsk(proposal: proposal, widthLimit: limit, heightLimit: 4_096),
            state: state, context: context)?.width
    }
}

/// `cells` cells of text that CAN wrap — a word every seven — or that cannot.
/// The difference is the whole of one bug: under a narrower proposal the first
/// reports its wrapped width, a few cells under the proposal, and the second
/// reports exactly the proposal. (Seven, because a word that divides the
/// proposal — five into forty — wraps to exactly the proposal and hides it.)
func wideText(_ cells: Int, breakable: Bool) -> String {
    guard breakable else { return String(repeating: "0", count: cells) }
    return String((0..<cells).map { $0 % 7 == 6 && $0 != cells - 1 ? " " : "a" })
}

/// Whether a row is mid-animation, in the only sense the content width can see:
/// its measure declares a side effect, so nothing it measures may be kept.
@MainActor
final class MovingFlag {
    var value = false
}
