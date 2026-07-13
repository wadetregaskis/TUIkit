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
    @State var charsetIndex: Int = ImageDemoHelpers.Charset.blocks.rawValue
    @State var glyphCount: Int = 0
    @State var blockResolutionIndex: Int = 0
    @State var shapeAware: Bool = false
    @State var colorModeIndex: Int = 0
    @State var ditheringOn: Bool = false
    @State var zoom: Double = 1.0
    @State var supersampling: Int = 0
    @State var edgeLines: Bool = true
    @State var edgeThreshold: Double = 0.9
    @State var customRamp: String = ""

    var body: some View {
        let charSet = ImageDemoHelpers.effectiveCharSet(
            charsetIndex: charsetIndex, glyphCount: glyphCount,
            blockResolutionIndex: blockResolutionIndex, customRamp: customRamp)
        let colorMode = ImageDemoHelpers.colorModes[colorModeIndex]
        let dithering: DitheringMode = ditheringOn ? .floydSteinberg : .none

        // The image lives in a two-axis ScrollView fitted to the viewport: at zoom 1
        // the whole image shows with no scrollbars; `+`/`-` zoom in and out, and the
        // scrollbars appear automatically once it grows past the visible area.
        // The controls and status-bar shortcuts drive the same @State, so either
        // changes the rendering knobs.
        VStack(alignment: .leading, spacing: 1) {
            ImageRenderingControls(
                charsetIndex: $charsetIndex,
                glyphCount: $glyphCount,
                blockResolutionIndex: $blockResolutionIndex,
                shapeAware: $shapeAware,
                colorModeIndex: $colorModeIndex,
                supersampling: $supersampling,
                edgeLines: $edgeLines,
                edgeThreshold: $edgeThreshold,
                customRamp: $customRamp)
            imageContent
                .imageCharacterSet(charSet)
                .imageShapeAware(shapeAware)
                .imageColorMode(colorMode)
                .imageDithering(dithering)
                .imageSupersampling(supersampling == 0 ? nil : supersampling)
                .imageEdgeThreshold(edgeLines ? edgeThreshold : nil)
        }
        .statusBarItems(statusBarItems)
        .appHeader {
            DemoAppHeader(L("page.imageFile.title"))
        }
    }

    @ViewBuilder private var imageContent: some View {
        if let path = Bundle.module.path(forResource: "demo-image", ofType: "jpg", inDirectory: "Resources") {
            Image(.file(path))
                .imagePlaceholder(L("page.imageFile.loading"))
                .imagePlaceholderSpinner(true)
                .zoomableImageScroll(zoom: zoom)
        } else {
            Text("\(L("page.imageFile.resourceNotFound")): demo-image.jpg")
                .foregroundStyle(.error)
        }
    }

    private var statusBarItems: [any StatusBarItemProtocol] {
        let charsetCount = ImageDemoHelpers.Charset.allCases.count
        let colorModeCount = ImageDemoHelpers.colorModes.count
        return [
            StatusBarItem(shortcut: Shortcut.escape, label: L("page.imageFile.back")),
            // c|C — lowercase cycles forward, uppercase cycles
            // backward. The "C" item is hidden so the bar shows
            // a single entry with the dual-key indicator.
            StatusBarItem(
                shortcut: "c|C",
                label: ImageDemoHelpers.charsetLabel(charsetIndex),
                key: .character("c")
            ) {
                charsetIndex = (charsetIndex + 1) % charsetCount
            },
            StatusBarItem(
                shortcut: "C",
                label: "",
                key: .character("C"),
                displayInStatusBar: false
            ) {
                charsetIndex = (charsetIndex - 1 + charsetCount) % charsetCount
            },
            // s toggles shape-aware glyph matching (no-op for custom ramps,
            // which carry no shape calibration).
            StatusBarItem(shortcut: "s", label: shapeAware ? "shape:on" : "shape:off") {
                if ImageDemoHelpers.usesShape(charsetIndex: charsetIndex) {
                    shapeAware.toggle()
                }
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
            StatusBarItem(shortcut: Shortcut.arrowsUpDown, label: L("page.imageFile.scroll")),
        ]
    }
}
