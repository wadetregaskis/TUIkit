//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RenderHarness.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkit

//  Mode A profiling harness (see Tools/Profiling/README.md).
//
//  Builds a representative view tree and calls `renderToBuffer(_:context:)`
//  on it in a counted loop, then exits. Unlike the end-to-end driver
//  (`record.sh` → `drive.py`), this needs no PTY and no Instruments
//  *attach* — profile it by having Instruments *launch* it:
//
//      swift build -c release --product RenderHarness -Xswiftc -g
//      BIN="$(swift build -c release --product RenderHarness --show-bin-path)/RenderHarness"
//      xcrun xctrace record --template 'Time Profiler' \
//          --output rh.trace --launch -- "$BIN" --tree alignment --iterations 200000
//      python3 Tools/Profiling/analyze_timeprofile.py rh.trace
//
//  `--launch` works where `--attach` is denied (sandboxes, CI, VMs without
//  debugger entitlements), so this is the only profiling mode available in
//  those environments. The deterministic, input-timing-free loop also makes
//  it the right microscope for before/after comparisons while iterating on a
//  measure- or render-pass change.
//
//  The tree's concrete type is preserved end to end (no `AnyView` erasure) so
//  the profile reflects the real `measureChild` / `Layoutable` dispatch the
//  view would take in an app.

@main
struct RenderHarness {
    @MainActor
    static func main() {
        var tree = "alignment"
        var iterations = 200_000
        var cols = 120
        var rows = 40

        var args = CommandLine.arguments.dropFirst().makeIterator()
        while let arg = args.next() {
            switch arg {
            case "--tree": tree = args.next() ?? tree
            case "--iterations": iterations = args.next().flatMap(Int.init) ?? iterations
            case "--cols": cols = args.next().flatMap(Int.init) ?? cols
            case "--rows": rows = args.next().flatMap(Int.init) ?? rows
            case "--help", "-h":
                print(usage)
                return
            default:
                FileHandle.standardError.write(Data("unknown argument: \(arg)\n".utf8))
                print(usage)
                return
            }
        }

        // Rendering composite views force-unwraps `environment.stateStorage`
        // (it is nil by default), so the harness must supply one. The focus
        // manager and the various dispatchers have non-nil defaults or are
        // skipped when absent, so state storage is all a layout/render profile
        // needs. (The richer `tuiContext:` initializer is internal to TUIkit.)
        var environment = EnvironmentValues()
        environment.stateStorage = StateStorage()
        // EquatableView memoizes through the render cache (its render
        // force-unwraps it); supply one so the `memoRows` tree can run. The
        // harness never clears it between iterations, so it models the
        // steady-state where unchanged subtrees stay cached across frames.
        environment.renderCache = RenderCache()
        // Everything below this line is fidelity, learned from `Stress`'s bench
        // making the same mistakes first. Without it Mode A measures a world the
        // app does not live in:
        //
        // * `volatileReadTracker` is a PRECONDITION of the measure memo
        //   (`ChildInfo`), not a diagnostic — with no tracker the memo is off,
        //   and a harness reporting "no cache activity" is describing itself
        //   rather than the framework.
        // * `preferenceStorage`, because `.preference` force-unwraps it.
        // * Rooting identity at a TYPE, as `RenderLoop` roots an app. Under the
        //   default raw-path root every identity is raw-rooted, and
        //   `ViewIdentity.isAncestor(of:)` then renders and prefix-compares two
        //   full path strings — which made the end-of-pass prune 88-95% of a
        //   frame in the Stress bench and nothing at all in the app.
        environment.preferenceStorage = PreferenceStorage()
        environment.volatileReadTracker = VolatileReadTracker()
        // An app's root environment is not an empty one, and the gap is not
        // cosmetic. `RenderLoop.buildEnvironment()` STORES the palette and the
        // appearance, and every frame stamps the terminal size and the
        // animation clock. Left unset here, every read of those four fell
        // through the dictionary to `defaultValue` — 208 of the 687
        // environment reads this tree performs per frame missed, where the same
        // reads in an app all hit. That is the difference between measuring a
        // dictionary miss and measuring an `Any` unbox plus a dynamic cast, so
        // an optimisation aimed at the miss path would have been aimed at the
        // harness. Seeded with the values the defaults already produce, so the
        // rendered output is unchanged and only the lookup pattern becomes the
        // app's.
        environment.palette = SystemPalette(.green)
        environment.appearance = .default
        environment.terminalWidth = cols
        environment.terminalHeight = rows
        environment.animationFrame = AnimationFrame()
        let context = RenderContext(
            availableWidth: cols, availableHeight: rows, environment: environment,
            identity: ViewIdentity(rootType: HarnessRoot.self))

        // Dispatch on the tree name into a generic loop so each tree keeps its
        // own concrete `View` type — type-erasing here would change the very
        // dispatch we want to measure.
        let checksum: Int
        switch tree {
        case "alignment": checksum = renderLoop(Trees.alignmentRow(), context, iterations)
        case "nested": checksum = renderLoop(Trees.nestedRow(), context, iterations)
        case "frames": checksum = renderLoop(Trees.frames(), context, iterations)
        case "paneled": checksum = renderLoop(Trees.paneled(), context, iterations)
        case "memoRows": checksum = renderLoop(Trees.memoRows(), context, iterations)
        case "stackRows": checksum = renderLoop(Trees.stackRows(), context, iterations)
        case "list": checksum = renderLoop(Trees.list(), context, iterations)
        case "form": checksum = renderLoop(Trees.mixedForm(), context, iterations)
        case "menu": checksum = renderLoop(Trees.menu(), context, iterations)
        default:
            FileHandle.standardError.write(Data("unknown tree: \(tree)\n".utf8))
            print(usage)
            return
        }

        // Print the accumulated checksum so the optimiser cannot elide the
        // render loop as dead code.
        print("tree=\(tree) iterations=\(iterations) size=\(cols)x\(rows) checksum=\(checksum)")
        if let stats = environment.renderCache?.stats {
            print("cache: hits=\(stats.hits) misses=\(stats.misses) stores=\(stats.stores) entries=\(environment.renderCache?.count ?? 0)")
        }
    }

    /// Renders `view` `iterations` times, folding each buffer's dimensions into
    /// a checksum that escapes via the return value (defeats dead-code removal).
    @MainActor
    private static func renderLoop<V: View>(_ view: V, _ context: RenderContext, _ iterations: Int) -> Int {
        var checksum = 0
        for _ in 0..<iterations {
            // The per-pass lifecycle IS part of a frame: `RenderLoop` opens
            // every pass with these and closes it by pruning whatever the pass
            // did not mark alive. Without them this loop rendered into a cache
            // that was never pruned and a per-pass measure memo that was never
            // emptied, so an off-screen size was a hit here and a miss in the
            // app — the same correction `Stress`'s bench needed.
            context.environment.stateStorage?.beginRenderPass()
            context.environment.renderCache?.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            context.environment.stateStorage?.endRenderPass()
            context.environment.renderCache?.removeInactive()
            checksum = checksum &+ buffer.width &+ buffer.height &+ buffer.lines.count
        }
        return checksum
    }

    /// The type the harness's identity tree is rooted at — the stand-in for the
    /// `App` type `RenderLoop` roots a real tree at.
    private enum HarnessRoot {}

    static let usage = """
        RenderHarness — Mode A profiling harness (xctrace --launch).
        Usage: RenderHarness [--tree alignment|nested|frames|paneled|memoRows|stackRows|list|form|menu] [--iterations N] [--cols C] [--rows R]
        """
}
