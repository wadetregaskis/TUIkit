//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SettingsSession.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import TUIkit

// MARK: - The settings

/// An app's settings: switches, a choice, a number, units that every
/// measurement is shown in, an advanced group that opens and closes, and
/// accounts that sync in and out.
@Observable
@MainActor
final class SettingsModel {
    struct Account: Identifiable, Equatable {
        let id: Int
        let name: String
        var enabled: Bool
    }

    var notifications = true
    var sounds = false
    var theme = 0
    var fontSize = 13
    var metric = true
    var advanced = false
    var telemetry = false
    var proxy = ""
    var accounts: [Account]
    private(set) var nextAccount: Int

    init(accounts: [Account]) {
        self.accounts = accounts
        nextAccount = accounts.count
    }

    func makeAccountID() -> Int {
        defer { nextAccount += 1 }
        return nextAccount
    }
}

// MARK: - The page

/// A form of sections: general switches and choices, measurements in the
/// chosen units, an advanced group, and one switch per account.
struct SettingsPage: View {
    let settings: SettingsModel

    /// Lengths in millimetres, shown in the chosen units.
    private static let measurements: [(String, Int)] = [
        ("Margin", 25), ("Gutter", 8), ("Page width", 210), ("Page height", 297), ("Indent", 12),
    ]

    var body: some View {
        Form {
            Section("General") {
                Toggle("Notifications", isOn: bind(\.notifications))
                Toggle("Sounds", isOn: bind(\.sounds))
                Picker("Theme", selection: bind(\.theme)) {
                    ForEach(0..<4, id: \.self) { index in
                        Text(verbatim: ["System", "Light", "Dark", "Sepia"][index]).tag(index)
                    }
                }
                Stepper("Font size: \(settings.fontSize)", value: bind(\.fontSize), in: 8...32)
            }
            Section("Measurements") {
                Toggle("Metric units", isOn: bind(\.metric))
                ForEach(Self.measurements, id: \.0) { name, millimetres in
                    LabeledContent(
                        name,
                        value: settings.metric
                            ? "\(millimetres) mm" : String(format: "%.2f in", Double(millimetres) / 25.4))
                }
            }
            DisclosureGroup("Advanced", isExpanded: bind(\.advanced)) {
                Toggle("Share usage data", isOn: bind(\.telemetry))
                TextField("Proxy", text: bind(\.proxy))
            }
            Section("Accounts") {
                ForEach(settings.accounts) { account in
                    Toggle(
                        account.name,
                        isOn: Binding(
                            get: { account.enabled },
                            set: { value in
                                if let index = settings.accounts.firstIndex(where: { $0.id == account.id }) {
                                    settings.accounts[index].enabled = value
                                }
                            }))
                }
            }
        }
    }

    private func bind<Value>(_ keyPath: ReferenceWritableKeyPath<SettingsModel, Value>) -> Binding<Value> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
    }
}

// MARK: - The script

/// Someone going through settings with the keyboard: tabbing from control to
/// control, flipping switches, stepping a number, switching units, opening
/// and closing the advanced group — while accounts sync in and out.
@MainActor
final class SettingsSession: StressSession {
    private let settings: SettingsModel
    private var random: SessionRandom

    init(config: StressConfig) {
        let seed = config.seed
        settings = SettingsModel(
            accounts: (0..<config.sized(24)).map { index in
                SettingsModel.Account(id: index, name: Synth.name(mix(seed, index)), enabled: index.isMultiple(of: 3))
            })
        random = SessionRandom(seed: seed ^ 0x5E77)
    }

    var page: SettingsPage { SettingsPage(settings: settings) }

    func step(_ index: Int) -> SessionStep {
        switch random.pick([
            ("tab", 30), ("back", 8), ("space", 16), ("enter", 8), ("arrow", 12), ("units", 5),
            ("advanced", 4), ("sync-in", 5), ("sync-out", 4), ("remote", 8),
        ]) {
        case "tab":
            return SessionStep(action: "tab", keys: Array(repeating: KeyEvent(key: .tab), count: random.within(1...3)))
        case "back":
            return SessionStep(action: "tab", keys: [KeyEvent(key: .tab, shift: true)])
        case "space":
            return SessionStep(action: "activate", keys: [KeyEvent(key: .space)])
        case "enter":
            return SessionStep(action: "activate", keys: [KeyEvent(key: .enter)])
        case "arrow":
            let key: Key = [.left, .right, .up, .down][random.below(4)]
            return SessionStep(action: "adjust", keys: [KeyEvent(key: key)])
        case "units":
            // A preference changed elsewhere: every measurement is re-shown.
            settings.metric.toggle()
            return SessionStep(action: "units")
        case "advanced":
            settings.advanced.toggle()
            return SessionStep(action: "disclose")
        case "sync-in":
            settings.accounts.insert(
                SettingsModel.Account(
                    id: settings.makeAccountID(), name: Synth.name(random.next()), enabled: random.below(2) == 0),
                at: random.below(settings.accounts.count + 1))
            return SessionStep(action: "sync")
        case "sync-out":
            guard !settings.accounts.isEmpty else { return SessionStep(action: "sync") }
            settings.accounts.remove(at: random.below(settings.accounts.count))
            return SessionStep(action: "sync")
        default:
            // A value changed by another device.
            settings.fontSize = random.within(8...32)
            settings.sounds.toggle()
            return SessionStep(action: "remote")
        }
    }

    static let descriptor = SessionDescriptor(
        id: "settings",
        summary: "a settings form worked through with the keyboard while accounts sync in and out",
        exercises:
            "focus traversal through a Form, toggles, a picker, a stepper, a disclosure group opening "
            + "and closing, every row re-shown when the units change, rows inserted and removed",
        make: { config, width, height, cold in
            DrivenSession(SettingsSession(config: config), width: width, height: height, cold: cold)
        })
}
