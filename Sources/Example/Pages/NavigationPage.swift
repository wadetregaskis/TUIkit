//  🖥️ TUIKit — Terminal UI Kit for Swift
//  NavigationPage.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// One of the things you can navigate to — the value a `NavigationLink` puts on
/// the path, and the one a `.navigationDestination(for:)` turns into a screen.
private struct Planet: Hashable, Identifiable {
    let name: String
    let moons: Int

    var id: String { name }
}

/// A moon, so the demo can push a *second* type onto the same path — which is
/// the difference between `NavigationPath` and a typed array binding.
private struct Moon: Hashable {
    let name: String
    let planet: String
}

/// The navigation demo: a stack you can actually walk into and back out of.
///
/// The interesting part is not that it pushes — it is what is still true when
/// you come back. The root's `@State` (the note you typed, the row you picked)
/// survives the round trip, because the stack keeps rendering it off-screen
/// while a screen is on top.
struct NavigationPage: View {
    /// The path, bound so the page can show its depth and offer a "root" button
    /// from any screen — the reason to hold one rather than let the stack.
    @State private var path = NavigationPath()

    /// Root state that must survive a push. If this empties when you come back,
    /// something is wrong.
    @State private var note = ""

    /// Root selection, for the same reason.
    @State private var selection: String?

    private let planets = [
        Planet(name: "Mercury", moons: 0),
        Planet(name: "Venus", moons: 0),
        Planet(name: "Earth", moons: 1),
        Planet(name: "Mars", moons: 2),
        Planet(name: "Jupiter", moons: 95),
    ]

    private func moons(of planet: Planet) -> [Moon] {
        switch planet.name {
        case "Earth": return [Moon(name: "Luna", planet: planet.name)]
        case "Mars":
            return [
                Moon(name: "Phobos", planet: planet.name),
                Moon(name: "Deimos", planet: planet.name),
            ]
        case "Jupiter":
            return ["Io", "Europa", "Ganymede", "Callisto"].map {
                Moon(name: $0, planet: planet.name)
            }
        default: return []
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(L("page.navigation.intro"))
                .foregroundStyle(.palette.foregroundSecondary)

            NavigationStack(path: $path) {
                rootScreen
                    .navigationDestination(for: Planet.self) { planetScreen($0) }
                    .navigationDestination(for: Moon.self) { moonScreen($0) }
            }
            .border(color: .palette.border)

            Text("\(L("page.navigation.depth")) \(path.count)")
                .foregroundStyle(.palette.foregroundSecondary)
        }
    }

    // MARK: - Screens

    /// The bottom of the stack. Its state is the point of the demo.
    private var rootScreen: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(L("page.navigation.root.instruction"))

            List(selection: $selection) {
                ForEach(planets) { planet in
                    NavigationLink(value: planet) {
                        HStack {
                            Text(planet.name)
                            Spacer()
                            // A glyph and a number: no language in the app
                            // has to pick between "1 moon" and "2 moons".
                            Text("☾ \(planet.moons)")
                                .foregroundStyle(.palette.foregroundSecondary)
                        }
                    }
                    .tag(planet.name)
                }
            }

            LabeledContent(L("page.navigation.note")) {
                TextField(L("page.navigation.notePlaceholder"), text: $note)
            }

            // A view destination rather than a value one: there is no data to
            // route on, just one specific screen.
            NavigationLink(L("page.navigation.about")) { aboutScreen }
        }
        .navigationTitle(L("page.navigation.title.planets"))
    }

    private func planetScreen(_ planet: Planet) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(planet.name).bold()
            Text("\(L("page.navigation.moons")): \(planet.moons)")

            if moons(of: planet).isEmpty {
                Text(L("page.navigation.noMoons"))
                    .foregroundStyle(.palette.foregroundSecondary)
            } else {
                Text(L("page.navigation.pushAgain"))
                    .foregroundStyle(.palette.foregroundSecondary)
                ForEach(moons(of: planet), id: \.name) { moon in
                    NavigationLink(moon.name, value: moon)
                }
            }

            Spacer()
            rootButton
        }
        .navigationTitle(planet.name)
    }

    private func moonScreen(_ moon: Moon) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(moon.name) · \(moon.planet)").bold()
            Text(L("page.navigation.moonBody"))
                .foregroundStyle(.palette.foregroundSecondary)
            Spacer()
            rootButton
        }
        .navigationTitle(moon.name)
    }

    private var aboutScreen: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(L("page.navigation.aboutBody"))
            Spacer()
            rootButton
        }
        .navigationTitle(L("page.navigation.about"))
    }

    /// Jump straight back to the root from any depth — what a bound path buys
    /// you that the links alone do not.
    private var rootButton: some View {
        Button(L("page.navigation.backToRoot")) { path.removeLast(path.count) }
            .disabled(path.isEmpty)
    }
}
