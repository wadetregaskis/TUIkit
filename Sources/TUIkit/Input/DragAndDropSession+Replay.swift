//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DragAndDropSession+Replay.swift
//
//  The drag session's three per-frame registries, made replayable through
//  the render cache's effect journal — the way `2009214b` made the mouse
//  dispatcher's handler table and its feature requests replayable.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Registrar

/// The drag-and-drop registrations a render walk makes, shared by the live
/// render and by a value memo replaying them — the sibling of
/// `MouseHandlerRegistrar`, and there for the same reason.
///
/// ``DragAndDropSession/beginFrame()`` empties `targets`, `autoScrollZones`
/// and `reorderHosts` before every walk and the view tree refills them as it
/// renders, so each one is per-frame state exactly as the handler table is. A
/// subtree served from a value memo does not render, so it used to refill
/// nothing: the stored buffer still carried the region, the handler behind it
/// was refiled from the journal under the id the region names — and the
/// registry the drop resolves that id against was empty. The row looked alive
/// and accepted nothing, which no comparison of rendered lines can see.
enum DragAndDropRegistrar {
    /// The journal kind of a drop-destination registration.
    static let targetKind = EffectJournal.Kind("dropTarget")

    /// The journal kind of a drag auto-scroll zone registration.
    static let autoScrollKind = EffectJournal.Kind("dragAutoScrollZone")

    /// The journal kind of a row-reorder host registration.
    static let reorderHostKind = EffectJournal.Kind("dragReorderHost")

    /// Declares the registration being made replayable, and returns the
    /// journal to record it in — or `nil` when nothing is recording, so a
    /// caller builds its replay closure only when something will keep it and
    /// the live path allocates nothing extra.
    ///
    /// A measure pass has nothing to declare and nothing to replay: it renders
    /// for sizing only, the controls that register suppress themselves while it
    /// runs, and no frame is ever served from its buffer.
    @MainActor
    static func declareReplayable(in context: RenderContext) -> EffectJournal? {
        guard !context.isMeasuring else { return nil }
        context.environment.volatileReadTracker?.recordReplayableEffect()
        return context.recordingEffectJournal
    }
}

// MARK: - Registering From a Render Walk

extension DragAndDropSession {
    /// Registers a drop destination for the view `context` is rendering, and —
    /// while a value memo records — records the registration so a hit can make
    /// it again.
    ///
    /// The entry point for every drop target a render walk registers;
    /// ``registerTarget(_:)`` is the bare form, for the session's own machinery
    /// and the tests that drive it directly.
    ///
    /// The replay looks the session up from the context it is run against
    /// rather than capturing this one, as every journalled effect does: a hit's
    /// context belongs to a later frame.
    @MainActor
    func registerTarget(_ target: Target, in context: RenderContext) {
        registerTarget(target)
        guard let journal = DragAndDropRegistrar.declareReplayable(in: context) else { return }
        journal.append(
            EffectJournal.Entry(
                kind: DragAndDropRegistrar.targetKind,
                channelToken: context.environment.keyChannelToken
            ) { replay in
                replay.environment.dragAndDropSession?.registerTarget(target)
            })
    }

    /// Registers a scrollable's auto-scroll zone for the view `context` is
    /// rendering, recorded for replay in the same way and for the same reason.
    ///
    /// A served scrollable that stopped registering its zone is a drag that
    /// will not scroll to reach what is off screen — silently, since the
    /// viewport looks exactly as it did.
    ///
    /// The zone is stamped with the scrollable's pictures here, so every zone a
    /// render walk registers reports the ticks that move it.
    @MainActor
    func registerAutoScrollZone(_ zone: AutoScrollZone, in context: RenderContext) {
        var zone = zone
        zone.drawing = HandlerDrawing(context)
        registerAutoScrollZone(zone)
        guard let journal = DragAndDropRegistrar.declareReplayable(in: context) else { return }
        journal.append(
            EffectJournal.Entry(
                kind: DragAndDropRegistrar.autoScrollKind,
                channelToken: context.environment.keyChannelToken
            ) { replay in
                replay.environment.dragAndDropSession?.registerAutoScrollZone(zone)
            })
    }

    /// Registers a control as this frame's home for reorders of its rows, the
    /// registration recorded for replay in the same way.
    ///
    /// The handover a bare ``registerReorderHost(_:)`` performs happens on the
    /// replay too, which is the point: a served `List` is the list on screen,
    /// and a gesture that has come back to it has to be handed over on the
    /// frame it returns rather than on whichever later frame something finally
    /// forces a render.
    @MainActor
    func registerReorderHost(_ host: ReorderHost, in context: RenderContext) {
        registerReorderHost(host)
        guard let journal = DragAndDropRegistrar.declareReplayable(in: context) else { return }
        journal.append(
            EffectJournal.Entry(
                kind: DragAndDropRegistrar.reorderHostKind,
                channelToken: context.environment.keyChannelToken
            ) { replay in
                replay.environment.dragAndDropSession?.registerReorderHost(host)
            })
    }
}
