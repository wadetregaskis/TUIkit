//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnchoredEndGrowingRowsTests.swift
//
//  End on a lazy stack past the anchored-window threshold whose rows grow down
//  the list lands on the last row and stays there. The tail glue re-asserts the
//  bottom offset against a total the render refines, and a move of more than
//  four viewports was taken for a scrollbar jump and mapped to a row through
//  the running pitch average — which the tail's own tall rows had just raised,
//  so the ordinal came out far above them: End showed the last row for a frame
//  and then settled mid-list, and stayed there.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

private struct GrowingGroupsApp: App {
    var body: some Scene { WindowGroup { GrowingGroupsPage() } }
}

/// 260 groups — past the 256-row threshold — each an eager stack of rows that
/// grows down the list, from 20 rows to 149.
private struct GrowingGroupsPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("header")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<260, id: \.self) { group in
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(0..<(20 + group / 2), id: \.self) { row in
                                Text("g\(group) r\(row)")
                            }
                        }
                    }
                }
            }
        }
    }
}

@MainActor
@Suite("End on an anchored stack whose rows grow down the list")
struct AnchoredEndGrowingRowsTests {
    @Test("End lands on the last row and stays on it")
    func endStaysOnTheLastRow() {
        let app = HeadlessApp(GrowingGroupsApp(), width: 30, height: 12)
        app.frame(atNanos: 0)
        _ = app.send(KeyEvent(key: .end))
        var screens: [[String]] = []
        for frame in 1...10 {
            app.frame(atNanos: Int64(frame) * 16_666_667)
            screens.append(app.screen.map(\.stripped))
        }
        let last = "g259 r148"
        for (index, screen) in screens.enumerated().dropFirst() {
            #expect(
                screen.contains { $0.contains(last) },
                "frame \(index + 1) after End does not show \(last): \(screen)")
        }
    }
}
