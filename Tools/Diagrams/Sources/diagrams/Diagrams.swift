import Foundation

/// Every diagram this tool can render. Add a new one here and re-run.
///
/// A diagram's content is documentation: keep it in step with the prose of the
/// matching DocC article and with the code it describes.
let allDiagrams: [Diagram] = [
    lifecycleMainLoop,
    architectureEventLoop,
    lifecycleSubsystemInit,
    lifecycleRunCreates,
    keyboardEventDispatch,
    renderCyclePipeline,
    renderCycleDispatch,
    depGraphOwnership,
    depGraphReferences,
]

/// AppLifecycle.md — setup, the demand-driven main loop, and teardown.
let lifecycleMainLoop = Diagram(
    name: "lifecycle-main-loop",
    title: "TUIkit application lifecycle and demand-driven main loop",
    nodes: [
        Node(id: "setup", title: "Terminal setup",
             detail: ["install signals · alt screen · raw mode · mouse"], kind: .terminal),
        Node(id: "observers", title: "Register observers",
             detail: ["AppState → requestRerender · focus → wake()"]),
        Node(id: "timers", title: "Prepare animation timers",
             detail: ["Pulse · Cursor — started on demand"]),
        Node(id: "initial", title: "Render first frame"),
        Node(id: "shutdown", title: "shouldShutdown?", kind: .decision),
        Node(id: "resize", title: "Consume resize flag",
             detail: ["SIGWINCH → invalidate diff cache"]),
        Node(id: "input", title: "Drain & dispatch input",
             detail: ["≤128/frame · keys: 5 layers + 2 stages · mouse: hit-test"]),
        Node(id: "render", title: "Render if a frame is due",
             detail: ["at most once per App.maxFrameRate"]),
        Node(id: "block", title: "Block until woken",
             detail: ["input · render request · signal"], kind: .accent),
        Node(id: "cleanup", title: "Cleanup & exit",
             detail: ["restore terminal · show cursor"], kind: .terminal),
    ],
    edges: [
        Edge("setup", "observers"),
        Edge("observers", "timers"),
        Edge("timers", "initial"),
        Edge("initial", "shutdown"),
        Edge("shutdown", "resize", label: "no"),
        Edge("shutdown", "cleanup", label: "yes"),
        Edge("resize", "input"),
        Edge("input", "render"),
        Edge("render", "block"),
        Edge("block", "shutdown", label: "loop", loop: true),
    ]
)

/// Architecture.md — the demand-driven, frame-capped event loop.
let architectureEventLoop = Diagram(
    name: "architecture-event-loop",
    title: "TUIkit demand-driven, frame-capped event loop",
    nodes: [
        Node(id: "init", title: "Subsystems initialised",
             detail: ["Terminal · AppState · Focus · TUIContext",
                      "RenderLoop · InputHandler · signal handlers"], kind: .terminal),
        Node(id: "shutdown", title: "shouldShutdown?", kind: .decision),
        Node(id: "resize", title: "Consume resize flag",
             detail: ["SIGWINCH → invalidate diff cache"]),
        Node(id: "input", title: "Drain & dispatch input",
             detail: ["≤128/frame · keys → 5 layers + 2 stages · mouse → hit-test"]),
        Node(id: "render", title: "Render if a frame is due",
             detail: ["coalesce requests · ≤ App.maxFrameRate"]),
        Node(id: "block", title: "Block until woken",
             detail: ["input · render request · signal (self-pipe)"], kind: .accent),
        Node(id: "cleanup", title: "Cleanup & exit",
             detail: ["restore the terminal"], kind: .terminal),
    ],
    edges: [
        Edge("init", "shutdown"),
        Edge("shutdown", "resize", label: "no"),
        Edge("shutdown", "cleanup", label: "yes"),
        Edge("resize", "input"),
        Edge("input", "render"),
        Edge("render", "block"),
        Edge("block", "shutdown", label: "loop", loop: true),
    ]
)

/// AppLifecycle.md — what `AppRunner.init()` creates and wires (the TUIContext
/// services are grouped in the box).
let lifecycleSubsystemInit = Diagram(
    name: "lifecycle-subsystem-init",
    title: "TUIkit subsystem initialisation",
    nodes: [
        Node(id: "main", title: "@main", kind: .terminal),
        Node(id: "appMain", title: "App.main()"),
        Node(id: "inst", title: "Self()", detail: ["make the app instance"]),
        Node(id: "init", title: "AppRunner.init()", kind: .accent),
        Node(id: "terminal", title: "Terminal"),
        Node(id: "appState", title: "AppState"),
        Node(id: "statusBar", title: "StatusBarState"),
        Node(id: "appHeader", title: "AppHeaderState"),
        Node(id: "focus", title: "FocusManager"),
        Node(id: "themes", title: "ThemeManager ×2", detail: ["palette · appearance"]),
        Node(id: "tuiContext", title: "TUIContext"),
        Node(id: "lifecycle", title: "LifecycleManager"),
        Node(id: "keyDispatch", title: "KeyEventDispatcher"),
        Node(id: "prefs", title: "PreferenceStorage"),
        Node(id: "stateStore", title: "StateStorage"),
        Node(id: "cache", title: "RenderCache"),
    ],
    edges: [
        Edge("main", "appMain"), Edge("appMain", "inst"), Edge("inst", "init"),
        Edge("init", "terminal"), Edge("init", "appState"), Edge("init", "statusBar"),
        Edge("init", "appHeader"), Edge("init", "focus"), Edge("init", "themes"),
        Edge("init", "tuiContext"),
        Edge("tuiContext", "lifecycle"), Edge("tuiContext", "keyDispatch"),
        Edge("tuiContext", "prefs"), Edge("tuiContext", "stateStore"), Edge("tuiContext", "cache"),
    ],
    rankdir: "LR",
    clusters: [Cluster(label: "", nodes: ["lifecycle", "keyDispatch", "prefs", "stateStore", "cache"])]
)

/// AppLifecycle.md — what `AppRunner.run()` creates before entering the loop.
let lifecycleRunCreates = Diagram(
    name: "lifecycle-run-creates",
    title: "Components created by AppRunner.run()",
    nodes: [
        Node(id: "run", title: "AppRunner.run()", kind: .accent),
        Node(id: "input", title: "InputHandler"),
        Node(id: "render", title: "RenderLoop"),
        Node(id: "pulse", title: "PulseTimer", detail: ["100 ms"]),
        Node(id: "cursor", title: "CursorTimer", detail: ["50 ms"]),
    ],
    edges: [
        Edge("run", "input"), Edge("run", "render"),
        Edge("run", "pulse"), Edge("run", "cursor"),
    ]
)

/// KeyboardShortcuts.md + Architecture.md + AppLifecycle.md — the five-layer
/// keyboard dispatch with its two refinement stages: the modal-claimed ESC
/// pre-route (before Layer 1) and the semantic-shortcut Layer 3.5 (default /
/// cancel action, between Layers 3 and 4) — plus the two `hasTextInputFocus`
/// gates that switch Layer 0 on and Layer 3 off. Mirrors
/// `InputHandler.handle(_:)`.
let keyboardEventDispatch = Diagram(
    name: "keyboard-event-dispatch",
    title: "Keyboard event dispatch — five layers + two refinement stages",
    nodes: [
        Node(id: "ev", title: "KeyEvent", kind: .terminal),
        Node(id: "g0", title: "text input focused?", kind: .decision),
        Node(id: "l0", title: "Layer 0 · Text input",
             detail: ["focusManager.dispatchKeyEvent", "TextField / SecureField / TextEditor"]),
        Node(id: "gesc", title: "ESC claimed by an open surface?", kind: .decision),
        Node(id: "pre", title: "ESC pre-route · Focus system",
             detail: ["open drop-down closes FIRST", "before any page-level handler"]),
        Node(id: "l1", title: "Layer 1 · Status bar items", detail: ["shortcut-triggered actions"]),
        Node(id: "l2", title: "Layer 2 · View handlers", detail: [".onKeyPress · deepest view first"]),
        Node(id: "g3", title: "still has text focus?", kind: .decision),
        Node(id: "l3", title: "Layer 3 · Focus system",
             detail: ["focused element · Tab / Shift+Tab", "arrow-key fallback"]),
        Node(id: "l35", title: "Layer 3.5 · Semantic shortcuts",
             detail: ["Return → default button", "Escape → cancel button"]),
        Node(id: "l4", title: "Layer 4 · Default bindings",
             detail: ["quit (always) · theme · appearance", "chrome gated while a modal grabs input"]),
        Node(id: "drop", title: "Unmatched → dropped", kind: .terminal),
    ],
    edges: [
        Edge("ev", "g0"),
        Edge("g0", "l0", label: "yes"),
        Edge("g0", "gesc", label: "no"),
        // With text focus, the ESC pre-route is skipped (Layer 0 already
        // routed through the focus system).
        Edge("l0", "l1"),
        Edge("gesc", "pre", label: "yes"),
        Edge("gesc", "l1", label: "no"),
        Edge("pre", "l1"),
        Edge("l1", "l2"),
        Edge("l2", "g3"),
        Edge("g3", "l35", label: "yes — skip L3"),
        Edge("g3", "l3", label: "no"),
        Edge("l3", "l35"),
        Edge("l35", "l4"),
        Edge("l4", "drop"),
    ]
)

/// RenderCycle.md — the twelve steps inside `RenderLoop.render()`.
let renderCyclePipeline = Diagram(
    name: "render-cycle-pipeline",
    title: "The twelve-step render pipeline",
    nodes: [
        Node(id: "s1", title: "1 · Clear per-frame state", detail: ["handlers · prefs · focus · bars"]),
        Node(id: "s2", title: "2 · Begin tracking", detail: ["lifecycle · state · cache"]),
        Node(id: "s3", title: "3 · Build environment", detail: ["subsystem values + services"]),
        Node(id: "s4", title: "4 · Create render context"),
        Node(id: "s5", title: "5 · Evaluate scene"),
        Node(id: "s6", title: "6 · Render view tree"),
        Node(id: "s7", title: "7 · Build output lines"),
        Node(id: "s8", title: "8 · Begin buffered frame"),
        Node(id: "s9", title: "9 · App header + diff content"),
        Node(id: "s10", title: "10 · Render status bar"),
        Node(id: "s11", title: "11 · Flush frame", detail: ["one write() syscall"]),
        Node(id: "s12", title: "12 · End tracking", detail: ["onDisappear · state GC · cache cleanup"]),
    ],
    edges: [
        Edge("s1", "s2"), Edge("s2", "s3"), Edge("s3", "s4"), Edge("s4", "s5"),
        Edge("s5", "s6"), Edge("s6", "s7"), Edge("s7", "s8"), Edge("s8", "s9"),
        Edge("s9", "s10"), Edge("s10", "s11"), Edge("s11", "s12"),
    ]
)

/// RenderCycle.md — how `renderToBuffer` chooses procedural vs. body rendering.
let renderCycleDispatch = Diagram(
    name: "render-cycle-dispatch",
    title: "renderToBuffer dispatch",
    nodes: [
        Node(id: "rtb", title: "renderToBuffer(view)", kind: .accent),
        Node(id: "qr", title: "Renderable?", kind: .decision),
        Node(id: "proc", title: "renderToBuffer(context:)", detail: ["procedural — leaves, _*Core"]),
        Node(id: "qb", title: "has a body?", kind: .decision),
        Node(id: "recurse", title: "Recurse into body", detail: ["compose child views"]),
        Node(id: "empty", title: "Empty buffer", kind: .terminal),
    ],
    edges: [
        Edge("rtb", "qr"),
        Edge("qr", "proc", label: "yes"),
        Edge("qr", "qb", label: "no"),
        Edge("qb", "recurse", label: "yes"),
        Edge("qb", "empty", label: "no"),
    ]
)

/// AppLifecycle.md — who owns what at runtime (AppRunner owns everything; the
/// TUIContext services are grouped; SignalManager signals back to AppRunner).
let depGraphOwnership = Diagram(
    name: "dep-graph-ownership",
    title: "Runtime ownership graph",
    nodes: [
        Node(id: "runner", title: "AppRunner", kind: .accent),
        Node(id: "signal", title: "SignalManager"),
        Node(id: "terminal", title: "Terminal"),
        Node(id: "appState", title: "AppState"),
        Node(id: "statusBar", title: "StatusBarState"),
        Node(id: "appHeader", title: "AppHeaderState"),
        Node(id: "focus", title: "FocusManager"),
        Node(id: "themes", title: "ThemeManager ×2"),
        Node(id: "tuiContext", title: "TUIContext"),
        Node(id: "input", title: "InputHandler"),
        Node(id: "render", title: "RenderLoop"),
        Node(id: "pulse", title: "PulseTimer"),
        Node(id: "cursor", title: "CursorTimer"),
        Node(id: "lifecycle", title: "LifecycleManager"),
        Node(id: "keyDispatch", title: "KeyEventDispatcher"),
        Node(id: "prefs", title: "PreferenceStorage"),
        Node(id: "stateStore", title: "StateStorage"),
        Node(id: "cache", title: "RenderCache"),
    ],
    edges: [
        Edge("runner", "signal"), Edge("runner", "terminal"), Edge("runner", "appState"),
        Edge("runner", "statusBar"), Edge("runner", "appHeader"), Edge("runner", "focus"),
        Edge("runner", "themes"), Edge("runner", "tuiContext"), Edge("runner", "input"),
        Edge("runner", "render"), Edge("runner", "pulse"), Edge("runner", "cursor"),
        Edge("tuiContext", "lifecycle"), Edge("tuiContext", "keyDispatch"),
        Edge("tuiContext", "prefs"), Edge("tuiContext", "stateStore"), Edge("tuiContext", "cache"),
        Edge("signal", "runner", label: "SIGINT · SIGWINCH", loop: true, dashed: true),
    ],
    rankdir: "LR",
    clusters: [Cluster(label: "", nodes: ["lifecycle", "keyDispatch", "prefs", "stateStore", "cache"])]
)

/// AppLifecycle.md — the main runtime references during a frame (dashed = "uses",
/// not "owns").
let depGraphReferences = Diagram(
    name: "dep-graph-references",
    title: "Runtime reference graph",
    nodes: [
        Node(id: "render", title: "RenderLoop", kind: .accent),
        Node(id: "input", title: "InputHandler", kind: .accent),
        Node(id: "terminal", title: "Terminal"),
        Node(id: "statusBar", title: "StatusBarState"),
        Node(id: "appHeader", title: "AppHeaderState"),
        Node(id: "focus", title: "FocusManager"),
        Node(id: "themes", title: "ThemeManager ×2"),
        Node(id: "lifecycle", title: "LifecycleManager"),
        Node(id: "stateStore", title: "StateStorage"),
        Node(id: "cache", title: "RenderCache"),
        Node(id: "prefs", title: "PreferenceStorage"),
        Node(id: "keyDispatch", title: "KeyEventDispatcher"),
    ],
    edges: [
        Edge("render", "terminal", label: "writes output", dashed: true),
        Edge("render", "statusBar", label: "inject env", dashed: true),
        Edge("render", "appHeader", dashed: true),
        Edge("render", "focus", dashed: true),
        Edge("render", "themes", dashed: true),
        Edge("render", "lifecycle", label: "begin/end pass", dashed: true),
        Edge("render", "stateStore", label: "begin/end pass", dashed: true),
        Edge("render", "cache", label: "begin/end pass", dashed: true),
        Edge("render", "prefs", label: "begin pass", dashed: true),
        Edge("render", "keyDispatch", label: "clear handlers", dashed: true),
        Edge("input", "focus", label: "L0 + L3", dashed: true),
        Edge("input", "statusBar", label: "L1", dashed: true),
        Edge("input", "keyDispatch", label: "L2", dashed: true),
        Edge("input", "themes", label: "L4", dashed: true),
    ],
    rankdir: "LR"
)
