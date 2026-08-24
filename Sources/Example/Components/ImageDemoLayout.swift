//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageDemoLayout.swift
//
//  The shape of an image demo page — the picture and its controls side by
//  side — and the status bar both pages carry.
//
//  Side by side rather than stacked because of what the controls are FOR: you
//  change one and look at the picture. A strip above the image took its height
//  from the picture and grew every time a knob was added, and the vertical
//  space it took was the space the picture wanted most; a column takes width,
//  of which a terminal running an image demo has plenty.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// A picture, and the pane of controls that drives it.
struct ImageDemoLayout<Content: View>: View {
    @Binding var settings: ImageDemoSettings
    @ViewBuilder let content: Content

    /// How wide the control pane is, borders included. Wide enough for the
    /// widest row it holds (the block-resolution radio row) *with* the
    /// scrollbar the pane grows on a short terminal, and no wider — every
    /// column past that is one the picture does not get.
    private static var paneWidth: Int { 44 }

    var body: some View {
        HStack(alignment: .top, spacing: 1) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            // A box rather than a `Divider`, which draws a HORIZONTAL rule
            // whichever stack it is in (SwiftUI's takes its orientation from
            // the layout; TUIkit's does not yet). The border is doing the
            // separating either way, and a box reads as a pane.
            ImageRenderingControls(settings: $settings)
                .border(.palette.border)
                .frame(width: Self.paneWidth)
        }
    }
}

/// The status bar both image pages carry: the same knobs the pane holds, on
/// single keys, because a demo of an image renderer is a thing you want to
/// flick through without leaving the picture.
///
/// Shared rather than written twice. The two pages had drifted already — the
/// file page grew the tone cycler and the URL page did not, so the same app
/// answered `n` in two ways depending on which page you were on.
enum ImageDemoStatusBar {
    @MainActor
    static func items(
        settings: Binding<ImageDemoSettings>, zoom: Binding<Double>, back: LocalizedStringKey
    ) -> [any StatusBarItemProtocol] {
        [
            StatusBarItem(shortcut: Shortcut.escape, label: back),
            // c|C — lowercase cycles forward, uppercase cycles backward. The
            // "C" item is hidden so the bar shows a single entry with the
            // dual-key indicator.
            StatusBarItem(
                shortcut: "c|C",
                label: ImageDemoHelpers.charsetLabel(settings.wrappedValue.charset),
                key: .character("c")
            ) {
                settings.wrappedValue.charset = ImageDemoSettings.cycled(
                    settings.wrappedValue.charset, by: 1)
            },
            StatusBarItem(
                shortcut: "C", label: "", key: .character("C"), displayInStatusBar: false
            ) {
                settings.wrappedValue.charset = ImageDemoSettings.cycled(
                    settings.wrappedValue.charset, by: -1)
            },
            // s toggles shape-aware glyph matching (no-op for custom ramps,
            // which carry no shape calibration).
            StatusBarItem(
                shortcut: "s", label: settings.wrappedValue.shapeAware ? "shape:on" : "shape:off"
            ) {
                if ImageDemoHelpers.usesShape(settings.wrappedValue.charset) {
                    settings.wrappedValue.shapeAware.toggle()
                }
            },
            StatusBarItem(
                shortcut: "m|M", label: settings.wrappedValue.colourLabel, key: .character("m")
            ) {
                settings.wrappedValue.colour = ImageDemoSettings.cycled(
                    settings.wrappedValue.colour, by: 1)
            },
            StatusBarItem(
                shortcut: "M", label: "", key: .character("M"), displayInStatusBar: false
            ) {
                settings.wrappedValue.colour = ImageDemoSettings.cycled(
                    settings.wrappedValue.colour, by: -1)
            },
            // A transfer curve, not a palette: it says what the tones BECOME
            // and keeps every one of them, which is why an inversion here is a
            // negative rather than a two-colour image.
            StatusBarItem(
                shortcut: "n|N", label: settings.wrappedValue.toneLabel, key: .character("n")
            ) {
                settings.wrappedValue.tone = ImageDemoSettings.cycled(
                    settings.wrappedValue.tone, by: 1)
            },
            StatusBarItem(
                shortcut: "N", label: "", key: .character("N"), displayInStatusBar: false
            ) {
                settings.wrappedValue.tone = ImageDemoSettings.cycled(
                    settings.wrappedValue.tone, by: -1)
            },
            // d is a binary toggle — a Shift variant would be a no-op, so no
            // "D" partner.
            StatusBarItem(
                shortcut: "d", label: settings.wrappedValue.dithering ? "dither:on" : "dither:off"
            ) {
                settings.wrappedValue.dithering.toggle()
            },
            // +/- zoom. "=" is a hidden synonym for "+" (no Shift needed). At
            // zoom 1 the image fits the viewport; zooming in reveals the
            // scrollbars.
            StatusBarItem(
                shortcut: "+|-", label: ImageDemoHelpers.zoomLabel(zoom.wrappedValue),
                key: .character("+")
            ) {
                zoom.wrappedValue = ImageDemoHelpers.zoomedIn(zoom.wrappedValue)
            },
            StatusBarItem(
                shortcut: "=", label: "", key: .character("="), displayInStatusBar: false
            ) {
                zoom.wrappedValue = ImageDemoHelpers.zoomedIn(zoom.wrappedValue)
            },
            StatusBarItem(
                shortcut: "-", label: "", key: .character("-"), displayInStatusBar: false
            ) {
                zoom.wrappedValue = ImageDemoHelpers.zoomedOut(zoom.wrappedValue)
            },
            StatusBarItem(shortcut: Shortcut.arrowsUpDown, label: "page.imageFile.scroll"),
        ]
    }
}

extension View {
    /// Applies an ``ImageDemoSettings`` to an image.
    ///
    /// One place, so the two pages cannot apply different subsets of it — which
    /// they did: the URL page never applied a tone curve at all.
    func imageDemoSettings(_ settings: ImageDemoSettings) -> some View {
        self
            .imageCharacterSet(settings.characterSet)
            .imageShapeAware(settings.shapeAware)
            .imageColorMode(settings.colorMode)
            .imageToneCurve(settings.toneCurve)
            .imageDithering(settings.ditheringMode)
            .imageSupersampling(settings.supersampling == 0 ? nil : settings.supersampling)
            .imageEdgeThreshold(settings.edgeLines ? settings.edgeThreshold : nil)
    }
}
