//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SnapshotCorpusTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// A representative corpus of layouts, snapshotted to catch unintended rendering
/// changes — especially from the flexibility-contract work, where a change to how
/// `sizeThatFits` / render-fill / distribution behave should surface here for
/// every affected view. See `SnapshotTesting.swift` for the harness; accept
/// intended changes with `TUIKIT_RECORD_SNAPSHOTS=1`.
///
/// The cases lean deliberately on the flexibility-sensitive paths: `Spacer`
/// distribution, `.frame(maxWidth:)`, `ScrollView` size-to-content, `ViewThatFits`
/// candidate selection at different widths, and the container/tab chrome built on
/// top of them.
@MainActor
@Suite("Golden snapshots")
struct SnapshotCorpusTests {

    @Test("layout corpus matches the committed snapshots")
    func corpus() {
        // Text & stacks
        assertSnapshot("text-multiline", width: 20, height: 3, of: Text("Hello\nTUIkit world"))
        assertSnapshot("vstack-leading", width: 14, height: 4, of:
            VStack(alignment: .leading, spacing: 0) { Text("a"); Text("bbbb"); Text("cc") })
        assertSnapshot("vstack-center", width: 14, height: 4, of:
            VStack(alignment: .center, spacing: 0) { Text("a"); Text("bbbb"); Text("cc") })
        assertSnapshot("vstack-trailing", width: 14, height: 4, of:
            VStack(alignment: .trailing, spacing: 0) { Text("a"); Text("bbbb"); Text("cc") })
        assertSnapshot("hstack-spacer", width: 20, height: 1, of:
            HStack { Text("L"); Spacer(); Text("R") })
        assertSnapshot("hstack-valign-bottom", width: 12, height: 3, of:
            HStack(alignment: .bottom, spacing: 1) { Text("a\nb\nc"); Text("x") })
        assertSnapshot("zstack-overlay", width: 12, height: 1, of:
            ZStack { Text("aaaaaa"); Text("Z") })

        // Frames (the flexibility surface)
        assertSnapshot("frame-fixed", width: 16, height: 3, of: Text("hi").frame(width: 10, height: 3))
        assertSnapshot("frame-maxwidth-infinity", width: 16, height: 1, of:
            Text("hi").frame(maxWidth: .infinity))
        assertSnapshot("frame-maxwidth-center", width: 16, height: 1, of:
            Text("hi").frame(maxWidth: .infinity, alignment: .center))

        // Chrome
        assertSnapshot("padding-border", width: 14, height: 5, of: Text("x").padding().border())
        assertSnapshot("divider", width: 12, height: 3, of:
            VStack(spacing: 0) { Text("top"); Divider(); Text("bottom") })

        // ScrollView sizes to its content, not the viewport.
        assertSnapshot("scrollview-size-to-content", width: 24, height: 6, of:
            ScrollView { VStack(alignment: .leading, spacing: 0) { Text("r1"); Text("r2"); Text("r3") } })

        // ViewThatFits picks a different candidate per available width.
        let fits = ViewThatFits {
            HStack(spacing: 1) { Text("Alpha"); Text("Beta"); Text("Gamma") }
            VStack(spacing: 0) { Text("Alpha"); Text("Beta"); Text("Gamma") }
        }
        assertSnapshot("viewthatfits-wide", width: 30, height: 4, of: fits)
        assertSnapshot("viewthatfits-narrow", width: 8, height: 4, of: fits)

        // TabView chrome (wraps + active-tab corners).
        assertSnapshot("tabview-compact-multirow", width: 18, height: 8, of:
            TabView(selection: .constant(1)) {
                ForEach(0..<6) { i in Tab("Tab \(i)", value: i) { Text("c\(i)") } }
            }.tabViewStyle(.compact))
        assertSnapshot("tabview-bordered", width: 30, height: 9, of:
            TabView(selection: .constant(1)) {
                ForEach(0..<6) { i in Tab("Tab \(i)", value: i) { Text("Content \(i)") } }
            }.tabViewStyle(.bordered))

        // Dialog with a centred footer.
        assertSnapshot("dialog-centred-footer", width: 32, height: 8, of:
            Dialog(title: "Title", footerAlignment: .center) {
                Text(String(repeating: "x", count: 20))
            } footer: {
                Button("OK") {}
            })

        // The colour picker — the densest flexibility case (size-to-content panel
        // of ViewThatFits editors + swatch grids, centred content, footer).
        assertSnapshot("colorpicker-rgb", width: 64, height: 30, of:
            ColorPickerPanel("Accent", selection: .constant(.rgb(80, 160, 255)), isPresented: .constant(true)))
    }
}
