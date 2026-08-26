//  🖥️ TUIkit — Terminal UI Kit for Swift
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

/// A surface feature, and below it a sample taken there. Two more types purely
/// to make the stack DEEP: at five levels the navigation bar's breadcrumb trail
/// has to elide its middle on a normal terminal, and below a certain width fall
/// back to the single Back button. A three-level demo never reaches either.
private struct Feature: Hashable {
    let name: String
    let moon: String
}

private struct Sample: Hashable {
    let label: String
    let feature: String
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

    /// Root state that must survive a push — the demo's whole point. If this
    /// empties when you come back, something is wrong. (A second copy of the
    /// same proof used to live on the planet list as a selection binding; it
    /// bought nothing this does not, and cost the list a redundant focus stop.)
    @State private var note = ""

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
            Text("page.navigation.intro")
                .foregroundStyle(.palette.foregroundSecondary)

            NavigationStack(path: $path) {
                rootScreen
                    .navigationDestination(for: Planet.self) { planetScreen($0) }
                    .navigationDestination(for: Moon.self) { moonScreen($0) }
                    .navigationDestination(for: Feature.self) { featureScreen($0) }
                    .navigationDestination(for: Sample.self) { sampleScreen($0) }
            }
            .border(.palette.border)

            Text("\(L("page.navigation.depth")) \(path.count)")
                .foregroundStyle(.palette.foregroundSecondary)
        }
    }

    // MARK: - Screens

    /// The bottom of the stack. Its state is the point of the demo.
    private var rootScreen: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("page.navigation.root.instruction")

            // A plain column, not a `List`. Every row here is a
            // `NavigationLink`, which is already its own focus stop, so a list
            // around them added a SECOND cursor over the same five targets:
            // Tab walked the links, then landed on the list to walk them again
            // with the arrows. A list earns its own cursor when it is the only
            // way to reach its rows — these rows reach themselves.
            VStack(alignment: .leading, spacing: 0) {
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
                }
            }

            LabeledContent("page.navigation.note") {
                TextField("page.navigation.notePlaceholder", text: $note)
            }

            // A view destination rather than a value one: there is no data to
            // route on, just one specific screen.
            NavigationLink("page.navigation.about") { aboutScreen }
        }
        .navigationTitle("page.navigation.title.planets")
    }

    private func planetScreen(_ planet: Planet) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(planet.name).bold()
            Text("\(L("page.navigation.moons")): \(planet.moons)")

            if moons(of: planet).isEmpty {
                Text("page.navigation.noMoons")
                    .foregroundStyle(.palette.foregroundSecondary)
            } else {
                Text("page.navigation.pushAgain")
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
            Text("page.navigation.moonBody")
                .foregroundStyle(.palette.foregroundSecondary)
            // Two more levels below here, so the trail gets long enough to
            // elide. Feature and sample names are the demo's CONTENT, like the
            // planet names above them, so they are not translated.
            ForEach(Self.features(of: moon), id: \.name) { feature in
                NavigationLink(feature.name, value: feature)
            }
            Spacer()
            rootButton
        }
        .navigationTitle(moon.name)
    }

    private func featureScreen(_ feature: Feature) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(feature.name) · \(feature.moon)").bold()
            ForEach(Self.samples(at: feature), id: \.label) { sample in
                NavigationLink(sample.label, value: sample)
            }
            Spacer()
            rootButton
        }
        .navigationTitle(feature.name)
    }

    private func sampleScreen(_ sample: Sample) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(sample.label) · \(sample.feature)").bold()
            Spacer()
            rootButton
        }
        .navigationTitle(sample.label)
    }

    /// Named surface features, deliberately long enough that the trail has to
    /// elide at ordinary terminal widths.
    /// Two real, named surface features per moon — IAU names, not invented
    /// ones. Every moon used to show Luna's, which made four screens of the
    /// demo say the same thing and quietly taught the reader that the trail
    /// they were walking did not depend on where they had walked.
    private static func features(of moon: Moon) -> [Feature] {
        let names: [String] =
            switch moon.name {
            case "Luna": ["Mare Tranquillitatis", "Copernicus Crater"]
            // Phobos is dominated by one crater a third of its width, and by
            // the grooves radiating from it.
            case "Phobos": ["Stickney Crater", "Kepler Dorsum"]
            // Deimos has exactly two named craters, both named for writers who
            // wrote about Martian moons before anyone had seen them.
            case "Deimos": ["Swift Crater", "Voltaire Crater"]
            case "Io": ["Loki Patera", "Pele"]
            case "Europa": ["Conamara Chaos", "Pwyll Crater"]
            case "Ganymede": ["Galileo Regio", "Uruk Sulcus"]
            case "Callisto": ["Valhalla Basin", "Asgard Basin"]
            default: []
            }
        return names.map { Feature(name: $0, moon: moon.name) }
    }

    private static func samples(at feature: Feature) -> [Sample] {
        ["Core 1", "Core 2"].map { Sample(label: $0, feature: feature.name) }
    }

    private var aboutScreen: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("page.navigation.aboutBody")
            Spacer()
            rootButton
        }
        .navigationTitle("page.navigation.about")
    }

    /// Jump straight back to the root from any depth — what a bound path buys
    /// you that the links alone do not.
    private var rootButton: some View {
        Button("page.navigation.backToRoot") { path.removeLast(path.count) }
            .disabled(path.isEmpty)
    }
}
