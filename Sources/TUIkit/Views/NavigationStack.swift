//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationStack.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - NavigationStack

/// A view that displays a root view and lets you push additional views over it.
/// Matches SwiftUI's type of the same name.
///
/// ```swift
/// NavigationStack {
///     List(recipes) { recipe in
///         NavigationLink(recipe.name, value: recipe)
///     }
///     .navigationTitle("Recipes")
///     .navigationDestination(for: Recipe.self) { recipe in
///         RecipeView(recipe: recipe)
///             .navigationTitle(recipe.name)
///     }
/// }
/// ```
///
/// The stack shows its root until something is pushed; from then on it shows
/// the top of the path, under a navigation bar carrying the trail of
/// ``navigationTitle(_:)-(LocalizedStringKey)``s that got you there:
///
/// ```
///   Planets  ›  Mars  ›  Deimos  ›  Copernicus Rim
/// ```
///
/// Every crumb but the last is a `Button` — a Tab stop, and clicking or
/// activating one pops straight back to that depth rather than one screen at a
/// time. **Escape** and `@Environment(\.dismiss)` still pop one, from anywhere
/// in the pushed screen.
///
/// The trail gives way as the terminal narrows: first its middle is elided
/// (`Planets  ›  …  ›  Copernicus Rim`), keeping the two ends that orient you;
/// then, when even that will not fit, the bar falls back to a single **‹ Back**
/// button and the truncated title. The bar's height never changes through any of
/// this — see `ChromeStyle.barHeight(contentRows:)`.
///
/// ## Where the path lives
///
/// With no `path` argument the stack keeps the path itself, which is all most
/// apps need. Bind one when you want to read or change it — deep-linking, or
/// returning to the root from several screens down:
///
/// - `NavigationStack(path: $recipes)` — a homogeneous stack. `Data` is any
///   `RangeReplaceableCollection` of `Hashable` values.
/// - `NavigationStack(path: $path)` with a ``NavigationPath`` — a
///   heterogeneous stack, where different screens push different types.
///
/// ## TUI-specific behaviour
///
/// - The bar is exactly two rows (title row + rule) whatever the title is, so
///   the space left for content never depends on the content.
/// - The root keeps rendering while a screen is pushed — off-screen, and
///   isolated from focus and key events the way a modal's backdrop is. That is
///   what keeps the root's `@State` (a scroll position, a selection) alive to
///   come back to, and what keeps its `.navigationDestination(for:)`
///   registrations current.
public struct NavigationStack<Root: View>: View {

    /// Where the path is kept. Every case is normalised to the same pair of
    /// closures at render time, so the core has one path model to work with.
    enum PathStorage {
        /// The stack's own `@State` — `NavigationStack { … }`.
        case owned
        /// A ``NavigationPath`` binding.
        case path(Binding<NavigationPath>)
        /// A typed collection binding, erased to `AnyHashable` and back.
        case typed(read: () -> [AnyHashable], write: ([AnyHashable]) -> Void)
    }

    let root: Root
    let storage: PathStorage

    /// The destination registry and path accessors. `@State` so it is ONE
    /// object across frames: a link rendered now installs a button action that
    /// must still find this stack's path when it fires later.
    @State private var coordinator = NavigationCoordinator()

    /// The path, when the stack owns it (``PathStorage/owned``). Unused
    /// otherwise; it costs one empty array.
    @State private var ownedPath: [AnyHashable] = []

    /// Creates a navigation stack that manages its own path.
    public init(@ViewBuilder root: () -> Root) {
        self.root = root()
        self.storage = .owned
    }

    /// Creates a navigation stack backed by a ``NavigationPath``, for screens
    /// driven by values of more than one type.
    ///
    /// - Parameters:
    ///   - path: The path to read and write.
    ///   - root: The view at the bottom of the stack.
    public init(path: Binding<NavigationPath>, @ViewBuilder root: () -> Root) {
        self.root = root()
        self.storage = .path(path)
    }

    /// Creates a navigation stack backed by a collection of hashable values.
    ///
    /// - Parameters:
    ///   - path: The collection of values to show screens for.
    ///   - root: The view at the bottom of the stack.
    public init<Data>(path: Binding<Data>, @ViewBuilder root: () -> Root)
    where
        Data: MutableCollection & RandomAccessCollection & RangeReplaceableCollection,
        Data.Element: Hashable
    {
        self.root = root()
        self.storage = .typed(
            read: { path.wrappedValue.map { AnyHashable($0) } },
            // A typed path can hold only its own element type; anything else
            // on the way back in is dropped, which is the binding's contract
            // rather than a policy of ours. See ``NavigationLink``.
            write: { erased in
                path.wrappedValue = Data(erased.compactMap { $0.base as? Data.Element })
            })
    }

    public var body: some View {
        let accessors = accessors()
        return _NavigationStackCore(
            root: root,
            coordinator: coordinator,
            read: accessors.read,
            write: accessors.write)
    }

    /// The path accessors for whichever storage this stack was built with.
    private func accessors() -> (read: () -> [AnyHashable], write: ([AnyHashable]) -> Void) {
        switch storage {
        case .owned:
            let binding = $ownedPath
            return ({ binding.wrappedValue }, { binding.wrappedValue = $0 })
        case .path(let path):
            return (
                { path.wrappedValue.elements },
                { path.wrappedValue = NavigationPath(erased: $0) }
            )
        case .typed(let read, let write):
            return (read, write)
        }
    }
}

// MARK: - Core

/// Renders the root, or the top of the path over it.
///
/// A `_*Core` because two things here are procedural and cannot be composed:
/// rendering the root purely for its side effects while showing something else,
/// and reading the screen's `navigationTitle` preference back out after
/// rendering it, to draw a bar whose height was fixed before either happened.
private struct _NavigationStackCore<Root: View>: View, Renderable, Layoutable {
    let root: Root
    let coordinator: NavigationCoordinator
    let read: () -> [AnyHashable]
    let write: ([AnyHashable]) -> Void

    /// The navigation bar's height: the title row plus the rule under it.
    ///
    /// A constant, deliberately. Chrome whose height depends on the content it
    /// sits above cannot be laid out in one pass — the content's height would
    /// have to be known to size the bar, and the bar's height has to be known
    /// to give the content its space. A long title truncates instead.
    private static var barHeight: Int { 2 }

    var body: Never {
        fatalError("_NavigationStackCore renders via Renderable")
    }

    // MARK: Measurement

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let elements = read()
        var childContext = context
        childContext.environment.navigationCoordinator = coordinator

        guard let top = elements.last else {
            return measureChild(
                root, proposal: proposal,
                context: childContext.withChildIdentity(type: type(of: root)))
        }

        let bar = Self.barHeight
        let inner = ProposedSize(
            width: proposal.width,
            height: proposal.height.map { max(0, $0 - bar) })
        childContext = childContext.withAvailableSize(
            width: childContext.availableWidth,
            height: max(0, childContext.availableHeight - bar))

        guard let destination = coordinator.destination(for: top) else {
            return ViewSize(
                width: proposal.width ?? 0, height: bar,
                isWidthFlexible: true, isHeightFlexible: false)
        }
        let size = measureChild(
            destination, proposal: inner,
            context: childContext.withChildIdentity(type: NavigationScreen.self))
        return ViewSize(
            width: size.width, height: size.height + bar,
            isWidthFlexible: size.isWidthFlexible, isHeightFlexible: size.isHeightFlexible)
    }

    // MARK: Rendering

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Re-point the coordinator at this frame's binding before anything in
        // the subtree can capture it. Render passes only: a measure pass would
        // install identical closures for no gain, and persistent state is not
        // a measure's to touch.
        if !context.isMeasuring {
            coordinator.read = read
            coordinator.write = write
        }

        let elements = read()
        var base = context
        base.environment.navigationCoordinator = coordinator

        // Each depth is its own focus section, so walking into a screen and
        // back restores the focus the level you left was holding — the same
        // thing a dismissed modal does. Without it the pop landed on whichever
        // control registered first, so returning from a planet always put the
        // focus back on the first planet rather than on the one you opened.
        //
        // Before anything renders: the level being returned TO registers its
        // focusables during this pass, and it must do so with the deeper
        // section already gone.
        if !context.isMeasuring, let section = enterSection(depth: elements.count, context: context) {
            base.environment.activeFocusSectionID = section
        }

        guard let top = elements.last else {
            return TUIkit.renderToBuffer(
                root, context: base.withChildIdentity(type: type(of: root)))
        }

        // The root still renders — off-screen, and isolated from focus and key
        // events exactly as a modal's backdrop is. Its buffer (and with it
        // every hit-test region) is dropped, so nothing on it can be reached;
        // what survives is its `@State`, which `endRenderPass` would otherwise
        // prune the moment it stopped rendering, and its
        // `.navigationDestination(for:)` registrations, which stay current
        // because the closures are re-captured each frame.
        //
        // `withThrowawayFrameDemand` because the buffer is dropped WHOLE. A
        // root that read the pulse phase, or asked the scheduler for a
        // lattice, went on driving the loop at its own rate from behind the
        // screen covering it — the isolation above covers every channel by
        // which the invisible root could reach the USER, and left it the two
        // by which it reached the CLOCK.
        if !context.isMeasuring {
            let backdrop = base.isolatedForBackground().withThrowawayFrameDemand()
            // Collect the root's title while it renders, because this is the
            // only place it is ever published — the bar draws for pushed
            // screens, so nothing else sees depth 0's name, and the crumb trail
            // would start with an anonymous "…" no matter how wide the terminal.
            let preferences = backdrop.environment.preferenceStorage
            // Declared like the screen's collection in `renderScreen`, and on
            // the LIVE tracker rather than the backdrop's throwaway: this one
            // is not a demand for a frame but a refusal to be cached, and it
            // is load-bearing. Served from a memo this whole branch is skipped,
            // the root does not render, and `endRenderPass` prunes the `@State`
            // the render exists to keep.
            context.environment.volatileReadTracker?.recordRenderSideEffect()
            preferences?.push()
            _ = TUIkit.renderToBuffer(
                root, context: backdrop.withChildIdentity(type: type(of: root)))
            coordinator.recordTitle(preferences?.pop()[NavigationTitleKey.self] ?? "", atDepth: 0)
        }

        return renderScreen(top: top, context: base)
    }

    /// Activates the focus section for `depth`, deactivating any deeper ones
    /// this stack had entered — deepest first, so each level hands its focus
    /// back up the way it was given.
    ///
    /// - Returns: the section the screen and its bar should register in, or
    ///   `nil` at the root: depth 0 has no section of its own. The root is
    ///   ordinary page content and belongs in whatever section the page is
    ///   already using, which is also where the deepest `deactivateSection`
    ///   reverts to.
    private func enterSection(depth: Int, context: RenderContext) -> String? {
        let focusManager = context.environment.focusManager
        // Not while rendering as a modal's dimmed backdrop: that pass carries a
        // THROWAWAY focus manager, so the deactivation would land on an object
        // nobody reads — and consuming `renderedDepth` here would spend the
        // trigger, so the real manager would never hear about the pop at all.
        // The page under a presentation is not navigating; it is a picture.
        guard let focusManager, !focusManager.isBackdrop else { return nil }
        let base = context.identity.path
        if coordinator.renderedDepth > depth {
            for deeper in stride(from: coordinator.renderedDepth, to: depth, by: -1) {
                focusManager.deactivateSection(id: Self.sectionID(base: base, depth: deeper))
            }
        }
        let pushed = coordinator.renderedDepth < depth
        coordinator.renderedDepth = depth
        guard depth > 0 else { return nil }
        let sectionID = Self.sectionID(base: base, depth: depth)
        // Registration is per-frame presence: sections are rebuilt every pass,
        // so the section has to be declared again each time or its controls
        // have nowhere to register. For the same reason it is declared to any
        // value-memoizing ancestor, as `.focusSection` declares its own: a stack
        // served from the cache registers no section at all.
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        focusManager.registerSection(id: sectionID)
        // Activation is NOT. It is a transition — it remembers the section it
        // leaves, drops the focus, and restores this one's memory — so calling
        // it every frame while something else is active (an alert or sheet
        // presented FROM a pushed screen) took the focus back from it on every
        // pass: the dialog's control was focused for under a frame, a field in
        // it was torn down and restarted continuously, and the render loop
        // spun at the frame cap for as long as the dialog was up.
        if pushed { focusManager.activateSection(id: sectionID) }
        return sectionID
    }

    /// A focus section per stack, per depth. Structural identity, never the
    /// pushed value: two stacks on one page must not share a section, and the
    /// same value pushed twice is two different places to come back to.
    static func sectionID(base: String, depth: Int) -> String {
        "navigation-\(base)-\(depth)"
    }

    /// Renders the pushed screen with its navigation bar above it.
    private func renderScreen(top: AnyHashable, context: RenderContext) -> FrameBuffer {
        let width = max(0, context.availableWidth)
        let contentHeight = max(0, context.availableHeight - Self.barHeight)

        var screenContext = context.withAvailableSize(width: width, height: contentHeight)
        // Escape and `\.dismiss` both mean "go back" from inside a pushed
        // screen, which is what SwiftUI's dismiss does in a stack.
        let coordinator = coordinator
        screenContext.environment.dismiss = DismissAction { coordinator.pop() }

        // Where the stack's Escape handler goes: BEHIND everything the screen is
        // about to register, although whether to register it at all is only
        // known once the screen has rendered (see `renderBar`). Read now, before
        // the first of the screen's handlers lands.
        let escapeHandlerSlot = context.environment.keyEventDispatcher?.handlerCount ?? 0

        // Collect the screen's own preferences so the bar can read the title it
        // set — and only the title IT set, not one an ancestor published.
        let preferences = screenContext.environment.preferenceStorage
        // Collecting observes this pass's preferences, as `onPreferenceChange`
        // does, and is declared to any value-memoizing ancestor for the same
        // reason: a served buffer runs no collection. Render passes only, like
        // every declaration.
        if !context.isMeasuring {
            context.environment.volatileReadTracker?.recordRenderSideEffect()
        }
        preferences?.push()
        var content =
            coordinator.destination(for: top).map {
                TUIkit.renderToBuffer(
                    $0, context: screenContext.withChildIdentity(type: NavigationScreen.self))
            } ?? FrameBuffer()
        let published = preferences?.pop()
        let title = published?[NavigationTitleKey.self] ?? ""
        let hidesBack = published?[NavigationBackButtonHiddenKey.self] ?? false

        content = padded(content, toWidth: width, height: contentHeight)

        var buffer = renderBar(
            title: title, hidesBack: hidesBack, width: width,
            escapeHandlerSlot: escapeHandlerSlot, context: context)
        buffer.appendVertically(content)
        return buffer
    }

    /// The navigation bar, pinned to `ChromeStyle.barHeight(contentRows:)` rows.
    /// `escapeHandlerSlot` is the key dispatcher's handler count from before the
    /// screen rendered: where the stack's Escape handler is filed.
    private func renderBar(
        title: String, hidesBack: Bool, width: Int, escapeHandlerSlot: Int,
        context: RenderContext
    ) -> FrameBuffer {
        let coordinator = coordinator
        // The Back button is a real `Button`: a Tab stop, clickable, and
        // styled by whatever `.buttonStyle` is in effect above the stack.
        let back = "‹ " + LocalizationService.shared.string(for: LocalizationKey.Button.back)
        let barContext = context.withAvailableSize(width: width, height: Self.barHeight)

        // Escape goes back, after the focused control has had its chance at the
        // key (the status-bar claim re-routes ESC through the focus system
        // first, so a list clearing its selection still wins). The claim is the
        // lightweight kind: a pushed screen is not a modal, so the app's other
        // shortcuts keep working.
        // Only when nothing else claimed ESC this frame: the content renders
        // BEFORE the bar (the bar needs the title preference the content
        // publishes), so an open menu, popover or drop-down inside it has
        // already posted its own close label — and this write clobbered it,
        // showing "⎋ go back" under an open menu whose ESC closes the menu.
        //
        // A presented sheet or alert claims ESC the OTHER way: as a dismiss item
        // of its own input-grabbing section, never through the label. The label
        // test alone let this write go-back over it, and the status bar renames
        // every escape item to the claimed label — the dialog read "⎋ go back"
        // while ESC closed the dialog. With dismissal disabled the dialog
        // publishes no item, and go-back was the only escape entry on the bar,
        // for a key that did nothing: the dialog's grab keeps the handler below
        // from running. So a modal section holding the keyboard is a claim too;
        // with none written, the dialog's own item is what the bar shows and
        // what ESC fires. A presenter rendered AFTER the stack marks its section
        // too late for this to see, and is not covered.
        if !context.isMeasuring, barContext.environment.statusBar?.escapeLabelOverride == nil,
            barContext.environment.focusManager?.activeSectionIsModal != true
        {
            // The claim and the handler are both per-frame: the render loop
            // resets the label and empties the dispatcher before every pass, so a
            // stack served from a value memo left Escape unclaimed and unhandled.
            // Declared, as every other writer to those registries is.
            barContext.environment.volatileReadTracker?.recordRenderSideEffect()
            barContext.environment.statusBar?.escapeLabelOverride =
                LocalizationService.shared.string(for: LocalizationKey.StatusBar.goBack)
            barContext.environment.statusBar?.escapeClaimGrabsInput = false
            // Filed at the slot taken before the screen rendered, not appended.
            // The dispatcher asks the most recent registration first, so an
            // appended pop outranked every handler the screen had just
            // registered: a screen's `.onKeyPress(keys: [.escape])` never ran,
            // and a screen that must not be left (the remedy
            // `navigationBarBackButtonHidden(_:)` documents) could not say so.
            // Filed ahead of the screen, going back is what ESC does when
            // nothing ON the screen wants it; a handler AROUND the stack (a
            // page returning to its menu on ESC) registered before the slot,
            // and still loses to going back.
            //
            // Only the handler moves. The label claim above stays after the
            // screen, because it has to see whether something inside claimed
            // ESC first; hoisted, it would also lower the grabs-input flag
            // under a drop-down that has yet to post its own claim.
            barContext.environment.keyEventDispatcher?.insertHandler(
                at: escapeHandlerSlot,
                sectionID: barContext.environment.activeFocusSectionID
            ) { event in
                guard event.key == .escape else { return false }
                coordinator.pop()
                return true
            }
        }

        // The title takes whatever the button leaves, truncated rather than
        // wrapped: the bar's height is fixed, so it has nowhere to wrap to.
        // Measure the BUTTON, not the bar — the bar ends in a `Spacer`, so
        // measuring it answers "the whole width", which left the title no room
        // at all and silently truncated it to nothing.
        let backWidth =
            hidesBack
            ? 0
            : measureChild(
                backButton(back, coordinator: coordinator),
                proposal: ProposedSize(width: nil, height: nil),
                context: barContext.withChildIdentity(type: NavigationBarID.self)
            ).width
        // Crumbs when they fit, the Back button when they do not. `backWidth`
        // is what a bar with the single button would need, so it doubles as the
        // budget the trail has to beat.
        coordinator.recordTitle(title, atDepth: coordinator.depth)
        // With the button hidden the trail goes too: every crumb in it pops, so
        // keeping it would leave three ways back where the screen asked for
        // none. The title then has the whole bar rather than what the button
        // left it.
        let titled = navigationBar(
            back: back,
            hidesBack: hidesBack,
            title: title.truncatedToWidth(max(0, width - backWidth - 1)),
            crumbs: hidesBack
                ? nil
                : NavigationCrumbs.trail(
                    titles: coordinator.titles(upTo: coordinator.depth), fittingWidth: width),
            coordinator: coordinator)

        let rendered = TUIkit.renderToBuffer(
            titled, context: barContext.withChildIdentity(type: NavigationBarID.self))
        return padded(rendered, toWidth: width, height: Self.barHeight)
    }

    /// The bar's view: the crumb trail (or the Back button and title when the
    /// trail will not fit), and the rule beneath.
    private func navigationBar(
        back: String, hidesBack: Bool, title: String, crumbs: [NavigationCrumbs.Crumb]?,
        coordinator: NavigationCoordinator
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                if let crumbs {
                    // One closure parameter, NOT `{ _, crumb in`. The closure is
                    // not the bug: `{ _, crumb in` is converted to a function of
                    // one tuple parameter, and swift.org's Swift 6.2.4 (an
                    // assertions build) aborts in SILGen ("no generic
                    // environment provided for type with type parameters") on a
                    // function conversion that needs a reabstraction thunk, in
                    // a generic context (`Root`), of a function whose opaque
                    // result does not use that context's parameters
                    // (`crumbView`). One parameter needs no conversion. Xcode's
                    // 6.2.4 compiles either spelling. See
                    // Tools/CompilerBugs/README.md, section 4.
                    ForEach(Array(crumbs.enumerated()), id: \.offset) { pair in
                        crumbView(pair.element, coordinator: coordinator)
                    }
                } else if hidesBack {
                    Text(title).bold()
                } else {
                    backButton(back, coordinator: coordinator)
                    Text(" ")
                    Text(title).bold()
                }
                Spacer()
            }
            Divider()
        }
    }

    /// A crumb: a `Button` when it goes somewhere, plain text when it is the
    /// separator or the screen you are already on.
    ///
    /// Only the clickable ones are Buttons, so only they are Tab stops — the
    /// separators would otherwise put dead entries in the focus ring, and the
    /// current screen is not somewhere to navigate to.
    ///
    /// Three weights, loudest last: the punctuation recedes, a screen you can
    /// go back to is quiet until the focus or the pointer lifts it
    /// (``_NavigationCrumbButtonStyle``), and the screen you are on is bold.
    @ViewBuilder
    private func crumbView(_ crumb: NavigationCrumbs.Crumb, coordinator: NavigationCoordinator) -> some View {
        if let depth = crumb.popsTo {
            // The lead rides in the label: this style reserves no cells of its
            // own, so nothing else would space the trail.
            Button(NavigationCrumbs.lead + crumb.label) { coordinator.pop(coordinator.depth - depth) }
                .buttonStyle(_NavigationCrumbButtonStyle())
        } else if crumb.isChrome {
            Text(NavigationCrumbs.lead + crumb.label)
                .foregroundStyle(Color.palette.foregroundTertiary)
        } else {
            Text(NavigationCrumbs.lead + crumb.label).bold()
        }
    }

    /// The **‹ Back** control — a real `Button`, so it is a Tab stop, it takes
    /// a click, and `.buttonStyle(_:)` above the stack restyles it.
    private func backButton(_ label: String, coordinator: NavigationCoordinator) -> some View {
        Button(label) { coordinator.pop() }
            .buttonStyle(.plain)
    }

    /// Pads (or clips) a buffer to exactly `width` × `height`, keeping its
    /// overlays and hit-test regions — `replacingLines` is what preserves them.
    private func padded(_ buffer: FrameBuffer, toWidth width: Int, height: Int) -> FrameBuffer {
        var lines = buffer.lines.prefix(height).map { line -> String in
            let visible = line.strippedLength
            return visible < width ? line + String(repeating: " ", count: width - visible) : line
        }
        let blank = String(repeating: " ", count: width)
        while lines.count < height { lines.append(blank) }
        return buffer.replacingLines(Array(lines))
    }
}

// MARK: - Identity tags

/// Identity tag for the pushed screen, so every screen in a stack shares one
/// identity slot: pushing a second screen of the same shape must not inherit
/// the first one's `@State`, and coming back must not find the screen's state
/// filed under the destination view's type.
private enum NavigationScreen {}

/// Identity tag for the navigation bar, keeping the Back button's focus
/// registration in one stable place across pushes.
private enum NavigationBarID {}
