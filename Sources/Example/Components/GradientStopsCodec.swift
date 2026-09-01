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
    /// are dropped; NO surviving stop yields `fallback`, so a consumer always
    /// has a drawable gradient.
    ///
    /// One stop is not a failure — it is a solid colour, which the editor's
    /// Gradient switch can produce and every consumer paints. Rejecting it
    /// (this did, at first) silently reverts the switch: the panel writes one
    /// stop, the store hands back the fallback, and the dialog redraws as the
    /// gradient it just stopped being.
    ///
    /// **A stop written without a position is read as evenly spaced**, which
    /// is what the previous format — bare `RRGGBB` stops, from when a gradient
    /// was an even `[Color]` — meant. Stored values migrate by being read.
    ///
    /// The format is colours and positions only. A gradient's colour space is
    /// therefore taken from `fallback`, which is the caller's own default —
    /// storing one would be a third format revision for something no editor
    /// can currently set.
    static func decode(_ raw: String, fallback: Gradient) -> Gradient {
        let fields = raw.split(separator: ",")
        guard !fields.isEmpty else { return fallback }
        var stops: [Gradient.Stop] = []
        for (index, field) in fields.enumerated() {
            let parts = field.split(separator: "@", maxSplits: 1)
            guard let colour = Color.hex(String(parts[0])) else { continue }
            // A lone stop has nowhere to sit, and `index / (count − 1)` would
            // be 0/0 for it.
            let even = fields.count > 1 ? Double(index) / Double(fields.count - 1) : 0
            stops.append(
                Gradient.Stop(
                    color: colour, location: parts.count > 1 ? Double(parts[1]) ?? even : even))
        }
        // `withStops` on the FALLBACK, not `Gradient(stops:)`: the format
        // stores colours and positions and nothing else, so anything else the
        // gradient carries — its colour space — comes from what the caller
        // offered rather than reverting to the default on every reload.
        return stops.isEmpty ? fallback : fallback.withStops(stops)
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
