//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LifecyclePage.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// Session-scoped counters for the lifecycle demo.
///
/// Hoisted into `ContentView` (which lives for the whole session) and handed to
/// `LifecyclePage` as a binding, so the counts survive leaving and re-entering
/// the page. Per-page `@State` would reset to zero on every visit — the page
/// leaves the view tree when you return to the menu, exactly as in SwiftUI — so
/// the counters could never be seen to climb across revisits.
struct LifecycleCounters: Equatable {
    var appear = 0
    var task = 0
    var change = 0
    var tick = 0
    var lastEvent = "—"
}

/// View-lifecycle demo page.
///
/// Demonstrates the lifecycle hooks with live, on-screen counters that tick up
/// as each hook fires: `.onAppear` (runs on every appearance — leave to the menu
/// and revisit to watch it climb), `.task` (async work that completes ~¼s after
/// the first frame, and re-runs on each revisit), and `.onChange` (fires when a
/// tracked value changes — bump it and watch the count follow). The "last event"
/// line names whichever hook fired most recently. The counts live in
/// `ContentView` (see ``LifecycleCounters``) so they persist across revisits.
struct LifecyclePage: View {
    @Binding var counters: LifecycleCounters

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection(L("page.lifecycle.countersSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.lifecycle.description"))
                        .foregroundStyle(.palette.foregroundSecondary)

                    VStack(alignment: .leading, spacing: 0) {
                        ValueDisplayRow(".onAppear", "\(counters.appear)")
                        ValueDisplayRow(".task", "\(counters.task)")
                        ValueDisplayRow(".onChange", "\(counters.change)")
                    }
                    .border(color: .brightBlack)

                    ValueDisplayRow(L("page.lifecycle.lastEvent"), counters.lastEvent)
                }
                // The hooks live on the section whose lifecycle they describe.
                // onAppear runs on each appearance (revisit the page to see it
                // climb); task runs once the first frame is on screen.
                .onAppear {
                    counters.appear += 1
                    counters.lastEvent = L("page.lifecycle.evAppear")
                }
                .task {
                    await runStartupTask()
                }
            }

            DemoSection(L("page.lifecycle.onChangeSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.lifecycle.onChangeDescription"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    HStack(spacing: 2) {
                        Button(L("page.lifecycle.bump")) { counters.tick += 1 }
                        ValueDisplayRow(L("page.lifecycle.tracked"), "\(counters.tick)")
                    }
                }
                .onChange(of: counters.tick) {
                    counters.change += 1
                    counters.lastEvent = "\(L("page.lifecycle.evChange")) \(counters.tick)"
                }
            }

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader(L("page.lifecycle.title"))
        }
    }

    // MARK: - Helpers

    /// The body of the `.task`: a short delay, then tick the task counter —
    /// mirroring an async load that finishes after the first frame.
    private func runStartupTask() async {
        try? await Task.sleep(for: .milliseconds(250))
        counters.task += 1
        counters.lastEvent = L("page.lifecycle.evTask")
    }
}
