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
    @State var zoom: Double = 1.0

    var body: some View {
        let charSet = ImageDemoHelpers.charSets[charSetIndex]
        let colorMode = ImageDemoHelpers.colorModes[colorModeIndex]
        let dithering: DitheringMode = ditheringOn ? .floydSteinberg : .none

        VStack(alignment: .leading) {
            HStack(spacing: 1) {
                Text(L("page.imageURL.urlLabel"))
                    .foregroundStyle(.palette.foregroundSecondary)
                TextField(L("page.imageURL.urlPlaceholder"), text: $imageURL)
                    .onSubmit {
                        activeURL = imageURL
                    }
                    .textContentType(.url)
            }
            .padding(.bottom, 1)

            if !activeURL.isEmpty {
                // Loaded image fills the rest of the page in a viewport-fitted,
                // zoomable two-axis scroll (+/- to zoom; scrollbars appear on zoom).
                Image(.url(activeURL))
                    .imagePlaceholder(L("page.imageURL.downloading"))
                    .imagePlaceholderSpinner(true)
                    .zoomableImageScroll(zoom: zoom)
                    .border(color: .palette.border)
            } else {
                Spacer()
                HStack {
                    Spacer()
                    Text(L("page.imageURL.pressEnter"))
                        .foregroundStyle(.palette.foregroundTertiary)
                        .italic()
                    Spacer()
                }
                Spacer()
            }
        }
        .imageCharacterSet(charSet)
        .imageColorMode(colorMode)
        .imageDithering(dithering)
        .statusBarItems(statusBarItems)
        .appHeader {
            DemoAppHeader(L("page.imageURL.title"))
        }
    }

    private var statusBarItems: [any StatusBarItemProtocol] {
        let charSetCount = ImageDemoHelpers.charSets.count
        let colorModeCount = ImageDemoHelpers.colorModes.count
        return [
            StatusBarItem(shortcut: Shortcut.escape, label: L("page.imageURL.back")),
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
            // +/- zoom. "=" is a hidden synonym for "+" (no Shift needed). At zoom 1
            // the image fits the viewport; zooming in reveals the scrollbars.
            StatusBarItem(shortcut: "+|-", label: ImageDemoHelpers.zoomLabel(zoom), key: .character("+")) {
                zoom = ImageDemoHelpers.zoomedIn(zoom)
            },
            StatusBarItem(shortcut: "=", label: "", key: .character("="), displayInStatusBar: false) {
                zoom = ImageDemoHelpers.zoomedIn(zoom)
            },
            StatusBarItem(shortcut: "-", label: "", key: .character("-"), displayInStatusBar: false) {
                zoom = ImageDemoHelpers.zoomedOut(zoom)
            },
            StatusBarItem(shortcut: Shortcut.arrowsUpDown, label: L("page.imageURL.scroll")),
        ]
    }
}
