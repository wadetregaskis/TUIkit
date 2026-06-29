//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LifecyclePage.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// View-lifecycle demo page.
///
/// Demonstrates the lifecycle hooks with live, on-screen counters that tick up
/// as each hook fires: `.onAppear` (runs when the page is shown — revisit it from
/// the menu to watch it climb), `.task` (async work that completes ~¼s after the
/// first frame), and `.onChange` (fires when a tracked value changes — bump it
/// and watch the count follow). The "last event" line names whichever hook fired
/// most recently.
struct LifecyclePage: View {
    @State private var appearCount: Int = 0
    @State private var taskCount: Int = 0
    @State private var changeCount: Int = 0
    @State private var tick: Int = 0
    @State private var lastEvent: String = "—"

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection(L("page.lifecycle.countersSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.lifecycle.description"))
                        .foregroundStyle(.palette.foregroundSecondary)

                    VStack(alignment: .leading, spacing: 0) {
                        ValueDisplayRow(".onAppear", "\(appearCount)")
                        ValueDisplayRow(".task", "\(taskCount)")
                        ValueDisplayRow(".onChange", "\(changeCount)")
                    }
                    .border(color: .brightBlack)

                    ValueDisplayRow(L("page.lifecycle.lastEvent"), lastEvent)
                }
                // The hooks live on the section whose lifecycle they describe.
                // onAppear runs on each appearance (revisit the page to see it
                // climb); task runs once the first frame is on screen.
                .onAppear {
                    appearCount += 1
                    lastEvent = L("page.lifecycle.evAppear")
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
                        Button(L("page.lifecycle.bump")) { tick += 1 }
                        ValueDisplayRow(L("page.lifecycle.tracked"), "\(tick)")
                    }
                }
                .onChange(of: tick) {
                    changeCount += 1
                    lastEvent = "\(L("page.lifecycle.evChange")) \(tick)"
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
        taskCount += 1
        lastEvent = L("page.lifecycle.evTask")
    }
}
