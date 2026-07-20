//  🖥️ TUIKit — Terminal UI Kit for Swift
//  GradientStopsCodec.swift
//
//  Gradient stops ⇄ comma-separated hex, for persisting an editable gradient
//  in @AppStorage. Shared by the ProgressView page's indeterminate-sweep
//  gradient and the track-style editor's fill gradient.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

enum GradientStopsCodec {
    /// Decodes comma-separated hex (`"3CC8BE,506EF0"`) to colours. Invalid
    /// entries are dropped; fewer than two surviving stops yields `fallback`,
    /// so a consumer always has a drawable gradient.
    static func decode(_ raw: String, fallback: [Color]) -> [Color] {
        let parsed = raw.split(separator: ",").compactMap { Color.hex(String($0)) }
        return parsed.count >= 2 ? parsed : fallback
    }

    /// Encodes colours as comma-separated hex for storage.
    static func encode(_ stops: [Color]) -> String {
        stops.map { color in
            guard let c = color.rgbComponents else { return "000000" }
            return String(format: "%02X%02X%02X", c.red, c.green, c.blue)
        }.joined(separator: ",")
    }
}
