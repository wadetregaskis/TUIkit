//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ImageURLPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// Image demo page for loading an image from a URL.
///
/// Provides a text field for entering an image URL. After pressing
/// Enter the image is downloaded and rendered. Status bar items allow
/// cycling through character set, color mode, and dithering settings.
struct ImageURLPage: View {
    @State var imageURL: String = ""
    @State var activeURL: String = ""

    @State var charSetIndex: Int = 0
    @State var colorModeIndex: Int = 0
    @State var ditheringOn: Bool = false

    var body: some View {
        let charSet = ImageDemoHelpers.charSets[charSetIndex]
        let colorMode = ImageDemoHelpers.colorModes[colorModeIndex]
        let dithering: DitheringMode = ditheringOn ? .floydSteinberg : .none

        VStack(alignment: .leading) {
            HStack(spacing: 1) {
                Text("URL:")
                    .foregroundStyle(.palette.foregroundSecondary)
                TextField("Enter image URL...", text: $imageURL)
                    .onSubmit {
                        activeURL = imageURL
                    }
                    .textContentType(.url)
            }
            .padding(.bottom, 1)

            if !activeURL.isEmpty {
                HStack {
                    Spacer()
                    Image(.url(activeURL))
                        .imagePlaceholder("Downloading...")
                        .imagePlaceholderSpinner(true)
                        .border(color: .palette.border)
                    Spacer()
                }
            } else {
                HStack {
                    Spacer()
                    Text("Press Enter to load the image")
                        .foregroundStyle(.palette.foregroundTertiary)
                        .italic()
                    Spacer()
                }
                Spacer()
            }
            Spacer()
        }
        .imageCharacterSet(charSet)
        .imageColorMode(colorMode)
        .imageDithering(dithering)
        .statusBarItems(statusBarItems)
        // Page-scrollable again: Image now sizes its height from the width and its
        // aspect ratio, so it no longer balloons inside a ScrollView.
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader("Image (URL)")
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
