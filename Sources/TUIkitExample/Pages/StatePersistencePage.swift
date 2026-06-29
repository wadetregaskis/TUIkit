//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StatePersistencePage.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkit

/// State-persistence demo page.
///
/// Demonstrates `@AppStorage` — values that persist to disk and survive quitting
/// and relaunching the app. The page shows the live values, the on-disk settings
/// file they are written to, and a prompt to quit (`q`) and relaunch to see the
/// numbers carry over.
struct StatePersistencePage: View {
    // @AppStorage persists to <config>/settings.json, so these values survive
    // quitting and relaunching the app.
    @AppStorage("state.launchTaps") private var launchTaps: Int = 0
    @AppStorage("state.remembered") private var remembered: Bool = false
    @AppStorage("state.note") private var note: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection(L("page.state.persistenceSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.state.description"))
                        .foregroundStyle(.palette.foregroundSecondary)

                    Button(L("page.state.tapToIncrement")) {
                        launchTaps += 1
                    }
                    Toggle(L("page.state.rememberMe"), isOn: $remembered)

                    HStack(spacing: 2) {
                        ValueDisplayRow(L("page.state.storedTaps"), "\(launchTaps)")
                        ValueDisplayRow(
                            L("page.state.remembered"),
                            remembered ? L("page.state.yes") : L("page.state.no"))
                    }
                }
            }

            DemoSection(L("page.state.noteSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.state.noteDescription"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    TextField(L("page.state.notePlaceholder"), text: $note)
                        .frame(width: 32)
                }
            }

            DemoSection(L("page.state.whereSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    ValueDisplayRow(L("page.state.savedTo"), Self.settingsPath)
                    Text(L("page.state.relaunchHint"))
                        .foregroundStyle(.palette.accent)
                }
            }

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader(L("page.state.title"))
        }
    }

    /// The on-disk settings file `@AppStorage` writes to, resolved the same way
    /// the framework's `JSONFileStorage` does: `$XDG_CONFIG_HOME/<app>/settings.json`
    /// or `~/.config/<app>/settings.json`.
    private static var settingsPath: String {
        let appName = ProcessInfo.processInfo.processName
        let configDir: URL
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            configDir = URL(fileURLWithPath: xdg).appendingPathComponent(appName)
        } else {
            configDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config")
                .appendingPathComponent(appName)
        }
        let full = configDir.appendingPathComponent("settings.json").path
        // Abbreviate the home prefix to keep the line short.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return full.hasPrefix(home) ? "~" + full.dropFirst(home.count) : full
    }
}
