//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScreenCells.swift
//
//  A drawn frame taken apart into cells, each with the colours it is drawn
//  in: what a session's styled check reads when what it must judge is not the
//  text on the screen but how it is painted — which row of an open menu is
//  highlighted, whether a label stays readable on the fill behind it, whether
//  a colour of the palette before a switch is still on the screen.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// One terminal cell as the frame paints it: its character and the colours
/// the SGR in force there states, reverse video already swapped out, so
/// ``foreground`` is the ink the cell shows and ``background`` its field.
struct ScreenCell: Equatable {
    /// The character drawn, or `nil` for the second column of a wide one.
    var character: Character?
    /// The ink, or `nil` for the terminal's own.
    var foreground: Color?
    /// The field, or `nil` for the terminal's own.
    var background: Color?
    var isBold = false
    var isDim = false

    /// Whether the cell shows ink: a character that is not a space.
    var hasInk: Bool {
        guard let character else { return false }
        return !character.isWhitespace
    }

    /// A colour as a report names it: `#rrggbb`, or `default` for the
    /// terminal's own. A named or indexed colour whose RGB nobody reported is
    /// named by its SGR.
    static func name(_ colour: Color?) -> String {
        guard let colour else { return "default" }
        if let rgb = colour.rgbComponents {
            return "#" + [rgb.red, rgb.green, rgb.blue].map { String(format: "%02x", $0) }.joined()
        }
        return colour.foregroundCodes(depth: .truecolor).joined(separator: ";")
    }
}

/// How a colour was spelled on the wire — what a colour depth decides.
enum ColourSpelling: Comparable, Hashable, CustomStringConvertible {
    /// One of the sixteen named codes (30–37, 90–97 and their fields).
    case named
    /// A 256-colour index (`38;5;n`).
    case indexed
    /// 24 bits (`38;2;r;g;b`).
    case rgb

    /// The spelling TUIkit gives the colours it computes at `depth`: 24 bits,
    /// an index into the 256, or one of the sixteen — `nil` where it spells
    /// none. A named colour is spelled by name at every depth.
    static func computed(at depth: ColorDepth) -> Self? {
        switch depth {
        case .noColor: nil
        case .basic16: .named
        case .palette256: .indexed
        case .truecolor: .rgb
        }
    }

    var description: String {
        switch self {
        case .named: "one of the sixteen"
        case .indexed: "a 256-colour index"
        case .rgb: "24 bits"
        }
    }
}

/// A frame's lines, each taken apart into ``ScreenCell``s, and where each
/// spelling of a colour first appears in it.
struct ScreenCells {
    /// One row of cells per line, a cell per column.
    let rows: [[ScreenCell]]
    /// The first cell each spelling of a colour paints, by spelling: a frame
    /// drawn for a 256-colour terminal must state no 24-bit colour anywhere,
    /// and one drawn for a truecolour terminal no index TUIkit computed.
    let spellings: [ColourSpelling: (row: Int, column: Int)]

    init(_ lines: [String]) {
        var spellings: [ColourSpelling: (row: Int, column: Int)] = [:]
        rows = lines.enumerated().map { row, line in
            var parser = CellParser()
            let cells = parser.cells(of: line)
            for (spelling, column) in parser.spellings where spellings[spelling] == nil {
                spellings[spelling] = (row, column)
            }
            return cells
        }
        self.spellings = spellings
    }

    /// The cell at `column` of `row`, or `nil` off the frame.
    func cell(row: Int, column: Int) -> ScreenCell? {
        guard rows.indices.contains(row), rows[row].indices.contains(column) else { return nil }
        return rows[row][column]
    }
}

/// Reads one line's SGR as a terminal would, cell by cell.
private struct CellParser {
    private var foreground: (Color, ColourSpelling)?
    private var background: (Color, ColourSpelling)?
    private var bold = false
    private var dim = false
    private var reversed = false
    /// The first column each spelling paints.
    private(set) var spellings: [ColourSpelling: Int] = [:]

    mutating func cells(of line: String) -> [ScreenCell] {
        var cells: [ScreenCell] = []
        var characters = line[...]
        while let first = characters.first {
            if first == "\u{1B}" {
                characters = consumeEscape(characters)
                continue
            }
            characters = characters.dropFirst()
            let ink = reversed ? background : foreground
            let field = reversed ? foreground : background
            for spelling in [ink?.1, field?.1].compactMap({ $0 }) where spellings[spelling] == nil {
                spellings[spelling] = cells.count
            }
            let cell = ScreenCell(
                character: first, foreground: ink?.0, background: field?.0, isBold: bold, isDim: dim)
            cells.append(cell)
            for _ in 1..<max(1, first.terminalWidth) {
                var continuation = cell
                continuation.character = nil
                cells.append(continuation)
            }
        }
        return cells
    }

    /// Consumes the escape sequence at the front of `text`, applying it when it
    /// is SGR, and returns what follows it.
    private mutating func consumeEscape(_ text: Substring) -> Substring {
        var rest = text.dropFirst()
        switch rest.first {
        case "[":
            rest = rest.dropFirst()
            let body = rest.prefix { !("@"..."~").contains($0) }
            rest = rest.dropFirst(body.count)
            if rest.first == "m" { apply(String(body)) }
            return rest.dropFirst()
        case "]":
            // An operating-system command, such as a hyperlink: up to BEL or ST.
            while let character = rest.first {
                rest = rest.dropFirst()
                if character == "\u{07}" { break }
                if character == "\u{1B}", rest.first == "\\" { return rest.dropFirst() }
            }
            return rest
        default:
            return rest.dropFirst()
        }
    }

    private mutating func apply(_ parameters: String) {
        var codes = parameters.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        if codes.isEmpty { codes = [0] }
        var index = 0
        while index < codes.count {
            let code = codes[index]
            index += 1
            switch code {
            case 30...37, 90...97, 39, 40...47, 100...107, 49: applyNamed(code)
            case 38, 48:
                let colour = extended(codes, at: &index)
                if code == 38 { foreground = colour } else { background = colour }
            default: applyAttribute(code)
            }
        }
    }

    /// A named colour's code, or a default's.
    private mutating func applyNamed(_ code: Int) {
        switch code {
        case 30...37: foreground = named(code - 30)
        case 90...97: foreground = named(code - 90 + 8)
        case 40...47: background = named(code - 40)
        case 100...107: background = named(code - 100 + 8)
        case 39: foreground = nil
        default: background = nil
        }
    }

    /// A reset, or an attribute turned on or off.
    private mutating func applyAttribute(_ code: Int) {
        switch code {
        case 0:
            foreground = nil
            background = nil
            bold = false
            dim = false
            reversed = false
        case 1: bold = true
        case 2: dim = true
        case 22:
            bold = false
            dim = false
        case 7: reversed = true
        case 27: reversed = false
        default: break
        }
    }

    private func named(_ slot: Int) -> (Color, ColourSpelling)? {
        ANSIColor(rawValue: UInt8(slot)).map { (Color.ansi($0), .named) }
    }

    private func extended(_ codes: [Int], at index: inout Int) -> (Color, ColourSpelling)? {
        guard index < codes.count else { return nil }
        let form = codes[index]
        index += 1
        if form == 5, index < codes.count {
            defer { index += 1 }
            return (Color.palette256(UInt8(clamping: codes[index])), .indexed)
        }
        if form == 2, index + 2 < codes.count {
            defer { index += 3 }
            return (
                Color.rgb(
                    UInt8(clamping: codes[index]), UInt8(clamping: codes[index + 1]),
                    UInt8(clamping: codes[index + 2])),
                .rgb
            )
        }
        return nil
    }
}
