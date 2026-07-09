//  🖥️ TUIKit — Terminal UI Kit for Swift
//  View+Events.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Key Press

extension View {
    /// Adds a handler for key press events.
    ///
    /// The handler is called when any key is pressed while this view
    /// is in the view hierarchy. Return `true` to consume the event,
    /// or `false` to let it propagate to other handlers.
    ///
    /// # Example
    ///
    /// ```swift
    /// Text("Press any key")
    ///     .onKeyPress { event in
    ///         if event.key == .enter {
    ///             doSomething()
    ///             return true  // Consumed
    ///         }
    ///         return false  // Let others handle it
    ///     }
    /// ```
    ///
    /// - Parameter handler: The handler to call on key press. Returns true if handled.
    /// - Returns: A view that handles key presses.
    public func onKeyPress(_ handler: @escaping (KeyEvent) -> Bool) -> some View {
        KeyPressModifier(content: self, keys: nil, handler: handler)
    }

    /// Adds a handler for specific key press events.
    ///
    /// # Example
    ///
    /// ```swift
    /// Text("Use arrow keys")
    ///     .onKeyPress(keys: [.up, .down]) { event in
    ///         if event.key == .up {
    ///             moveUp()
    ///         } else {
    ///             moveDown()
    ///         }
    ///         return true
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - keys: The keys to listen for.
    ///   - handler: The handler to call on key press. Returns true if handled.
    /// - Returns: A view that handles specific key presses.
    public func onKeyPress(keys: Set<Key>, handler: @escaping (KeyEvent) -> Bool) -> some View {
        KeyPressModifier(content: self, keys: keys, handler: handler)
    }

    /// Adds a handler for a single key press.
    ///
    /// This handler always consumes the event when the specified key is pressed.
    ///
    /// # Example
    ///
    /// ```swift
    /// Text("Press Enter to continue")
    ///     .onKeyPress(.enter) {
    ///         continueAction()
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - key: The key to listen for.
    ///   - action: The action to perform.
    /// - Returns: A view that handles the specific key press.
    public func onKeyPress(_ key: Key, action: @escaping () -> Void) -> some View {
        KeyPressModifier(
            content: self,
            keys: [key],
            handler: { _ in
                action()
                return true
            }
        )
    }
}

// MARK: - Mouse

extension View {
    /// Adds a handler for raw mouse events landing on this view.
    ///
    /// The handler is called with the event in screen coordinates
    /// (relative to the terminal viewport) whenever a mouse event
    /// lands inside this view's rendered bounds. Return `true` to
    /// claim the event — for a `.pressed` event that also captures
    /// the subsequent drag, so the modifier keeps receiving
    /// `.dragged` and `.released` events for the same button even if
    /// the cursor wanders off-view.
    ///
    /// ```swift
    /// Text("Drag me")
    ///     .onMouseEvent { event in
    ///         switch event.phase {
    ///         case .pressed: pressed = true
    ///         case .released: pressed = false
    ///         default: break
    ///         }
    ///         return true
    ///     }
    /// ```
    ///
    /// - Parameter handler: The handler. Returns `true` if consumed.
    /// - Returns: A view that handles mouse events landing on it.
    public func onMouseEvent(_ handler: @escaping (MouseEvent) -> Bool) -> some View {
        OnMouseEventModifier(content: self, handler: handler)
    }

    /// Adds an action that fires on a left-click inside this view.
    ///
    /// Equivalent to listening for a `.released` event of the left
    /// button after a matching `.pressed` event on the same view.
    /// The action receives the absolute screen position of the click.
    ///
    /// ```swift
    /// Text("Click me")
    ///     .onTapGesture { _ in clicked() }
    /// ```
    ///
    /// - Parameter action: The action to run on click. Receives the
    ///   `(x, y)` of the release.
    /// - Returns: A view that consumes left-click releases.
    public func onTapGesture(_ action: @escaping (_ x: Int, _ y: Int) -> Void) -> some View {
        onMouseEvent { event in
            if event.button == .left, event.phase == .released {
                action(event.x, event.y)
                return true
            }
            // Still claim the press so the dispatcher routes the
            // release back to us even if the cursor moves off-view
            // during the drag.
            if event.button == .left, event.phase == .pressed {
                return true
            }
            return false
        }
    }

    /// Adds an action that fires when this view is tapped `count` times in quick
    /// succession — e.g. `count: 2` for a double-click.
    ///
    /// Mirrors SwiftUI's `onTapGesture(count:perform:)`. The dispatcher
    /// synthesises the click count by timing successive left-button clicks at
    /// (near) the same cell (see ``TUIkitCore/MouseEvent/clickCount``); the
    /// action runs on the release of the `count`-th click. A `count: 1` tap
    /// behaves like ``onTapGesture(_:)`` but without the `(x, y)` arguments.
    ///
    /// ```swift
    /// Text(folder.name)
    ///     .onTapGesture(count: 2) { open(folder) }
    /// ```
    ///
    /// - Parameters:
    ///   - count: The number of taps that triggers the action (clamped to ≥ 1).
    ///   - action: The action to run once `count` taps land on this view.
    /// - Returns: A view that consumes left-click presses/releases and fires
    ///   `action` on the matching multi-click.
    public func onTapGesture(count: Int, perform action: @escaping () -> Void) -> some View {
        onMouseEvent { event in
            guard event.button == .left else { return false }
            switch event.phase {
            case .pressed:
                return true  // claim so the release routes back to us
            case .released:
                if event.clickCount == max(1, count) {
                    action()
                }
                return true
            default:
                return false
            }
        }
    }

    /// Adds an action that fires on a scroll wheel tick inside this
    /// view's bounds.
    ///
    /// `delta` is `+1` for upward / leftward scrolls and `-1` for
    /// downward / rightward, matching the sign convention scroll
    /// widgets (Lists, Tables) already use.
    ///
    /// - Parameter action: The action to run on each tick. The
    ///   `direction` argument tells you whether the wheel was scrolled
    ///   `.up` (toward content moving down) or `.down` (toward
    ///   content moving up), or sideways via `.left` / `.right`.
    /// - Returns: A view that consumes scroll events landing on it.
    public func onScrollGesture(
        _ action: @escaping (_ direction: ScrollDirection) -> Void
    ) -> some View {
        onMouseEvent { event in
            guard event.phase == .scrolled else { return false }
            switch event.button {
            case .scrollUp: action(.up)
            case .scrollDown: action(.down)
            case .scrollLeft: action(.left)
            case .scrollRight: action(.right)
            default: return false
            }
            return true
        }
    }

    /// Adds an action that fires while the user drags the left mouse
    /// button across this view.
    ///
    /// The action is invoked for every `.dragged` event between the
    /// initial `.pressed` and the matching `.released`, so the
    /// handler is in continuous control of whatever it's animating
    /// (a slider's value, a moving cursor, …). The first call carries
    /// `phase == .began`, intermediate calls carry `phase == .moved`,
    /// and the final call carries `phase == .ended`.
    public func onDragGesture(
        _ action: @escaping (DragGestureEvent) -> Void
    ) -> some View {
        DragGestureModifier(content: self, action: action)
    }
}

/// Direction of a scroll-wheel tick reported to ``View/onScrollGesture(_:)``.
public enum ScrollDirection: Sendable, Equatable {
    case up
    case down
    case left
    case right
}

/// The state delivered to ``View/onDragGesture(_:)`` for each drag step.
public struct DragGestureEvent: Sendable, Equatable {
    /// Where the gesture is in its lifecycle.
    public enum Phase: Sendable, Equatable {
        case began
        case moved
        case ended
    }

    /// The current phase.
    public let phase: Phase

    /// The cursor's current absolute screen position.
    public let x: Int
    public let y: Int

    /// The absolute screen position where the gesture began.
    public let startX: Int
    public let startY: Int

    /// The displacement from the gesture's starting position.
    public var translationX: Int { x - startX }
    public var translationY: Int { y - startY }
}

// MARK: - Value Change

extension View {
    /// Adds an action to perform when the given value changes.
    ///
    /// The action receives both the old and new values. Use this to react
    /// to state changes, for example to validate input or trigger side effects.
    ///
    /// # Example
    ///
    /// ```swift
    /// struct ContentView: View {
    ///     @State var selection = 0
    ///
    ///     var body: some View {
    ///         List(selection: $selection) { ... }
    ///             .onChange(of: selection) { oldValue, newValue in
    ///                 loadDetails(for: newValue)
    ///             }
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - value: The value to observe for changes.
    ///   - initial: Whether to call the action on the first render pass.
    ///     When `true`, the action fires immediately with `oldValue == newValue`.
    ///     Defaults to `false`.
    ///   - action: The action to perform when the value changes, receiving
    ///     the old and new values.
    /// - Returns: A view that triggers an action on value changes.
    public func onChange<V: Equatable>(
        of value: V,
        initial: Bool = false,
        _ action: @escaping (V, V) -> Void
    ) -> some View {
        OnChangeModifier(content: self, value: value, initial: initial, action: action)
    }

    /// Adds an action to perform when the given value changes.
    ///
    /// This variant does not receive the old or new values. Use it when
    /// you only need to know that a change occurred.
    ///
    /// # Example
    ///
    /// ```swift
    /// Text("Count: \(count)")
    ///     .onChange(of: count) {
    ///         playSound()
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - value: The value to observe for changes.
    ///   - initial: Whether to call the action on the first render pass.
    ///     Defaults to `false`.
    ///   - action: The action to perform when the value changes.
    /// - Returns: A view that triggers an action on value changes.
    public func onChange<V: Equatable>(
        of value: V,
        initial: Bool = false,
        _ action: @escaping () -> Void
    ) -> some View {
        OnChangeModifier(content: self, value: value, initial: initial) { _, _ in action() }
    }
}

// MARK: - Lifecycle

extension View {
    /// Executes an action when this view first appears.
    ///
    /// The action is only executed once per view appearance. If the view
    /// is removed and then added again, the action will execute again.
    ///
    /// # Example
    ///
    /// ```swift
    /// struct ContentView: View {
    ///     var body: some View {
    ///         Text("Hello")
    ///             .onAppear {
    ///                 loadData()
    ///             }
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter action: The action to execute.
    /// - Returns: A view that executes the action on appearance.
    public func onAppear(perform action: @escaping () -> Void) -> some View {
        OnAppearModifier(
            content: self,
            action: action
        )
    }

    /// Executes an action when this view disappears.
    ///
    /// The action is executed when the view is no longer rendered.
    ///
    /// # Example
    ///
    /// ```swift
    /// struct ContentView: View {
    ///     var body: some View {
    ///         Text("Hello")
    ///             .onDisappear {
    ///                 cleanup()
    ///             }
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter action: The action to execute.
    /// - Returns: A view that executes the action on disappearance.
    public func onDisappear(perform action: @escaping () -> Void) -> some View {
        OnDisappearModifier(
            content: self,
            action: action
        )
    }

    /// Starts an async task when this view appears.
    ///
    /// The task is automatically cancelled when the view disappears.
    ///
    /// # Example
    ///
    /// ```swift
    /// struct ContentView: View {
    ///     var body: some View {
    ///         Text("Loading...")
    ///             .task {
    ///                 await fetchData()
    ///             }
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - priority: The task priority (default: .userInitiated).
    ///   - action: The async action to execute.
    /// - Returns: A view that starts the task on appearance.
    public func task(
        priority: TaskPriority = .userInitiated,
        _ action: @escaping @Sendable () async -> Void
    ) -> some View {
        TaskModifier(
            content: self,
            task: action,
            priority: priority,
            idToken: nil
        )
    }

    /// Starts an async task tied to an identifier, restarting it when the
    /// identifier changes.
    ///
    /// The task starts when the view appears, is cancelled when it disappears,
    /// and — unlike ``task(priority:_:)`` — is cancelled and **restarted**
    /// whenever `id` changes. Mirrors SwiftUI's `task(id:priority:_:)`; use it to
    /// re-run async work when an input changes (a search query, a selected row)
    /// without hand-rolling `onChange` + cancellation.
    ///
    /// # Example
    ///
    /// ```swift
    /// Text(results)
    ///     .task(id: query) {
    ///         results = await search(query)
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - id: A value whose change restarts the task.
    ///   - priority: The task priority (default: .userInitiated).
    ///   - action: The async action to execute.
    /// - Returns: A view that (re)starts the task when `id` changes.
    public func task<ID: Equatable>(
        id value: ID,
        priority: TaskPriority = .userInitiated,
        _ action: @escaping @Sendable () async -> Void
    ) -> some View {
        TaskModifier(
            content: self,
            task: action,
            priority: priority,
            idToken: "\(value)"
        )
    }
}

// MARK: - Status Bar Items

extension View {
    /// Sets the status bar items for this view.
    ///
    /// When this view is rendered, the specified items will be displayed
    /// in the status bar. This replaces any existing global items.
    ///
    /// If a user item uses the same shortcut string as a system item
    /// (for example `q`), the user item wins in both display and event
    /// handling for that view context.
    ///
    /// # Example
    ///
    /// ```swift
    /// struct MainView: View {
    ///     var body: some View {
    ///         VStack {
    ///             Text("Main Content")
    ///         }
    ///         .statusBarItems([
    ///             StatusBarItem(shortcut: "q", label: "quit"),
    ///             StatusBarItem(shortcut: "h", label: "help") { showHelp() }
    ///         ])
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter items: The status bar items to display.
    /// - Returns: A view that sets the specified status bar items.
    public func statusBarItems(_ items: [any StatusBarItemProtocol]) -> some View {
        StatusBarItemsModifier(content: self, items: items, composition: .merge, context: nil)
    }

    /// Declares status bar items for this view using a builder.
    ///
    /// When used inside a `.focusSection()`, items are composed with parent
    /// items using the `.merge` strategy (default). Use
    /// ``statusBarItems(_:_:)`` to specify a different strategy.
    ///
    /// A user-defined item can intentionally override a system shortcut such
    /// as `q`. When the item has an action, it intercepts the key before the
    /// built-in quit binding runs.
    ///
    /// # Example
    ///
    /// ```swift
    /// VStack {
    ///     Text("Main Content")
    /// }
    /// .statusBarItems {
    ///     StatusBarItem(shortcut: "q", label: "quit")
    ///     StatusBarItem(shortcut: "h", label: "help") { showHelp() }
    /// }
    /// ```
    ///
    /// - Parameter builder: A closure that returns the status bar items.
    /// - Returns: A view that declares the specified status bar items.
    public func statusBarItems(
        @StatusBarItemBuilder _ builder: () -> [any StatusBarItemProtocol]
    ) -> some View {
        StatusBarItemsModifier(content: self, items: builder(), composition: .merge, context: nil)
    }

    /// Declares status bar items with a specific composition strategy.
    ///
    /// - **`.merge`** (default): Items are combined with parent items.
    ///   Child wins on shortcut conflict.
    /// - **`.replace`**: Items replace all parent items (cascade barrier).
    ///
    /// Shortcut conflicts are resolved in favor of the most local user item.
    /// This also applies to system shortcuts such as `q`.
    ///
    /// # Example
    ///
    /// ```swift
    /// // Modal: replace all parent items
    /// SettingsView()
    ///     .focusSection("settings")
    ///     .statusBarItems(.replace) {
    ///         StatusBarItem(shortcut: Shortcut.escape, label: "close")
    ///         StatusBarItem(shortcut: Shortcut.enter, label: "confirm")
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - composition: How to compose with parent items.
    ///   - builder: A closure that returns the status bar items.
    /// - Returns: A view that declares the specified status bar items.
    public func statusBarItems(
        _ composition: StatusBarItemComposition,
        @StatusBarItemBuilder _ builder: () -> [any StatusBarItemProtocol]
    ) -> some View {
        StatusBarItemsModifier(content: self, items: builder(), composition: composition, context: nil)
    }

    /// Sets the status bar items for this view with a named context.
    ///
    /// This is the legacy push/pop API. Prefer using `.statusBarItems { ... }`
    /// with `.focusSection()` for declarative composition.
    ///
    /// - Parameters:
    ///   - context: A unique identifier for this context.
    ///   - builder: A closure that returns the status bar items.
    /// - Returns: A view that pushes status bar items to the context stack.
    public func statusBarItems(
        context: String,
        @StatusBarItemBuilder _ builder: () -> [any StatusBarItemProtocol]
    ) -> some View {
        StatusBarItemsModifier(content: self, items: builder(), composition: .merge, context: context)
    }

    /// Sets the status bar items for this view with a named context.
    ///
    /// This is the legacy push/pop API. Prefer using `.statusBarItems()` with
    /// `.focusSection()` for declarative composition.
    ///
    /// - Parameters:
    ///   - context: A unique identifier for this context.
    ///   - items: The status bar items to display.
    /// - Returns: A view that pushes status bar items to the context stack.
    public func statusBarItems(
        context: String,
        items: [any StatusBarItemProtocol]
    ) -> some View {
        StatusBarItemsModifier(content: self, items: items, composition: .merge, context: context)
    }

    // MARK: - Focus Sections

    /// Declares this view as a focus section.
    ///
    /// A focus section is a named, focusable area of the UI. Interactive children
    /// (buttons, menus) within this section are grouped together. Users cycle
    /// between sections with Tab/Shift+Tab.
    ///
    /// Focus sections are **declarative** — they are registered during rendering,
    /// not added/removed imperatively. The `FocusManager` tracks which section
    /// is active and routes focus events accordingly.
    ///
    /// # Example
    ///
    /// ```swift
    /// HStack {
    ///     PlaylistView()
    ///         .focusSection("playlist")
    ///         .statusBarItems {
    ///             StatusBarItem(shortcut: Shortcut.enter, label: "play")
    ///         }
    ///
    ///     TrackListView()
    ///         .focusSection("tracklist")
    ///         .statusBarItems {
    ///             StatusBarItem(shortcut: Shortcut.enter, label: "select")
    ///         }
    /// }
    /// ```
    ///
    /// - Parameter id: A unique identifier for this section.
    /// - Returns: A view that registers a focus section during rendering.
    public func focusSection(_ id: String) -> some View {
        FocusSectionModifier(content: self, sectionID: id)
    }
}
