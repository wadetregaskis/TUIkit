//  🖥️ TUIkit — Terminal UI Kit for Swift
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
    @State private var imageURL: String = ""
    @State private var activeURL: String = ""
    @State private var settings = ImageDemoSettings()
    @State private var zoom: Double = 1.0

    var body: some View {
        ImageDemoLayout(settings: $settings) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 1) {
                    Text("page.imageURL.urlLabel")
                        .foregroundStyle(.palette.foregroundSecondary)
                    TextField("page.imageURL.urlPlaceholder", text: $imageURL)
                        .onSubmit {
                            activeURL = imageURL
                        }
                        .textContentType(.url)
                }
                picture
                    .imageDemoSettings(settings)
            }
        }
        .statusBarItems(
            ImageDemoStatusBar.items(settings: $settings, zoom: $zoom, back: "page.imageURL.back"))
        .appHeader {
            DemoAppHeader("menu.item.imageURL")
        }
    }

    @ViewBuilder private var picture: some View {
        if !activeURL.isEmpty {
            // Loaded image fills the rest of the pane in a viewport-fitted,
            // zoomable two-axis scroll (+/- to zoom; scrollbars appear on zoom).
            Image(.url(activeURL))
                .imagePlaceholder("page.imageURL.downloading")
                .imagePlaceholderSpinner(true)
                .zoomableImageScroll(zoom: zoom)
                .border(.palette.border)
        } else {
            Spacer()
            HStack {
                Spacer()
                Text("page.imageURL.pressEnter")
                    .foregroundStyle(.palette.foregroundTertiary)
                    .italic()
                Spacer()
            }
            Spacer()
        }
    }
}
