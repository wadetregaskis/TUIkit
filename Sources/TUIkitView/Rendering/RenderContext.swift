//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderContext.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

/// The context for rendering a view.
///
/// Contains layout constraints, environment values, and the view's
/// structural identity. Runtime services (state storage, lifecycle,
/// key dispatch, etc.) are accessed through ``environment`` using
/// `EnvironmentKey`-based properties.
///
/// `RenderContext` is a pure data container — it does not hold a reference
/// to `Terminal`. All terminal I/O happens in `RenderLoop` after the
/// view tree has been rendered into a ``FrameBuffer``.
///
/// - Important: This is framework infrastructure passed to
///   ``ViewModifier/modify(buffer:context:)``. Most developers only need
///   ``availableWidth``, ``availableHeight``, and ``environment``.
public struct RenderContext {
    /// The available width in characters.
    public var availableWidth: Int

    /// The available height in lines.
    public var availableHeight: Int

    /// The environment values for this render pass.
    ///
    /// Mutating one value in place — `context.environment.foo = x`, which every
    /// stack, every bordered box and every `.foregroundStyle` does once per
    /// walk — leaves the mirrored service fields below alone, because nothing
    /// in a pass writes those two slots. They are wired into a LOCAL
    /// `EnvironmentValues` before the root context exists (`init` below,
    /// `EnvironmentValues.applyRuntimeServices(from:)`) and are read-only from
    /// then on. Replacing the environment WHOLESALE is the one write that
    /// could change them, so that route is ``withEnvironment(_:)``, and it
    /// re-mirrors.
    ///
    /// This was a `didSet` calling `mirrorServices()` — correct, and it
    /// re-derived both services on every write: two `[ObjectIdentifier: Any]`
    /// probes, two `swift_dynamicCast`s and four refcount operations to arrive
    /// at the two values already in the fields. The profiled menu tree writes
    /// the environment 46 times a frame, for 92 of its 687 environment reads,
    /// and that tree is four views — so on an ordinary page the count is per
    /// node per walk, not per menu.
    ///
    /// Assign wholesale ONLY through ``withEnvironment(_:)``. A debug build
    /// checks it: `servicesAreMirrored` is asserted on every view rendered.
    ///
    /// Single backticks on those last two names, not DocC links: they are
    /// `private` and `package`, so neither is in the public symbol graph
    /// `Tools/BuildDocs/build-docs.sh` emits, an unresolved link is a DocC
    /// warning, and CI runs that script with `--strict` — which fails on any
    /// diagnostic at all.
    public var environment: EnvironmentValues

    /// The subtree-memoization cache for this render pass, mirrored from
    /// ``environment``.
    ///
    /// This is the same value as `environment.renderCache`, hoisted out of the
    /// environment dictionary so the hot memoization paths (`EquatableView`,
    /// `_MemoizedRow`) can read it as a stored field — a plain pointer load —
    /// instead of routing every consult through
    /// `EnvironmentValues.subscript<K: EnvironmentKey>` (an `ObjectIdentifier`
    /// hash, an `[ObjectIdentifier: Any]` probe, and an `Any` downcast). A
    /// profile showed that getter at ~4.5% of a text-heavy frame.
    public var renderCache: RenderCache?

    /// The persistent `@State` storage for this render pass, mirrored from
    /// ``environment`` for the same reason as ``renderCache``.
    ///
    /// This is the most-read service in the framework: `renderToBuffer` binds
    /// `@State` and marks the identity active for *every* composite view, and
    /// `measureCompositeBody` binds again on the measure pass. Read through the
    /// environment dictionary, `EnvironmentValues.stateStorage.getter` measured
    /// **5.2% of all CPU** on the `fanout` stress scenario — one service
    /// lookup, all of it hash, `Any` unbox and `swift_dynamicCast`.
    public var stateStorage: StateStorage?

    /// Re-derives every mirrored service from ``environment``.
    ///
    /// The mirrors are a cache of the environment, so this is the one place
    /// that defines what "in sync" means for code that can call it:
    /// ``withEnvironment(_:)``, the only write that can change a service.
    ///
    /// The initializer below does NOT call it. The mirrors have no default
    /// value, so they must be assigned before any method may run on `self`; it
    /// spells the same two assignments out instead, and the two must be kept in
    /// step. `servicesAreMirrored` is what notices if they are not.
    private mutating func mirrorServices() {
        renderCache = environment.renderCache
        stateStorage = environment.stateStorage
    }

    /// Whether the mirrored services still agree with ``environment``.
    ///
    /// The invariant ``withEnvironment(_:)`` maintains, in the form an `assert`
    /// can take. It is worth asserting rather than trusting: a mirror pointing
    /// at the previous pass's cache is a stale memoized buffer, which is a bug
    /// that never looks like one.
    ///
    /// Only ever called from an `assert`, so a release build pays nothing. A
    /// debug build pays two dictionary probes per RENDERED VIEW — hundreds to
    /// thousands a frame, not the 46 environment writes a frame the `didSet`
    /// used to charge release builds for. That is the trade, and it is only
    /// affordable because `--bench` and the profiling runs are release builds.
    package var servicesAreMirrored: Bool {
        renderCache === environment.renderCache && stateStorage === environment.stateStorage
    }

    /// The current view's structural identity in the render tree.
    ///
    /// Built incrementally as `renderToBuffer` traverses the view hierarchy.
    /// Container views append child indices, composite views append type names.
    /// Used by `StateStorage` to persist `@State` values across render passes.
    public var identity: ViewIdentity

    /// Whether an explicit frame width constraint has been set.
    ///
    /// Set by `FlexibleFrameView` when a fixed width is specified.
    /// Container views use this to decide whether to expand to fill
    /// the available width or shrink to fit their content.
    public var hasExplicitWidth: Bool = false

    /// Whether an explicit frame height constraint has been set.
    ///
    /// Set by layout containers (e.g., NavigationSplitView) when a fixed height is specified.
    /// Container views use this to decide whether to expand to fill
    /// the available height or shrink to fit their content.
    public var hasExplicitHeight: Bool = false

    /// Whether this is a measurement pass (no side-effects should occur).
    ///
    /// Set for every measured child, `Layoutable` or not — and the `Layoutable`
    /// path is the rule here, not the exception: `measureResolved` copies the
    /// context and flips this before calling `sizeThatFits`, and the fallback
    /// that measures a `Renderable` by a single render flips it too. Containers
    /// that render a subtree only to size it (the stacks, `Table`, the windowed
    /// stacks, `_ContainerViewCore`, the render loop's own probe) set it by hand
    /// for the same reason.
    ///
    /// Views should skip side-effects like focus registration when this is true.
    ///
    /// ## What counts as a side effect
    ///
    /// A measure is SPECULATIVE — it runs several times a frame, at sizes
    /// nothing is drawn at, for subtrees that may never be rendered — and the
    /// rule it works under is a CPU's: speculation may do anything it likes,
    /// including fill caches, so long as nothing anyone is meant to be able to
    /// RELY on differs when the speculation turns out not to have been needed.
    ///
    /// So the forbidden things are the ones a user or an app can depend on: a
    /// focus registration, a lifecycle callback, a committed frame, a decision
    /// that shapes a later answer. Filling a derived cache is not one of them,
    /// and the render cache's size memo says so outright for the store it owns
    /// (`RenderCache.lookupSize(key:view:)`) — "Unlike the buffer cache this is
    /// safe to populate from a measure pass".
    /// That a cache was filled is of course INFERABLE, from latency or from
    /// allocation; nothing here is secret and none of it is a reason to refuse.
    ///
    /// The line a derived cache has to stay the right side of is that its answer
    /// must not depend on WHICH speculative passes ran. A complete aggregate
    /// does not; a sample does — see `RowWidthRecords`, which is a sample and is
    /// therefore seeded from the render path only, and `StackContentWidth.swift`,
    /// which is a maximum over every row and is not.
    public var isMeasuring: Bool = false

    /// Which generation of the environment a measurement belongs to — the
    /// measure memo's only handle on an environment change.
    ///
    /// ``RenderCache/MeasureKey`` deliberately carries no environment: it keys
    /// on the identity, the two widths, the view's type and a hash of the view's
    /// value, and nothing else. That is sound for the case it was
    /// built for, where the environment is fixed for the pass. It is NOT sound
    /// for a container that ASSIGNS an environment value directly —
    /// `context.environment.foo = x`, which several of them do — between two
    /// measurements of one subtree at one identity and one width. Those are two
    /// questions, and the key cannot tell them apart, so the memo answers the
    /// second with the first one's size.
    ///
    /// That is not hypothetical; it is the shape of two reverted commits. A
    /// menu measures its rows twice: hugging, to learn its width, and again at
    /// that width, because a row drawn into the interior less its hint column
    /// can wrap where the hug did not. On the arm where the hug wanted every
    /// cell it was offered the two asks are at the SAME width — so the reflow
    /// was answered by the hug, at `_ButtonCore`, whose size depends on the
    /// `ButtonStyle` it reads from the environment. Twenty stale serves on one
    /// walk of the Example, and the fix that read the reflow height silently did
    /// nothing wherever the memo hit.
    ///
    /// This is the mechanism by which such a container says so. It is
    /// deliberately NOT automatic — a digest of the whole environment would be
    /// paid for on every one of the ~2,000 key probes a frame, by every view,
    /// to serve the handful of containers that need it. Opting in costs one
    /// multiply and one xor into a key hash that is computed anyway.
    ///
    /// It is scoped by the copy: only the subtree handed the bumped context sees
    /// the new generation, so a menu invalidates its own rows and nothing else.
    /// The sibling of this idea one memo over is
    /// ``environmentApplicationDepth``, which disambiguates the BUFFER memo's
    /// environment slots for the same underlying reason.
    ///
    /// Bump it with ``invalidatingMeasureMemo()``.
    ///
    /// BOTH measure keys carry it, and they carry it differently.
    /// ``RenderCache/MeasureKey`` folds it into its identity hash, because it
    /// cannot afford an eighth field; ``RenderCache/SizeKey`` stores it as a
    /// field, because it must — a hash-only fold leaves the synthesised `==`
    /// calling two keys equal, and that table is cross-frame, so the value memo
    /// would answer a post-change ask with a pre-change size until the memoized
    /// value itself changed. A third key would have to choose one of the two on
    /// the same grounds.
    ///
    /// A `UInt8`, declared here among the flags, because `RenderContext` is
    /// copied down the whole tree and an `Int` grew it from 97 bytes to 105 —
    /// past the 104-byte stride, so every context copy in the framework got a
    /// word wider. That measured **+2.4% on `anyview` and +1.4% on
    /// `modifiers`**, the two shapes that pass the most contexts. In the flag
    /// run it lands in padding that was already there and the stride does not
    /// move. It wraps (``invalidatingMeasureMemo()`` uses `&+`), which is
    /// harmless: 128 opt-in bumps on one root-to-leaf path is not a shape that
    /// exists, and the consequence of a wrap would be the stale serve that is
    /// the status quo everywhere this is not called.
    ///
    /// ## Bit 7 is not a generation
    ///
    /// It is the IDEAL-WIDTH mark: set while a horizontal natural-extent probe
    /// asks "how wide would you be if nothing stopped you" (`asksIdealWidth`),
    /// and never at a committed render. It lives here rather than in a field of
    /// its own because an answer taken under it differs from one taken without
    /// it — a windowed stack answers for every row under it and for the rows
    /// its budget reaches otherwise — and this byte is already in both measure
    /// keys, so the two answers are kept apart by construction and at no cost.
    /// A generation is
    /// the low seven bits; anything that compares generations across passes
    /// compares `generationIgnoringIdealWidth`.
    public var measureGeneration: UInt8 = 0

    /// The depth of the innermost enclosing `ScrollView`'s content identity,
    /// plus one; `0` outside any scroll content. Set by the scroll view for
    /// every ask it makes of its content, and cleared for a subtree drawn
    /// somewhere else (a sheet, a popover, a menu presented from inside it).
    ///
    /// A lazy stack asks it at MEASURE time whether its render will band it or
    /// draw it whole: a stack reached from the content by single-child steps
    /// is the one the scroll window is consumed by, and its measure may be an
    /// estimate only the scrollbar reads; any other stack below the content is
    /// drawn whole, into the height its measure claimed, and must measure what
    /// it will draw. A measure has no window to ask — the scroll view publishes
    /// one only for its render — hence this.
    ///
    /// A field and not an environment value because an environment value cost
    /// more than the question is worth: one more entry in every scroll view's
    /// content environment, copied by every environment write beneath it,
    /// measured **+2.0% on `session/editor`**, which has no nested stack at
    /// all. A depth rather than the identity because the identity is a class
    /// reference, and eight more bytes would move this struct past its 104-byte
    /// stride (see ``measureGeneration``); two bytes land in padding that is
    /// already there, after the flags. The lineage the depth leaves out is
    /// implied: every identity a context carries descends from the one it was
    /// given, and the canvas is cleared where a context is lent to a subtree
    /// drawn elsewhere.
    ///
    /// `belowScrollContentOrigin` below a view that sits at the origin and
    /// keeps it for itself: the rows of a windowed stack
    /// (`leaveScrollOrigin()`). Single-child steps lead there all the same — a
    /// lone lazy stack in an outer one, a custom view whose body is the stack
    /// — and the depth alone read that stack as the one the window bands, so
    /// it estimated itself and was drawn whole into the estimate.
    package var scrollContentOriginDepth: UInt16 = 0

    /// `scrollContentOriginDepth` for a subtree inside scroll content but
    /// below its origin, where nothing is the stack the window is consumed by.
    /// No real depth: the scroll view marks none this deep.
    package static let belowScrollContentOrigin = UInt16.max

    /// Whether this measure is a horizontal natural-extent probe's IDEAL-WIDTH
    /// ask — see ``measureGeneration``'s bit 7. Under it, a width proposal of
    /// `nil` means SwiftUI's unspecified: a view that fills whatever it is
    /// offered reports what it would be if it were offered nothing, rather than
    /// the probe's budget.
    @inlinable
    package var asksIdealWidth: Bool { measureGeneration & 0x80 != 0 }

    /// ``measureGeneration`` without the ideal-width mark: the generation a
    /// value kept across passes is compared by, since an answer filed under
    /// the probe is the same answer when a render asks for it.
    @inlinable
    package var generationIgnoringIdealWidth: UInt8 { measureGeneration & 0x7F }

    /// This context with the ideal-width mark set or cleared.
    @inlinable
    package func askingIdealWidth(_ asks: Bool = true) -> Self {
        var copy = self
        copy.measureGeneration = asks ? copy.measureGeneration | 0x80 : copy.measureGeneration & 0x7F
        return copy
    }

    /// How many environment applications lie between the root and here.
    ///
    /// The disambiguator for `RenderCache.EnvironmentSlot`: two modifiers
    /// injecting the SAME key path can share one identity (a `Renderable`
    /// adds no child identity), and a slot keyed only on (identity, keyPath)
    /// let the outer one answer for both — the inner one's changes were never
    /// compared, so memoized subtrees below it served stale buffers. The
    /// depth is structural, so it is the same on the measure and render walks
    /// and stable across frames. Bumped by whoever injects an environment
    /// value AND notes it (`EnvironmentModifier`, `_StyleEnvironmentView`,
    /// `TintModifier`, and `.focusable()` / `.contextMenu` for the
    /// `\.isFocused` they publish); plain `setting()` writes do not note, so
    /// they have no slot to disambiguate.
    public var environmentApplicationDepth: Int = 0

    /// This context, with every measurement taken so far out of the memo's
    /// reach for the subtree below.
    ///
    /// Call it immediately after assigning an environment value that changes
    /// what the subtree measures to — see ``measureGeneration``. Answers taken
    /// AFTER this share the new generation, so the work done under it is still
    /// reused normally; what is put out of reach is only the answers from
    /// before the environment changed.
    public func invalidatingMeasureMemo() -> Self {
        var copy = self
        // The low seven bits only: bit 7 is the ideal-width mark, which a bump
        // must neither set nor clear.
        copy.measureGeneration =
            (copy.measureGeneration & 0x80) | ((copy.measureGeneration &+ 1) & 0x7F)
        return copy
    }

    /// The rectangle a `.gradientExtent(.subtree)` gradient spans, and where
    /// this view sits in it — `nil` when no such gradient is in force, which is
    /// almost always.
    ///
    /// A stored field rather than an environment value: it is read on the leaf
    /// path and nudged by every container that places children, and
    /// `EnvironmentValues` is a dictionary whose getter is expensive enough
    /// that ``renderCache`` and ``stateStorage`` were both hoisted out of it.
    /// Unused, it costs one nil check.
    public var gradientFrame: GradientFrame?

    /// The frame a container publishes to its children: this one, with the
    /// content size the container has just worked out standing in for the
    /// modifier's provisional guess.
    ///
    /// Call once per container, then ``placingGradientChild(_:x:y:)`` per
    /// child. Both are `nil`-cheap: with no `.gradientExtent(.subtree)` above,
    /// this returns `nil` and the placement is the identity.
    ///
    /// - Parameters:
    ///   - width: The container's own content width, in cells.
    ///   - height: Its content height, in lines.
    /// - Returns: The settled frame, or `nil` when no gradient spans this
    ///   subtree.
    public func gradientContentFrame(width: Int, height: Int) -> GradientFrame? {
        gradientFrame?.resolvingExtent(width: width, height: height)
    }

    /// This context as seen by a child the container places at `(x, y)` inside
    /// the content `frame` describes.
    ///
    /// - Parameters:
    ///   - frame: The container's settled frame, from
    ///     ``gradientContentFrame(width:height:)``.
    ///   - x: The child's left edge, relative to the container's content.
    ///   - y: The child's top edge, likewise.
    /// - Returns: A context whose ``gradientFrame`` is anchored on the child.
    public func placingGradientChild(_ frame: GradientFrame?, x: Int, y: Int) -> Self {
        guard let frame else { return self }
        var placed = self
        placed.gradientFrame = frame.offset(byX: x, y: y)
        return placed
    }

    /// Creates a new RenderContext.
    ///
    /// - Parameters:
    ///   - availableWidth: The available width in characters.
    ///   - availableHeight: The available height in lines.
    ///   - environment: The environment values (defaults to empty).
    ///   - identity: The view identity path (defaults to root).
    public init(
        availableWidth: Int,
        availableHeight: Int,
        environment: EnvironmentValues = EnvironmentValues(),
        identity: ViewIdentity = ViewIdentity(path: "")
    ) {
        self.availableWidth = availableWidth
        self.availableHeight = availableHeight
        self.environment = environment
        self.identity = identity
        // Property observers do not fire during initialization, so seed the
        // mirrors by hand here.
        self.renderCache = environment.renderCache
        self.stateStorage = environment.stateStorage
    }

    /// Creates a new context with the same size but different environment.
    ///
    /// - Parameter environment: The new environment values.
    /// - Returns: A new RenderContext with the updated environment.
    public func withEnvironment(_ environment: EnvironmentValues) -> Self {
        var copy = self
        // The one route that may be handed an environment carrying DIFFERENT
        // services, so the one route that re-derives the mirrors. The
        // structural copy helpers (`withChildIdentity`, `withAvailableWidth`,
        // …) only touch identity or size, and an in-place environment write
        // cannot reach a service slot, so both carry the mirrors for free.
        copy.environment = environment
        copy.mirrorServices()
        return copy
    }

    /// This context under `environment`, which MUST have been derived from
    /// ``environment`` — `setting(_:to:)`, or a copy with one value written.
    ///
    /// The difference from ``withEnvironment(_:)`` is the work it does not do:
    /// re-deriving ``renderCache`` and ``stateStorage`` out of a dictionary
    /// that is carrying the same two objects. A derived environment cannot have
    /// changed them, so there is nothing to re-derive — and this is the route
    /// every `.environment(_:_:)`-family modifier takes, once per application
    /// on each of the two walks.
    ///
    /// - Parameter environment: An environment derived from ``environment``.
    /// - Returns: This context, under `environment`.
    package func withDerivedEnvironment(_ environment: EnvironmentValues) -> Self {
        var copy = self
        copy.environment = environment
        // The "derived" in the name, checked where checking is free (see
        // ``servicesAreMirrored``). A caller holding an environment from
        // anywhere else wants ``withEnvironment(_:)``.
        assert(
            copy.servicesAreMirrored,
            "withDerivedEnvironment given an environment carrying different services")
        return copy
    }

    /// Creates a new context with a child identity for the given type and index.
    ///
    /// Used by container views (`TupleView`, `ViewArray`) to assign
    /// structural identities to their children.
    ///
    /// - Parameters:
    ///   - type: The child view's type.
    ///   - index: The child's position within the container.
    /// - Returns: A new RenderContext with the extended identity path.
    public func withChildIdentity<V>(type: V.Type, index: Int) -> Self {
        var copy = self
        copy.identity = identity.child(type: type, index: index)
        return copy
    }

    /// Type-erased form of ``withChildIdentity(type:index:)`` — used by
    /// `ChildView`, which stores its child as `any View` and so only knows the
    /// identity type dynamically. Produces the same identity as the generic form.
    public func withChildIdentity(erasedType type: Any.Type, index: Int) -> Self {
        var copy = self
        copy.identity = identity.child(erasedType: type, index: index)
        return copy
    }

    /// Id-keyed form of ``withChildIdentity(erasedType:index:)`` — used for
    /// `ForEach` rows, whose identity must follow their element's `id` (not
    /// their position) so `@State`, focus and lifecycle move with the element
    /// across reorders and insertions.
    public func withChildIdentity(erasedType type: Any.Type, key: String) -> Self {
        var copy = self
        copy.identity = identity.child(erasedType: type, key: key)
        return copy
    }

    /// Creates a new context with a child identity for a composite view's body.
    ///
    /// Used when descending into a view's `body` where there is exactly
    /// one child (no sibling disambiguation needed).
    ///
    /// - Parameter type: The child view's type.
    /// - Returns: A new RenderContext with the extended identity path.
    public func withChildIdentity<V>(type: V.Type) -> Self {
        var copy = self
        copy.identity = identity.child(type: type)
        return copy
    }

    /// Creates a new context with a branch identity.
    ///
    /// Used by `ConditionalView` to distinguish between if/else branches.
    ///
    /// - Parameter label: The branch label (`"true"` or `"false"`).
    /// - Returns: A new RenderContext with the branch identity.
    public func withBranchIdentity(_ label: String) -> Self {
        var copy = self
        copy.identity = identity.branch(label)
        return copy
    }

    /// Creates a new context with a different available width.
    ///
    /// Used by layout containers (e.g., NavigationSplitView) to constrain
    /// child views to a specific column width.
    ///
    /// This also sets `hasExplicitWidth` to true so that child views
    /// (like List) know to expand to fill the available width.
    ///
    /// - Parameter width: The new available width in characters.
    /// - Returns: A new RenderContext with the updated width.
    public func withAvailableWidth(_ width: Int) -> Self {
        var copy = self
        copy.availableWidth = width
        copy.hasExplicitWidth = true
        return copy
    }

    /// Creates a copy with updated available height.
    ///
    /// Used by layout containers (e.g., NavigationSplitView) to constrain
    /// child views to a specific height.
    ///
    /// This also sets `hasExplicitHeight` to true so that child views
    /// (like List) know to expand to fill the available height.
    ///
    /// - Parameter height: The new available height in lines.
    /// - Returns: A new RenderContext with the updated height.
    public func withAvailableHeight(_ height: Int) -> Self {
        var copy = self
        copy.availableHeight = height
        copy.hasExplicitHeight = true
        return copy
    }

    /// Creates a copy with updated available width and height.
    ///
    /// Used by layout containers to constrain child views to specific dimensions.
    ///
    /// - Parameters:
    ///   - width: The new available width in characters.
    ///   - height: The new available height in lines.
    /// - Returns: A new RenderContext with the updated dimensions.
    public func withAvailableSize(width: Int, height: Int) -> Self {
        var copy = self
        copy.availableWidth = width
        copy.availableHeight = height
        copy.hasExplicitWidth = true
        copy.hasExplicitHeight = true
        return copy
    }

    // MARK: - Container Layout Helpers

    /// What is left of `available` once `chrome` cells of decoration have taken
    /// theirs — never the last cell, while there is one to give.
    ///
    /// Decoration losing to the thing it decorates is the only order that
    /// degrades legibly, and the alternative is not a tighter box but a blank
    /// screen: chrome subtracted flat to zero leaves the content no cell to
    /// render into, an empty child collapses its container (a bordered box with
    /// nothing inside is nothing), and the collapse propagates all the way up.
    /// Two of the stress harness's scenarios drew literally nothing below three
    /// rows for exactly that reason.
    ///
    /// Clamping here rather than at each subtraction site also keeps the two
    /// halves of a container honest: measure and render both ask this, so they
    /// cannot disagree about how much room the content was given.
    ///
    /// - Parameters:
    ///   - available: The extent the container itself was offered, in cells.
    ///   - chrome: The cells the decoration wants — borders, insets, separators.
    /// - Returns: The extent to offer the content.
    @inlinable
    public static func extent(_ available: Int, insideChrome chrome: Int) -> Int {
        available <= 0 ? 0 : max(1, available - chrome)
    }

    /// Creates a context for rendering content inside a bordered container.
    ///
    /// Subtracts the border width (2 characters for left + right) from available width.
    /// Propagates `hasExplicitWidth` from parent so children know whether to expand.
    ///
    /// - Parameter hasBorder: Whether the container has a border (default: true).
    /// - Returns: A new context with adjusted width for inner content.
    public func forBorderedContent(hasBorder: Bool = true) -> Self {
        var copy = self
        if hasBorder {
            copy.availableWidth = Self.extent(availableWidth, insideChrome: 2)
        }
        // Propagate hasExplicitWidth from parent - if parent has explicit width,
        // children should also expand to fill the (reduced) available space.
        return copy
    }

    /// Calculates the inner width for a container based on content.
    ///
    /// Containers (borders, panels, cards) size to fit their content, but
    /// never wider than the space available between their borders.
    ///
    /// - Parameters:
    ///   - contentWidth: The natural width of the content.
    ///   - innerAvailableWidth: The width available inside the container.
    /// - Returns: The content width, capped at `innerAvailableWidth`.
    public func resolveContainerWidth(contentWidth: Int, innerAvailableWidth: Int) -> Int {
        max(0, min(contentWidth, innerAvailableWidth))
    }

    /// Calculates the inner height for a container based on content.
    ///
    /// Containers size to fit their content height.
    /// They do not auto-expand to fill available space.
    ///
    /// - Parameters:
    ///   - contentHeight: The natural height of the content.
    ///   - borderOverhead: Lines used by borders/title/footer (unused, kept for API compatibility).
    /// - Returns: The content height.
    public func resolveContainerHeight(contentHeight: Int, borderOverhead: Int = 0) -> Int {
        contentHeight
    }
}
