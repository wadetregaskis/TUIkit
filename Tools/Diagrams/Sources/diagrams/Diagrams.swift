import Foundation

/// Every diagram this tool can render. Add a new one here and re-run.
///
/// A diagram's content is documentation: keep it in step with the prose of the
/// matching DocC article and with the code it describes.
let allDiagrams: [Diagram] = [
    lifecycleMainLoop,
    architectureEventLoop,
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
             detail: ["≤128/frame · keys: 5 layers · mouse: hit-test"]),
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
             detail: ["≤128/frame · keys → 5 layers · mouse → hit-test"]),
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
