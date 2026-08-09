//  🖥️ TUIKit — Terminal UI Kit for Swift
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
/// the top of the path, under a one-line navigation bar carrying a **‹ Back**
/// button and the screen's ``navigationTitle(_:)``. Going back is a click on
/// that button, Return/Space with it focused, **Escape**, or
/// `@Environment(\.dismiss)` from anywhere in the pushed screen.
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
        if !context.isMeasuring {
            _ = TUIkit.renderToBuffer(
                root,
                context: base.isolatedForBackground()
                    .withChildIdentity(type: type(of: root)))
        }

        return renderScreen(top: top, context: base)
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

        // Collect the screen's own preferences so the bar can read the title it
        // set — and only the title IT set, not one an ancestor published.
        let preferences = screenContext.environment.preferenceStorage
        preferences?.push()
        var content =
            coordinator.destination(for: top).map {
                TUIkit.renderToBuffer(
                    $0, context: screenContext.withChildIdentity(type: NavigationScreen.self))
            } ?? FrameBuffer()
        let title = preferences?.pop()[NavigationTitleKey.self] ?? ""

        content = padded(content, toWidth: width, height: contentHeight)

        var buffer = renderBar(title: title, width: width, context: context)
        buffer.appendVertically(content)
        return buffer
    }

    /// The navigation bar, pinned to ``barHeight`` rows.
    private func renderBar(title: String, width: Int, context: RenderContext) -> FrameBuffer {
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
        if !context.isMeasuring {
            barContext.environment.statusBar.escapeLabelOverride = "go back"
            barContext.environment.statusBar.escapeClaimGrabsInput = false
            barContext.environment.keyEventDispatcher?.addHandler(
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
        let backWidth = measureChild(
            backButton(back, coordinator: coordinator),
            proposal: ProposedSize(width: nil, height: nil),
            context: barContext.withChildIdentity(type: NavigationBarID.self)
        ).width
        let titled = navigationBar(
            back: back,
            title: title.truncatedToWidth(max(0, width - backWidth - 1)),
            coordinator: coordinator)

        let rendered = TUIkit.renderToBuffer(
            titled, context: barContext.withChildIdentity(type: NavigationBarID.self))
        return padded(rendered, toWidth: width, height: Self.barHeight)
    }

    /// The bar's view: back button, title, and the rule beneath them.
    private func navigationBar(
        back: String, title: String, coordinator: NavigationCoordinator
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                backButton(back, coordinator: coordinator)
                Text(title)
                    .bold()
                Spacer()
            }
            Divider()
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
