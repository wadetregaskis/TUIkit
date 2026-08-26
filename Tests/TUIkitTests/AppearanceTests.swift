//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AppearanceTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Appearance Tests

@MainActor
@Suite("Appearance Tests")
struct AppearanceTests {

    // MARK: - Appearance Struct Tests

    @Test("Appearance name is derived from ID")
    func appearanceName() {
        // .capitalized lowercases after first letter, so "doubleLine" becomes "Doubleline"
        #expect(Appearance.line.name == "Line")
        #expect(Appearance.rounded.name == "Rounded")
        #expect(Appearance.doubleLine.name == "Doubleline")
        #expect(Appearance.heavy.name == "Heavy")
    }

    @Test("Default appearance is rounded")
    func defaultAppearance() {
        #expect(Appearance.default.rawId == .rounded)
        #expect(Appearance.default.borderStyle == .rounded)
    }

    @Test("Appearances are equatable")
    func appearanceEquatable() {
        let appearance1 = Appearance.line
        let appearance2 = Appearance(id: .line, borderStyle: .line)
        #expect(appearance1 == appearance2)
    }

    // MARK: - Appearance Registry Tests

    @Test("AppearanceRegistry contains all predefined appearances")
    func registryContainsAll() {
        let all = AppearanceRegistry.all
        #expect(all.count == 6)
        #expect(all.contains { $0.rawId == .line })
        #expect(all.contains { $0.rawId == .rounded })
        #expect(all.contains { $0.rawId == .doubleLine })
        #expect(all.contains { $0.rawId == .heavy })
        #expect(all.contains { $0.rawId == .block })
        #expect(all.contains { $0.rawId == .blank })
    }

    @Test("AppearanceRegistry cycling order is correct")
    func registryCyclingOrder() {
        let all = AppearanceRegistry.all
        // Order: rounded (default) → line → doubleLine → heavy → block → blank,
        // roughly by weight, so cycling walks to the extremes rather than
        // jumping between them.
        #expect(all[0].rawId == .rounded)
        #expect(all[1].rawId == .line)
        #expect(all[2].rawId == .doubleLine)
        #expect(all[3].rawId == .heavy)
        #expect(all[4].rawId == .block)
        #expect(all[5].rawId == .blank)
    }

    @Test("AppearanceRegistry can find appearance by ID")
    func registryFindById() {
        let found = AppearanceRegistry.appearance(withId: .heavy)
        #expect(found != nil)
        #expect(found?.rawId == .heavy)
        #expect(found?.borderStyle == .heavy)
    }

    @Test("AppearanceRegistry returns nil for unknown ID")
    func registryUnknownId() {
        let customId = Appearance.ID(rawValue: "unknown")
        let found = AppearanceRegistry.appearance(withId: customId)
        #expect(found == nil)
    }
}

// MARK: - Appearance Environment Tests

@MainActor
@Suite("Appearance Environment Tests")
struct AppearanceEnvironmentTests {

    @Test("Appearance can be accessed via environment")
    func environmentAccess() {
        let env = EnvironmentValues()
        #expect(env.appearance.rawId == .rounded)  // Default
    }

    @Test("Appearance can be set via environment")
    func environmentSet() {
        var env = EnvironmentValues()
        env.appearance = .heavy
        #expect(env.appearance.rawId == .heavy)
    }

    /// Absent by default: the manager is the running app's, published by
    /// `RenderLoop.buildEnvironment()`. A bare `EnvironmentValues()` has no
    /// app, so it has no manager — it used to hand out a shared one that any
    /// test could mutate for all the others.
    @Test("no appearance manager without an application")
    func managerAbsentByDefault() {
        #expect(EnvironmentValues().appearanceManager == nil)
    }

    @Test("Custom AppearanceManager can be set via environment")
    func managerEnvironmentSet() {
        var env = EnvironmentValues()
        let customManager = ThemeManager(
            items: [Appearance.line, Appearance.heavy] as [Appearance]
        )
        env.appearanceManager = customManager
        #expect(env.appearanceManager?.items.count == 2)
    }
}
