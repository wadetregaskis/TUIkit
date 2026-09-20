//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimatedCellsModifier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

extension View {
    /// Declares that some of this view's cells animate, and hands the run loop
    /// the finished frames for them (see ``AnimatedCellRun``).
    ///
    /// The route out of "read the phase while rendering", for a view assembled
    /// by *composition* rather than by a `Renderable` core. A `Renderable` puts
    /// its runs straight onto the buffer it built; a view whose body is other
    /// views has no buffer of its own to put them on, so it declares them here
    /// and this modifier attaches them to whatever the body rendered to.
    ///
    /// Offsets are relative to this view's own top-left, and travel with it —
    /// padding, borders and stacks shift the runs along with the cells they
    /// describe.
    ///
    /// - Important: The runs must describe the cells the view actually drew, at
    ///   the step it drew them. The loop splices a run's current frame over the
    ///   frame on screen without consulting the view again, so a run in the
    ///   wrong place, or one frame too wide, repaints whatever is really there —
    ///   every tick, until something else forces a full render.
    ///
    /// - Note: This is the low-level route, and it requires the view to know
    ///   where its own cells are. When what animates is a colour something else
    ///   paints — a border, say — hand that modifier an ``AnimatedColor``
    ///   instead and let it place the runs.
    ///
    /// - Parameter runs: The animated spans, positioned within this view.
    /// - Returns: A view whose buffer carries those runs.
    public func animatedCells(_ runs: [AnimatedCellRun]) -> some View {
        AnimatedCellsModifier(content: self, runs: runs)
    }
}

/// Attaches ``AnimatedCellRun``s to the buffer its content renders to. See
/// ``View/animatedCells(_:)``.
///
/// Size-neutral: which cells animate never changes layout, so it measures as
/// `content`.
struct AnimatedCellsModifier<Content: View>: View {
    let content: Content
    let runs: [AnimatedCellRun]

    var body: Never {
        fatalError("AnimatedCellsModifier renders via Renderable")
    }
}

extension AnimatedCellsModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = TUIkitView.renderToBuffer(content, context: context)
        // A measure pass draws nothing, so a run left on it would describe cells
        // that were never on screen — and, worse, keep the clock alive from a
        // pass that produced no frame.
        guard !context.isMeasuring else { return buffer }
        buffer.animatedCells += runs
        return buffer
    }
}

extension AnimatedCellsModifier: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - Seeing Through the Wrapper

/// - Note: The runs are attached to whatever buffer the content rendered to, and
///   a member's buffer is its own — so each member animates its own cells,
///   which is what the same runs over one combined buffer did.
extension AnimatedCellsModifier: SingleContentWrapper {
    var wrappedContent: Content { content }

    func rewrapping<V: View>(_ view: V) -> any View {
        AnimatedCellsModifier<V>(content: view, runs: runs)
    }
}

/// Body deliberately empty: ``ChildViewProvider`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension AnimatedCellsModifier: ChildViewProvider where Content: ChildViewProvider {}

/// Body deliberately empty: ``GridRowProviding`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension AnimatedCellsModifier: GridRowProviding where Content: GridRowProviding {}
