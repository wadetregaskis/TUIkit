//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RecentValues.swift
//
//  A tiny most-recently-used list persisted through `@AppStorage` as a JSON
//  string: the last hundred values used in a combo field, most recent first.
//  Shared by the custom track-style editors (Slider + ProgressView pages) and
//  anywhere else a `.textInputSuggestions` field wants a "Recents" group.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// Encoding/decoding and MRU bookkeeping for a recents list stored in a
/// single `@AppStorage` string.
enum RecentValues {
    /// How many values a recents list keeps.
    static let limit = 100

    /// The decoded list, most recent first. Malformed storage decodes as
    /// empty rather than failing.
    static func list(from json: String) -> [String] {
        guard let data = json.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return decoded
    }

    /// The storage string for `list`.
    static func encode(_ list: [String]) -> String {
        guard let data = try? JSONEncoder().encode(list),
            let json = String(data: data, encoding: .utf8)
        else { return "[]" }
        return json
    }

    /// Records a use of `value`: moves it to the front (descending
    /// last-use), truncates at ``limit``, and returns the new storage
    /// string. Empty values are not recorded.
    static func recording(_ value: String, in json: String) -> String {
        guard !value.isEmpty else { return json }
        var list = list(from: json)
        list.removeAll { $0 == value }
        list.insert(value, at: 0)
        if list.count > limit {
            list.removeLast(list.count - limit)
        }
        return encode(list)
    }
}
