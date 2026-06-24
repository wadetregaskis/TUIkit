//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ImageFilePage.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkit

/// Image demo page for loading an image from the local filesystem.
///
/// Displays a bundled demo image and provides status bar items to
/// cycle through character set, color mode, and dithering settings.
struct ImageFilePage: View {
    @State var charSetIndex: Int = 0
    @State var colorModeIndex: Int = 0
    @State var ditheringOn: Bool = false

    var body: some View {
        let charSet = ImageDemoHelpers.charSets[charSetIndex]
        let colorMode = ImageDemoHelpers.colorModes[colorModeIndex]
        let dithering: DitheringMode = ditheringOn ? .floydSteinberg : .none

        VStack(alignment: .leading) {
            HStack {
                Spacer()
                if let path = Bundle.module.path(forResource: "demo-image", ofType: "jpg", inDirectory: "Resources") {
                    Image(.file(path))
                        .imagePlaceholder("Loading image...")
                        .imagePlaceholderSpinner(true)
                } else {
                    Text("Resource not found: demo-image.jpg")
                        .foregroundStyle(.error)
                }
                Spacer()
            }
            .padding(.bottom, 1)
            Spacer()
        }
        .imageCharacterSet(charSet)
        .imageColorMode(colorMode)
        .imageDithering(dithering)
        .statusBarItems(statusBarItems)
        // Page-scrollable again: Image now sizes its height from the width and its
        // aspect ratio (rather than claiming the whole offered height), so it no
        // longer balloons inside a ScrollView's tall measure canvas.
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader("Image (File)")
        }
    }

    private var statusBarItems: [any StatusBarItemProtocol] {
        let charSetCount = ImageDemoHelpers.charSets.count
        let colorModeCount = ImageDemoHelpers.colorModes.count
        return [
            StatusBarItem(shortcut: Shortcut.escape, label: "back"),
            // c|C — lowercase cycles forward, uppercase cycles
            // backward. The "C" item is hidden so the bar shows
            // a single entry with the dual-key indicator.
            StatusBarItem(
                shortcut: "c|C",
                label: ImageDemoHelpers.charSetLabel(charSetIndex),
                key: .character("c")
            ) {
                charSetIndex = (charSetIndex + 1) % charSetCount
            },
            StatusBarItem(
                shortcut: "C",
                label: "",
                key: .character("C"),
                displayInStatusBar: false
            ) {
                charSetIndex = (charSetIndex - 1 + charSetCount) % charSetCount
            },
            StatusBarItem(
                shortcut: "m|M",
                label: ImageDemoHelpers.colorModeLabel(colorModeIndex),
                key: .character("m")
            ) {
                colorModeIndex = (colorModeIndex + 1) % colorModeCount
            },
            StatusBarItem(
                shortcut: "M",
                label: "",
                key: .character("M"),
                displayInStatusBar: false
            ) {
                colorModeIndex =
                    (colorModeIndex - 1 + colorModeCount) % colorModeCount
            },
            // d is a binary toggle — a Shift variant would be a
            // no-op, so no "D" partner.
            StatusBarItem(shortcut: "d", label: ditheringOn ? "dither:on" : "dither:off") {
                ditheringOn.toggle()
            },
            StatusBarItem(shortcut: Shortcut.arrowsUpDown, label: "scroll"),
        ]
    }
}
