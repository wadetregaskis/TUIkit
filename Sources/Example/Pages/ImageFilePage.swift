//  🖥️ TUIkit — Terminal UI Kit for Swift
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
    @State private var settings = ImageDemoSettings()
    @State private var zoom: Double = 1.0

    var body: some View {
        // The image lives in a two-axis ScrollView fitted to the viewport: at zoom 1
        // the whole image shows with no scrollbars; `+`/`-` zoom in and out, and the
        // scrollbars appear automatically once it grows past the visible area.
        // The controls and status-bar shortcuts drive the same @State, so either
        // changes the rendering knobs.
        ImageDemoLayout(settings: $settings) {
            imageContent
                .imageDemoSettings(settings)
        }
        .statusBarItems(statusBarItems)
        .appHeader {
            DemoAppHeader("menu.item.imageFile")
        }
    }

    @ViewBuilder private var imageContent: some View {
        if let path = Bundle.module.path(forResource: "demo-image", ofType: "jpg", inDirectory: "Resources") {
            Image(.file(path))
                .imagePlaceholder("page.imageFile.loading")
                .imagePlaceholderSpinner(true)
                .zoomableImageScroll(zoom: zoom)
        } else {
            Text("\(L("page.imageFile.resourceNotFound")): demo-image.jpg")
                .foregroundStyle(.error)
        }
    }

    private var statusBarItems: [any StatusBarItemProtocol] {
        ImageDemoStatusBar.items(settings: $settings, zoom: $zoom, back: "page.imageFile.back")
    }
}
