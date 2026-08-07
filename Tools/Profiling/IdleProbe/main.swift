//  🖥️ TUIKit — Terminal UI Kit for Swift
//  IdleProbe/main.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkit

// MARK: - Why this exists
//
// `idle_cpu.py` answers "does a static screen cost anything?", but only if the
// screen is genuinely static. Every page of `Example` that shows an `Image` also
// carries focusable controls, and a focused control pulses — so the loop is
// legitimately awake and the measurement says nothing about the image.
//
// This is the smallest app that can be asked the question: ONE view, nothing
// focusable, no spinner, no cursor, no notifications, no timers. Whatever CPU it
// burns is the subject under test and nothing else.
//
// Run each mode for the same window and compare. `text` is the control: it is
// known-static, so a non-zero reading there means the harness or the terminal is
// the source, not the view.
//
//     swift build -c release --product IdleProbe
//     BIN="$(swift build -c release --product IdleProbe --show-bin-path)/IdleProbe"
//     TUIKIT_CONFIG_DIR=$(mktemp -d) IDLE_PROBE_MODE=text  python3 Tools/Profiling/idle_cpu.py "$BIN"
//     TUIKIT_CONFIG_DIR=$(mktemp -d) IDLE_PROBE_MODE=image python3 Tools/Profiling/idle_cpu.py "$BIN"
//
// `Tools/Profiling/idle-image.sh` does exactly that, both modes, one command.
//
// TUIKIT_CONFIG_DIR matters: without it a PTY probe writes to the real
// preferences directory. $HOME does not isolate it on macOS.

// MARK: - Mode

/// What to put on screen. Each is deliberately a single view with no
/// interactivity, so the loop has no legitimate reason to wake.
enum ProbeMode: String {
    /// The control: a plain `Text`. Known static; the baseline every other
    /// reading is compared against.
    case text
    /// The subject: an `Image`. A missing file is fine and is in fact the
    /// cheaper test — the load fails fast and settles into the failure phase,
    /// after which nothing should change. Point `IDLE_PROBE_IMAGE` at a real
    /// file to measure a decoded image instead.
    case image
    /// A spinner: the known-NOT-idle case, so a run can prove the harness
    /// notices activity at all. A reading of ~0 here means the measurement is
    /// broken, not that the app is efficient.
    case spinner

    static var current: ProbeMode {
        ProcessInfo.processInfo.environment["IDLE_PROBE_MODE"]
            .flatMap { ProbeMode(rawValue: $0) } ?? .text
    }
}

private let imagePath =
    ProcessInfo.processInfo.environment["IDLE_PROBE_IMAGE"] ?? "/idle-probe-no-such-file.png"

// MARK: - The app

struct IdleProbeApp: App {
    var body: some Scene {
        WindowGroup {
            ProbeContent()
        }
    }
}

private struct ProbeContent: View {
    var body: some View {
        switch ProbeMode.current {
        case .text:
            Text("idle probe — text")
        case .image:
            Image(.file(imagePath))
                .frame(width: 40, height: 20)
        case .spinner:
            Spinner()
        }
    }
}

await IdleProbeApp.main()
