//  🖥️ TUIKit — Terminal UI Kit for Swift
//  BodyMutationDiagnostic.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkitCore

// MARK: - Body-mutation diagnostic

/// Reports `@State` written *while the view tree is being walked*.
///
/// Writing state during a walk is not illegal and is not swallowed — the write
/// happens, the invalidation is honoured, and the frame stays consistent. It is
/// simply almost always a mistake, and an expensive one: the write asks for
/// another frame, so a view that does it unconditionally asks for another frame
/// **every** frame, and the demand-driven run loop obliges. That is a screen
/// that never idles, and — because the next frame is usually identical — one
/// that burns CPU while writing nothing at all.
///
/// That exact bug cost 2% CPU on a screen showing one `Image` (`75a732fa`), and
/// finding it took a purpose-built probe plus a guess about where to look. This
/// turns the same question into a report that names the subtree.
///
/// ## Enabling it
///
/// Off by default, and free when off — the only cost is one optional check per
/// invalidation. Set `TUIKIT_DIAGNOSE_BODY_MUTATION=1`:
///
/// ```
/// TUIKIT_DIAGNOSE_BODY_MUTATION=1 swift run Example 2>mutations.log
/// ```
///
/// Reports go to **stderr**, matching `TUIKIT_DEBUG_RENDER` — stdout is the
/// terminal UI, so anything written there corrupts the frame. Redirect to
/// capture; a TUI run without a redirect will scribble on its own screen, which
/// is the honest trade for having no other channel.
///
/// ``reports`` collects the same records in memory, which is how tests read
/// them and how an app could surface them itself.
///
/// ## Why the traversing *thread*, not "the main thread"
///
/// A write only counts if it happens on the thread doing the walking, while it
/// is walking. Two rejected alternatives, both wrong in ways worth recording:
///
/// - `Thread.isMainThread` is not reliable under the Swift concurrency runtime
///   on Linux (upstream hit this and had to fix it: phranck `8d63dadf`).
/// - A `@TaskLocal` window looks tidier and is subtly wrong: a `.task` closure
///   started *during* the walk inherits the scope, so a perfectly legitimate
///   state write from that task — running much later — would be reported as a
///   body mutation.
///
/// Comparing thread identity has neither problem. A write from any other thread
/// does not match, and once the window closes nothing matches at all.
public final class BodyMutationDiagnostic: @unchecked Sendable {
    /// One reported mutation.
    public struct Report: Sendable, Equatable {
        /// The subtree whose state was written, or `nil` for a whole-tree
        /// invalidation (an `@Observable` change).
        public let identity: String
        /// How many frames into the run this was seen — enough to tell "once at
        /// startup" from "every single frame", which is the distinction that
        /// matters.
        public let frame: Int
    }

    /// Whether the environment asked for this. Read once: the answer cannot
    /// change within a run, and this is consulted on the invalidation path.
    public static let isEnabled: Bool =
        ProcessInfo.processInfo.environment["TUIKIT_DIAGNOSE_BODY_MUTATION"] == "1"

    private let lock = NSLock()
    /// The thread currently walking the tree, or `nil` outside a walk.
    private var traversingThread: ObjectIdentifier?
    /// Identities already reported *this frame*, so a view that mutates does not
    /// produce one line per invalidation.
    private var reportedThisFrame: Set<String> = []
    private var frameNumber = 0
    private var collected: [Report] = []

    /// Every mutation reported so far, oldest first.
    public var reports: [Report] {
        lock.withLock { collected }
    }

    public init() {}

    /// Opens the window: writes from this thread now count as body mutations.
    ///
    /// Re-entrant walks are the normal case — a frame may walk the tree more
    /// than once — so this is idempotent rather than balanced. ``endTraversal()``
    /// closes it whoever opened it.
    public func beginTraversal() {
        let thread = ObjectIdentifier(Thread.current)
        lock.withLock { traversingThread = thread }
    }

    /// Closes the window. Nothing is reported until the next ``beginTraversal()``.
    public func endTraversal() {
        lock.withLock { traversingThread = nil }
    }

    /// Starts a new frame, so a per-frame mutation is reported once per frame
    /// rather than once ever — the repetition is the signal.
    public func beginFrame() {
        lock.withLock {
            frameNumber += 1
            reportedThisFrame.removeAll(keepingCapacity: true)
        }
    }

    /// Records an invalidation if it came from the traversing thread mid-walk.
    ///
    /// - Parameter identity: The subtree being invalidated, or `nil` for a
    ///   whole-tree clear.
    func note(_ identity: ViewIdentity?) {
        // A root identity renders as the empty string, and a report nobody can
        // locate is not a report.
        let key = identity.map { $0.path.isEmpty ? "<root>" : $0.path } ?? "<whole tree>"
        let report: Report? = lock.withLock {
            guard traversingThread == ObjectIdentifier(Thread.current) else { return nil }
            guard reportedThisFrame.insert(key).inserted else { return nil }
            let report = Report(identity: key, frame: frameNumber)
            collected.append(report)
            return report
        }
        guard let report else { return }
        FileHandle.standardError.write(
            Data(
                """
                [TUIkit] state written during a tree walk, frame \(report.frame): \
                \(report.identity)
                  A write during the walk asks for another frame. If this repeats \
                every frame the run loop can never idle.

                """.utf8))
    }
}
