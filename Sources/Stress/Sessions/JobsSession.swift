//  🖥️ TUIkit — Terminal UI Kit for Swift
//  JobsSession.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import TUIkit

// MARK: - The queue

/// Jobs in a queue: running ones turn a spinner and count up, then finish or
/// fail.
@Observable
@MainActor
final class JobQueue {
    enum State: Equatable {
        case running(percent: Int)
        case done
        case failed
    }

    /// A job. `Equatable`, so its row is memoized — and a running one holds a
    /// spinner, whose frame moves every few ticks under an unchanged value.
    struct Job: Identifiable, Equatable {
        let id: Int
        var name: String
        /// Into ``JobQueue/styles``: `SpinnerStyle` is not `Equatable`.
        var style: Int
        var state: State
    }

    /// Styles at different speeds, so runs move on different ticks.
    static let styles: [SpinnerStyle] = [.dots, .line, .bouncing, .pie, .curve, .clock]

    var jobs: [Job]
    private(set) var nextID: Int

    init(jobs: [Job]) {
        self.jobs = jobs
        nextID = jobs.count
    }

    func makeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    var runningCount: Int {
        jobs.filter { if case .running = $0.state { true } else { false } }.count
    }
}

// MARK: - The page

/// A header counting the jobs, over a list of them.
struct JobsPage: View {
    let queue: JobQueue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "\(queue.jobs.count) jobs · \(queue.runningCount) running")
            List {
                ForEach(queue.jobs) { job in JobRow(job: job) }
            }
        }
    }
}

/// A job: its spinner or outcome, its name, its progress, and its number —
/// how the check reads the rows off the screen.
private struct JobRow: View {
    let job: JobQueue.Job

    var body: some View {
        HStack(spacing: 1) {
            switch job.state {
            case .running:
                Spinner(style: JobQueue.styles[job.style])
            case .done:
                Text(verbatim: "✓")
            case .failed:
                Text(verbatim: "✗")
            }
            Text(verbatim: job.name)
            Spacer()
            if case .running(let percent) = job.state {
                Text(verbatim: "\(percent)%")
            }
            Text(verbatim: "#\(job.id)")
        }
    }
}

// MARK: - The script

/// Someone watching a queue of jobs: most frames nothing is written and only
/// the spinners turn; now and then a job counts up, finishes, fails, is
/// retried or arrives, and the person walks and pages the list.
///
/// It is the shape a spinner in a memoized row needs to be checked in: the row's
/// value is unchanged for many frames while its spinner's picture moves, so a
/// cache that served the row as it was stored would draw an old frame — which
/// the cache-cleared twin sees at once.
@MainActor
final class JobsSession: StressSession {
    private let queue: JobQueue
    private var random: SessionRandom

    init(config: StressConfig) {
        let seed = config.seed
        queue = JobQueue(
            jobs: (0..<config.sized(60)).map { index in
                let h = mix(seed, index)
                let state: JobQueue.State =
                    switch h % 5 {
                    case 0: .done
                    case 1: .failed
                    default: .running(percent: Int(h % 90))
                    }
                return JobQueue.Job(
                    id: index, name: Synth.slug(h), style: Int((h >> 8) % UInt64(JobQueue.styles.count)),
                    state: state)
            })
        random = SessionRandom(seed: seed ^ 0x70B5)
    }

    var page: JobsPage { JobsPage(queue: queue) }

    var looksBeforeEachStep: Bool { false }

    func look(at screen: [String]) {}

    func step(_ index: Int) -> SessionStep {
        switch random.pick([
            ("quiet", 45), ("progress", 20), ("finish", 7), ("arrive", 7), ("retry", 4), ("walk", 12),
            ("page", 5),
        ]) {
        case "progress":
            let running = queue.jobs.indices.filter {
                if case .running = queue.jobs[$0].state { true } else { false }
            }
            guard !running.isEmpty else { return SessionStep(action: "quiet") }
            let at = running[random.below(running.count)]
            if case .running(let percent) = queue.jobs[at].state {
                queue.jobs[at].state = .running(percent: min(99, percent + random.within(1...9)))
            }
            return SessionStep(action: "progress")
        case "finish":
            let running = queue.jobs.indices.filter {
                if case .running = queue.jobs[$0].state { true } else { false }
            }
            guard !running.isEmpty else { return SessionStep(action: "quiet") }
            queue.jobs[running[random.below(running.count)]].state = random.below(4) == 0 ? .failed : .done
            return SessionStep(action: "finish")
        case "arrive":
            let h = random.next()
            queue.jobs.append(
                JobQueue.Job(
                    id: queue.makeID(), name: Synth.slug(h), style: Int(h % UInt64(JobQueue.styles.count)),
                    state: .running(percent: 0)))
            return SessionStep(action: "arrive")
        case "retry":
            guard let at = queue.jobs.firstIndex(where: { $0.state == .failed }) else {
                return SessionStep(action: "quiet")
            }
            queue.jobs[at].state = .running(percent: 0)
            return SessionStep(action: "retry")
        case "walk":
            let key: Key = random.below(3) == 0 ? .up : .down
            return SessionStep(action: "walk", keys: Array(repeating: KeyEvent(key: key), count: random.within(1...4)))
        case "page":
            return SessionStep(action: "walk", keys: [KeyEvent(key: random.below(2) == 0 ? .pageUp : .pageDown)])
        default:
            return SessionStep(action: "quiet")
        }
    }

    /// The header counts what the queue holds, and every job on the screen
    /// shows its own state: a ✓, a ✗, or its progress beside a spinner. The
    /// spinner's FRAME is the twin's to check — it is the same on both sides
    /// only if no stale one is served.
    func check(_ screen: [String], after index: Int) -> String? {
        let header = "\(queue.jobs.count) jobs · \(queue.runningCount) running"
        guard screen.contains(where: { $0.hasPrefix(header) }) else { return "the header does not say \(header)" }
        let byID = Dictionary(uniqueKeysWithValues: queue.jobs.map { ($0.id, $0) })
        for line in screen {
            guard let range = line.range(of: #"#\d+"#, options: .regularExpression),
                let id = Int(line[range].dropFirst()), let job = byID[id]
            else { continue }
            switch job.state {
            case .done where !line.contains("✓"): return "#\(id) is done but shows no ✓: \(line)"
            case .failed where !line.contains("✗"): return "#\(id) failed but shows no ✗: \(line)"
            case .running(let percent) where !line.contains("\(percent)%"):
                return "#\(id) is at \(percent)% but shows: \(line)"
            default: continue
            }
        }
        return nil
    }

    static let descriptor = SessionDescriptor(
        id: "jobs",
        summary: "a queue of jobs whose spinners turn while their rows stay unchanged",
        exercises:
            "memoized List rows holding spinners at six speeds, their frames moving under an unchanged value "
            + "for many frames; progress writes, jobs finishing, failing, retried and arriving; walking and "
            + "paging the list",
        make: { config, width, height, cold in
            DrivenSession(JobsSession(config: config), width: width, height: height, cold: cold)
        })
}
