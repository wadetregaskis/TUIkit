//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GradientStopsCodec.swift
//
//  A Gradient ⇄ a string, for persisting an editable gradient in @AppStorage.
//  Shared by the ProgressView page's indeterminate-sweep gradient and the
//  track-style editor's fill gradient.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

enum GradientStopsCodec {
    /// Decodes `"3CC8BE@0.000,506EF0@1.000"` to a gradient. Invalid entries
    /// are dropped; fewer than two surviving stops yields `fallback`, so a
    /// consumer always has a drawable gradient.
    ///
    /// **A stop written without a position is read as evenly spaced**, which
    /// is what the previous format — bare `RRGGBB` stops, from when a gradient
    /// was an even `[Color]` — meant. Stored values migrate by being read.
    static func decode(_ raw: String, fallback: Gradient) -> Gradient {
        let fields = raw.split(separator: ",")
        guard fields.count >= 2 else { return fallback }
        var stops: [Gradient.Stop] = []
        for (index, field) in fields.enumerated() {
            let parts = field.split(separator: "@", maxSplits: 1)
            guard let colour = Color.hex(String(parts[0])) else { continue }
            let even = Double(index) / Double(fields.count - 1)
            stops.append(
                Gradient.Stop(
                    color: colour, location: parts.count > 1 ? Double(parts[1]) ?? even : even))
        }
        return stops.count >= 2 ? Gradient(stops: stops) : fallback
    }

    /// Encodes a gradient for storage — the inverse of ``decode(_:fallback:)``.
    static func encode(_ gradient: Gradient) -> String {
        gradient.stops.map { stop in
            let hex: String
            if let components = stop.color.rgbComponents {
                hex = String(
                    format: "%02X%02X%02X", components.red, components.green, components.blue)
            } else {
                hex = "000000"
            }
            return hex + String(format: "@%.3f", stop.location)
        }.joined(separator: ",")
    }
}
