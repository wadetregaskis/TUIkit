//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MouseHandlerIDTable.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Mouse Handler ID Table

/// Where a mouse handler's id comes from: interned per `(identity, slot)`, so
/// the id belongs to the control rather than to its place in the walk.
///
/// The dispatcher used to hand out 0, 1, 2 … in registration order and restart
/// at 0 for the next walk, which made an id a *position*. One control ahead of
/// another going quiet renumbered everything below it, so anything that held an
/// id across a frame — a drop target, a drag zone, the auto-scroll driver
/// resolving a zone's rectangle — named whatever control had inherited the
/// number. The hover machine had to work around it explicitly
/// (`reconcileHoverAfterReshape`), and a two-walk frame shifted every id.
///
/// ## The key
///
/// The identity is the registering view's, and the slot is that registration's
/// ORDINAL at that identity within the walk: the first handler an identity
/// registers takes slot 0, the second slot 1. Nothing is hand-numbered, which
/// is the point — two sibling `Renderable`s can share one identity (a
/// `Renderable` adds no child identity of its own), and a container that
/// registers a handler per row registers them all at its own. Ordinals keep
/// those distinct by construction, where hand-picked constants would have to
/// agree across files to avoid handing two controls one id.
///
/// The counters restart with each walk, which is why ``beginWalk()`` exists:
/// `RenderLoop` may walk the scene more than once per frame, and without the
/// restart the second walk would mint a second id for every control.
///
/// ## Lifetime
///
/// Ids are never recycled — the mint only ever counts up — so an id that is
/// still held somewhere can go stale but can never come to mean a different
/// control. What the table holds is dropped by ``pruneInternedIDs(retaining:)``,
/// which the render cache calls with its own retention rule, because a cached
/// buffer carries its hit-test regions with their ids baked in.
final class MouseHandlerIDTable {

    /// One interned id and when it was last asked for.
    private struct Record {
        let id: HitTestRegion.HandlerID
        /// The ``pruneSerial`` in force when a walk last asked for this id.
        var askedAt: UInt64
    }

    /// A control's registration: which view, and which of that view's handlers.
    private struct Key: Hashable {
        let identity: ViewIdentity
        let slot: Int
    }

    /// The id minted for each `(identity, slot)`.
    private var interned: [Key: Record] = [:]

    /// How many handlers each identity has registered so far in THIS walk, so
    /// the next one takes the next slot. Emptied by ``beginWalk()``.
    private var slotsUsed: [ViewIdentity: Int] = [:]

    /// The next raw id to mint. Monotonic for the life of the dispatcher: an id
    /// is never handed out twice, so a stale one resolves to nothing rather
    /// than to someone else.
    private var nextRaw: UInt64 = 0

    /// Bumped by each prune, so a record can say whether this round asked for
    /// it without a second pass to clear flags.
    private var pruneSerial: UInt64 = 0

    /// How many ids are interned — for the tests that pin the pruning.
    var count: Int { interned.count }

    /// Mints an id that names no control.
    ///
    /// For a registration with no view identity to intern against: a test
    /// driving the dispatcher directly, and the measure pass exclusion below.
    func freshID() -> HitTestRegion.HandlerID {
        defer { nextRaw &+= 1 }
        return HitTestRegion.HandlerID(nextRaw)
    }

    /// The id for the next handler `context`'s view registers.
    ///
    /// Two calls from one identity within a walk are two slots, and the same
    /// two calls on the next frame get the same two ids back.
    func id(registeredIn context: RenderContext) -> HitTestRegion.HandlerID {
        // A measure pass renders content only for sizing, and the controls that
        // emit regions suppress them while it does. One that registered anyway
        // would consume the slot the render walk is about to ask for and shift
        // every id below it, so it gets an id that names nothing instead.
        guard !context.isMeasuring else { return freshID() }
        let identity = context.identity
        let slot = slotsUsed[identity, default: 0]
        slotsUsed[identity] = slot + 1
        let key = Key(identity: identity, slot: slot)
        if let existing = interned[key] {
            interned[key] = Record(id: existing.id, askedAt: pruneSerial)
            return existing.id
        }
        let id = freshID()
        interned[key] = Record(id: id, askedAt: pruneSerial)
        return id
    }

    /// Restarts the per-identity slot counters for a new walk of the scene.
    ///
    /// The interned ids themselves survive: that is the whole point of them.
    func beginWalk() {
        slotsUsed.removeAll(keepingCapacity: true)
    }
}

// MARK: - Pruning

extension MouseHandlerIDTable {
    /// Drops the ids no walk asked for since the last prune and that no cached
    /// subtree still covers.
    ///
    /// - Parameter isRetained: The render cache's question — whether a stored
    ///   entry above this identity was served this pass, so nothing below it was
    ///   visited and it registered nothing, yet its buffer (and the ids in its
    ///   regions) is still what the frame drew.
    func pruneInternedIDs(retaining isRetained: (ViewIdentity) -> Bool) {
        let serial = pruneSerial
        // Collect then remove: mutating a dictionary inside its own `for` loop
        // copies the whole table on the first removal.
        var stale: [Key] = []
        for (key, record) in interned
        where record.askedAt != serial && !isRetained(key.identity) {
            stale.append(key)
        }
        for key in stale { interned.removeValue(forKey: key) }
        pruneSerial &+= 1
    }
}

// MARK: - Registering With an Interned ID

extension MouseEventDispatcher: InternedIDTable {
    /// The render cache's end-of-pass prune, forwarded to the table.
    func pruneInternedIDs(retaining isRetained: (ViewIdentity) -> Bool) {
        handlerIDs.pruneInternedIDs(retaining: isRetained)
    }
}

extension MouseEventDispatcher {
    /// Registers a handler for the control `context` is rendering, under that
    /// control's own id.
    ///
    /// The entry point for everything a render walk registers; the id is
    /// interned per `(identity, slot)` — see ``MouseHandlerIDTable``.
    ///
    /// The handler table is emptied before every walk, so a control served from
    /// a value memo would leave the region in its stored buffer naming nothing
    /// — a `Button` still on screen that no click could reach. Registering again
    /// is all it takes, so this declares a REPLAYABLE effect and records the
    /// registration in the effect journal while a memo is recording; every hit
    /// files the same closure under the same id, at the point in the walk where
    /// the control would have rendered. See ``MouseHandlerRegistrar``.
    @MainActor
    func register(
        in context: RenderContext, _ handler: @escaping (MouseEvent) -> Bool
    ) -> HitTestRegion.HandlerID {
        registerInterned(handler, isHoverObserver: false, in: context)
    }

    /// Registers `handler`, with the pointer's enter/exit tracked into
    /// `hoverBox` first.
    ///
    /// Every control that lifts under the pointer opened its handler with the
    /// same six lines, and three of them had their own copy: `Button`,
    /// `_ToggleCore` and the text-field handler. Hover is one behaviour — the
    /// pointer is over the control or it is not — so a change to what that
    /// means should land once rather than three times, and a fourth control
    /// should get it by asking rather than by remembering.
    ///
    /// Both phases are consumed, as all three copies did: a synthetic
    /// enter/exit belongs to whichever region the dispatcher resolved it
    /// against, and passing it on would offer it to the control underneath.
    @MainActor
    func register(
        in context: RenderContext, hoverBox: StateBox<Bool>,
        _ handler: @escaping (MouseEvent) -> Bool
    ) -> HitTestRegion.HandlerID {
        register(in: context) { event in
            switch event.phase {
            case .entered:
                hoverBox.value = true
                return true
            case .exited:
                hoverBox.value = false
                return true
            default:
                return handler(event)
            }
        }
    }

    /// Registers `handler` for a control that draws part of ITSELF from state
    /// the event can move, and reports each event that moves what `drawn`
    /// reads to the render cache (``HandlerDrawing``).
    ///
    /// For the scrollables: the wheel scrolls one that does not hold the focus,
    /// and the pointer lifts its scrollbar's cells, and neither is a `@State`
    /// write. The `ForEach` row around such a scrollable is stored, and without
    /// the report it was served at the offset and in the colours it was stored
    /// with. One registration path, so the next handler a scrollable grows gets
    /// the report by asking for it — as a resizable view's edges did, for the
    /// grip the pointer lights.
    ///
    /// Only while a value memo records, because only then can anything
    /// containing this registration be stored: a memo stores only what it
    /// records as it renders, and one that is served makes again the
    /// registration it recorded — the reporting one — rather than this. A
    /// scrollable no memo holds, which is where one usually is, registers its
    /// handler bare: each wheel tick that moved it walked the whole cache for
    /// buffers that could not exist.
    @MainActor
    func register<Drawn: Equatable>(
        in context: RenderContext, reportingChangesTo drawn: @escaping () -> Drawn,
        _ handler: @escaping (MouseEvent) -> Bool
    ) -> HitTestRegion.HandlerID {
        guard context.recordingEffectJournal != nil else { return register(in: context, handler) }
        let drawing = HandlerDrawing(context)
        return register(in: context) { event in
            drawing.reportingChanges(to: drawn) { handler(event) }
        }
    }

    /// Registers a hover OBSERVER: a handler that hears the pointer enter and
    /// leave its region without taking the hover from the control inside it.
    ///
    /// For the wrappers that watch the pointer and act on nothing else,
    /// `.onHover` and `help(_:)`. Each renders its content and then appends a
    /// full-size region, so on every cell it is the innermost match — and hover
    /// resolves one region per point. Registered as an ordinary region, the
    /// wrapper took every `.entered` / `.exited` from what it wrapped:
    /// `Button("Save") {}.onHover { … }` never lit up under the pointer (SwiftUI
    /// keeps both), and `.onHover` or `.help` on a container killed the hover
    /// face of every control inside it. The click half was fixed by letting a
    /// declined click fall through; hover cannot fall through that way, because
    /// the wrapper has to hear the transition AND leave it for the control, and
    /// one hover slot would forget the wrapper and strand its callback `true`.
    /// Forwarding the transitions down, as `_DragHandle` does, is not enough
    /// either: moving from one wrapped control to its neighbour never leaves the
    /// wrapper's region, so nothing would exit the first or enter the second.
    ///
    /// So an observer runs on a lane of its own. The control under the pointer
    /// is resolved as though observers were not there and runs the machine
    /// exactly as it always did — enter, exit, per-cell `.moved`, the reshape
    /// remap — while the observer in front of it runs a second copy. See
    /// ``resolveHover(at:y:)`` for which observer that is. Still ONE observer
    /// per point: nested observers resolve to the outermost (the last
    /// appended), not to all of them.
    ///
    /// Named apart from ``register(in:_:)`` rather than given a label: both take
    /// a single closure, and a trailing closure would match either.
    @MainActor
    func registerHoverObserver(
        in context: RenderContext, _ handler: @escaping (MouseEvent) -> Bool
    ) -> HitTestRegion.HandlerID {
        registerInterned(handler, isHoverObserver: true, in: context)
    }

    /// Mints this control's id, files `handler` under it, and — while a value
    /// memo records — records the registration so a hit can make it again.
    ///
    /// The lane is a parameter rather than a second registration path so that
    /// an observer's replay puts it back on the observer lane: a replayed
    /// `.onHover` filed as an ordinary region would take the hover away from
    /// the control it wraps.
    ///
    /// `@MainActor`, as every `Renderable.renderToBuffer` that calls it already
    /// is: the recorded closure holds the handler, which is not `Sendable`, so
    /// it can only be built where the render walk runs.
    @MainActor
    private func registerInterned(
        _ handler: @escaping (MouseEvent) -> Bool, isHoverObserver: Bool,
        in context: RenderContext
    ) -> HitTestRegion.HandlerID {
        let id = handlerIDs.id(registeredIn: context)
        MouseHandlerRegistrar.register(
            id: id, handler: handler, isHoverObserver: isHoverObserver, into: self)
        // A measure pass registers nothing a frame can be served from: the
        // controls that emit regions suppress them while measuring, and the id
        // above names no control. Nothing to declare, and nothing to replay.
        guard !context.isMeasuring else { return id }
        context.environment.volatileReadTracker?.recordReplayableEffect()
        guard let journal = context.recordingEffectJournal else { return id }
        // Built only while a memo records, so the live path allocates no second
        // closure. The id is captured rather than minted again: it is the one
        // baked into the region of the buffer this memo is about to store, and
        // a replay must not consume the slot a live registration will ask for.
        journal.append(
            EffectJournal.Entry(
                kind: MouseHandlerRegistrar.kind, channelToken: context.environment.keyChannelToken
            ) { replay in
                MouseHandlerRegistrar.register(
                    id: id, handler: handler, isHoverObserver: isHoverObserver, context: replay)
            })
        return id
    }
}

// MARK: - Registration

/// The mouse registrations a render walk makes, shared by the live render and
/// by a value memo replaying them — see `EffectJournal`.
enum MouseHandlerRegistrar {
    /// The journal kind of a hit-test handler registration.
    static let kind = EffectJournal.Kind("mouseHandler")

    /// The journal kind of a per-frame mouse feature request.
    static let featureKind = EffectJournal.Kind("mouseFeature")

    /// Files `handler` under `id` in `dispatcher`, on the lane
    /// `isHoverObserver` names.
    static func register(
        id: HitTestRegion.HandlerID, handler: @escaping (MouseEvent) -> Bool,
        isHoverObserver: Bool, into dispatcher: MouseEventDispatcher
    ) {
        _ = dispatcher.register(id: id, handler)
        if isHoverObserver { dispatcher.noteHoverObserver(id) }
    }

    /// The same, into the dispatcher `context` carries rather than a captured
    /// one, so a replay registers into the services of the frame that serves
    /// the subtree rather than the one that stored it.
    static func register(
        id: HitTestRegion.HandlerID, handler: @escaping (MouseEvent) -> Bool,
        isHoverObserver: Bool, context: RenderContext
    ) {
        guard let dispatcher = context.environment.mouseEventDispatcher else { return }
        register(id: id, handler: handler, isHoverObserver: isHoverObserver, into: dispatcher)
    }

    /// Asks `context`'s dispatcher for `feature`, for the same reason and in
    /// the same way — see ``MouseEventDispatcher/requestFeature(_:in:)``.
    static func requestFeature(_ feature: MouseFeature, context: RenderContext) {
        context.environment.mouseEventDispatcher?.requestFeature(feature)
    }
}
