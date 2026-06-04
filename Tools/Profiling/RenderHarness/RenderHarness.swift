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
        let context = RenderContext(
            availableWidth: cols, availableHeight: rows, environment: environment)

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
            let buffer = renderToBuffer(view, context: context)
            checksum = checksum &+ buffer.width &+ buffer.height &+ buffer.lines.count
        }
        return checksum
    }

    static let usage = """
        RenderHarness — Mode A profiling harness (xctrace --launch).
        Usage: RenderHarness [--tree alignment|nested|frames|paneled|memoRows|stackRows|list|form] [--iterations N] [--cols C] [--rows R]
        """
}
