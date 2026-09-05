//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TruecolorInk.swift
//
//  Reads the truecolor foreground back off a rendered line, cell by cell, so a
//  test can ask "what colour is COLUMN 5" rather than "what is the second
//  escape run" — a probe that counted runs read a `List`'s border and a
//  `Table`'s gutter, and reported both as ignoring `.foregroundStyle`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// The truecolor ink (`r;g;b`) of each visible cell of `line`, `nil` where the
/// cell carries none. A wide glyph contributes one entry per cell it covers.
func truecolorInks(_ line: String) -> [String?] {
    var out: [String?] = []
    var current: String?
    var rest = Substring(line)
    while let escape = rest.firstIndex(of: "\u{1B}") {
        for character in rest[rest.startIndex..<escape] {
            out.append(contentsOf: repeatElement(current, count: character.terminalWidth))
        }
        rest = rest[escape...]
        guard let end = rest.firstIndex(of: "m") else { break }
        let body = rest[rest.index(rest.startIndex, offsetBy: 2)..<end]
        if let range = body.range(of: "38;2;") {
            current = body[range.upperBound...].split(separator: ";").prefix(3)
                .joined(separator: ";")
        } else if body == "0" {
            current = nil
        }
        rest = rest[rest.index(after: end)...]
    }
    for character in rest {
        out.append(contentsOf: repeatElement(current, count: character.terminalWidth))
    }
    return out
}

/// The ink at visible column `column` of `line`, or `nil` off the end or
/// where the cell carries none.
func truecolorInk(_ line: String, atColumn column: Int) -> String? {
    let cells = truecolorInks(line)
    return column < cells.count ? cells[column] : nil
}
