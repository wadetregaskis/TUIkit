//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StressApp.swift
//
//  Created by LAYERED.work
//  License: MIT

import Observation
import TUIkit

// MARK: - Shared clock

/// A frame counter (and the autopilot flag) shared with scenarios through the
/// environment. The autopilot (or real input) bumps `tick`; scenarios that
/// animate/churn observe it. Using `@Observable` means a bump invalidates only
/// the views that actually read it.
///
/// `@unchecked Sendable`: the autopilot `Task` captures this reference, but
/// every mutation hops to the main actor (`MainActor.run`) — the same actor the
/// render reads it on — so the access is in fact serialised.
@Observable
final class StressClock: @unchecked Sendable {
    var tick: Int = 0
    var autopilot: Bool = false
}

// MARK: - App

/// The interactive stress app. Reads its configuration from the environment +
/// CLI on construction (so `App.main()` needs no parameters), and hosts a menu
/// that opens one scenario at a time.
struct StressApp: App {
    let config: StressConfig

    init() {
        config = StressConfig.fromEnvironmentAndArgs(Array(CommandLine.arguments.dropFirst()))
    }

    var body: some Scene {
        WindowGroup {
            RootView(config: config)
        }
    }
}

// MARK: - Root view (menu + router)

private struct RootView: View {
    let config: StressConfig

    @State private var clock = StressClock()
    @State private var scale: Int
    @State private var menuIndex = 0
    /// The currently-open scenario id, or `nil` for the menu.
    @State private var activeID: String?
    /// The built scenario view, held across frames so heavy data is synthesised
    /// once (on open / scale change), not rebuilt every frame.
    @State private var activeView: AnyView?

    init(config: StressConfig) {
        self.config = config
        _scale = State(wrappedValue: config.scale)
    }

    /// The size-and-seed config reflecting the live `scale`.
    private var liveConfig: StressConfig {
        var c = config
        c.scale = scale
        return c
    }

    var body: some View {
        content
            .environment(clock)
            .onAppear {
                clock.autopilot = config.autopilot
                if activeView == nil, let id = config.initialScenario { open(id) }
            }
            .task { [clock] in
                // Keep the demand-driven loop busy while autopilot is on. The
                // flag and counter both live on the (Sendable) clock; mutate on
                // the main actor so it's serialised with rendering.
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(33))
                    await MainActor.run { if clock.autopilot { clock.tick &+= 1 } }
                }
            }
            .onKeyPress { handleKey($0) }
    }

    @ViewBuilder
    private var content: some View {
        if let view = activeView, let id = activeID {
            VStack(alignment: .leading, spacing: 0) {
                view
                Divider()
                Text(footer(for: id)).foregroundStyle(.secondary)
            }
        } else {
            menu
        }
    }

    /// Autopilot status string. Reading `clock.tick` here while autopilot is on
    /// is **load-bearing**: it is what makes the tick *observed*, so each bump
    /// (~30/s) actually invalidates and re-renders the tree. Without a live
    /// reader on screen, autopilot would increment an unobserved counter and
    /// generate no re-render load at all — i.e. do nothing visible. The live
    /// frame number is also the user's signal that autopilot is running.
    private var autopilotStatus: String {
        clock.autopilot ? "on · frame \(clock.tick)" : "off"
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TUIkit — Stress Test").bold()
            Text("scale \(scale) · seed \(config.seed) · autopilot \(autopilotStatus)")
                .foregroundStyle(.secondary)
            Divider()
            ForEach(0..<Scenarios.all.count, id: \.self) { index in
                let scenario = Scenarios.all[index]
                HStack {
                    Text(index == menuIndex ? "▶ \(scenario.title)" : "  \(scenario.title)")
                        .foregroundStyle(index == menuIndex ? .accent : .primary)
                    Spacer()
                    Text(scenario.stresses).foregroundStyle(.secondary)
                }
            }
            Divider()
            Text("↑/↓ select · enter open · +/− scale · a autopilot · esc quit")
                .foregroundStyle(.secondary)
        }
        .padding(1)
    }

    private func footer(for id: String) -> String {
        let title = Scenarios.byID(id)?.title ?? id
        return "\(title) · scale \(scale) · autopilot \(autopilotStatus)"
            + "   [esc back · +/− scale · a autopilot]"
    }

    // MARK: Navigation

    private func open(_ id: String) {
        guard let scenario = Scenarios.byID(id) else { return }
        activeID = id
        activeView = scenario.make(liveConfig)
    }

    private func rebuildActive() {
        if let id = activeID { open(id) }
    }

    private func close() {
        activeID = nil
        activeView = nil
    }

    // MARK: Input

    private func handleKey(_ event: KeyEvent) -> Bool {
        switch event.key {
        case .character("+"), .character("="):
            scale += 1
            rebuildActive()
            return true
        case .character("-"), .character("_"):
            scale = max(1, scale - 1)
            rebuildActive()
            return true
        case .character("a"):
            clock.autopilot.toggle()
            return true
        default:
            break
        }

        if activeID != nil {
            // In a scenario: esc returns to the menu; everything else (arrows,
            // page keys) falls through to the focused List/ScrollView.
            if event.key == .escape {
                close()
                return true
            }
            return false
        }

        // On the menu.
        switch event.key {
        case .up:
            menuIndex = max(0, menuIndex - 1)
            return true
        case .down:
            menuIndex = min(Scenarios.all.count - 1, menuIndex + 1)
            return true
        case .enter:
            open(Scenarios.all[menuIndex].id)
            return true
        default:
            // esc on the menu falls through to the default quit handler.
            return false
        }
    }
}
