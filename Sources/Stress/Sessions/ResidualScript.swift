//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ResidualScript.swift
//
//  What someone does to the `residual` page, and what the page must then show.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// MARK: - The script

/// Someone working a page of three panes and a band of odd rows: retyping
/// lines, inserting and deleting them, walking the selection, making the page
/// busy and idle, renaming items and tasks, and moving the focus among the
/// controls — while the band's flags, payloads, tokens, buttons, theme, badge,
/// help text, pick, counters and button style move under it.
@MainActor
final class ResidualSession<Kind: ResidualRowKind>: StressSession {
    private let model: ResidualModel
    private let palette = ResidualPalette()
    private let themes = [ResidualTheme(name: "dawn"), ResidualTheme(name: "dusk")]
    private var random: SessionRandom
    /// The page's own `@State`, as the keys sent so far set it: what the check
    /// expects to see.
    private var selection = 0
    private var busy = false
    private var hint = 0
    private var badge = 1
    private var flags = [false, true, false, true]
    private var flagCursor = 0
    private var theme = 0
    /// How few and how many lines there may be.
    private let lineRange: ClosedRange<Int>

    init(config: StressConfig) {
        let seed = config.seed
        let lineCount = config.sized(24)
        lineRange = max(4, lineCount / 3)...lineCount
        model = ResidualModel(
            lines: (0..<lineCount).map { Self.line(mix(seed, $0)) },
            items: (0..<config.sized(16)).map { ResidualModel.Item(id: $0, title: Self.title($0, mix(seed ^ 0x17E, $0))) },
            tasks: (0..<config.sized(10)).map { ResidualModel.Item(id: $0, title: Synth.slug(mix(seed ^ 0x7A5, $0))) },
            payloads: (0..<ResidualColumns.payloads).map { ResidualNote(id: $0, text: Self.short(mix(seed ^ 0x9A1, $0))) },
            tokens: (0..<ResidualColumns.tokens).map { Self.short(mix(seed ^ 0x70C, $0)) },
            actions: (0..<ResidualColumns.actions).map { ResidualModel.Item(id: $0, title: Self.short(mix(seed ^ 0xAC7, $0))) },
            picks: (0..<8).map { ResidualModel.Item(id: $0, title: Self.short(mix(seed ^ 0x91C, $0))) },
            counters: (0..<ResidualColumns.counters).map { index in
                let range = index == ResidualColumns.widestCounter ? ResidualColumns.wideCounter : ResidualColumns.narrowCounters
                return ResidualCounter(value: range.lowerBound + Int(mix(seed ^ 0xC07, index) % UInt64(range.count)))
            },
            fits: (0..<ResidualColumns.fitRows).map { index in
                ResidualCounter(value: ResidualColumns.fitCounter.lowerBound + Int(mix(seed ^ 0xF17, index) % 21))
            })
        random = SessionRandom(seed: seed ^ 0x2E51)
    }

    /// A line short enough never to be cut by its column.
    private static func line(_ h: UInt64) -> String {
        String(Synth.sentence(h, words: 2 + Int(h % 3)).prefix(ResidualColumns.linesWidth - 6))
    }

    /// An item's title: its number, and a slug cut to fit its column.
    private static func title(_ id: Int, _ h: UInt64) -> String {
        String("\(id) \(Synth.slug(h))".prefix(ResidualColumns.itemsWidth - 2))
    }

    /// A word short enough for any cell of the band.
    private static func short(_ h: UInt64) -> String {
        String(Synth.slug(h).prefix(12))
    }

    var page: ResidualPage<Kind> { ResidualPage(model: model, palette: palette, themes: themes) }

    func step(_ index: Int) -> SessionStep {
        switch random.pick(ResidualWeights.steps) {
        case "select":
            let forward = random.below(3) != 0
            let presses = random.within(1...3)
            let count = model.items.count
            selection = (selection + (forward ? presses : count * presses - presses)) % count
            return SessionStep(
                action: "select",
                keys: Array(repeating: KeyEvent(key: .character(forward ? "j" : "k")), count: presses))
        case "busy":
            busy.toggle()
            return key("busy", "b")
        case "edit":
            // Retyped in place: the row keeps its index, and so its key.
            model.lines[random.below(model.lines.count)] = Self.line(random.next())
            return SessionStep(action: "edit")
        case "insert":
            // Every line below the insertion now reads the line above it.
            guard model.lines.count < lineRange.upperBound else { return SessionStep(action: "quiet") }
            model.lines.insert(Self.line(random.next()), at: random.below(model.lines.count + 1))
            return SessionStep(action: "insert")
        case "remove":
            guard model.lines.count > lineRange.lowerBound else { return SessionStep(action: "quiet") }
            model.lines.remove(at: random.below(model.lines.count))
            return SessionStep(action: "remove")
        case "rename":
            let at = random.below(model.items.count)
            model.items[at].title = Self.title(model.items[at].id, random.next())
            return SessionStep(action: "rename")
        case "retask":
            model.tasks[random.below(model.tasks.count)].title = Synth.slug(random.next())
            return SessionStep(action: "retask")
        case "focus":
            return SessionStep(action: "focus", keys: [KeyEvent(key: .tab)])
        default:
            return band(random.pick(ResidualWeights.band))
        }
    }

    /// A step that moves something in the band, or leaves the page alone.
    private func band(_ action: String) -> SessionStep {
        switch action {
        case "hint":
            hint = (hint + 1) % ResidualColumns.hints.count
            return key("hint", "h")
        case "badge":
            badge = (badge + 1) % 4
            return key("badge", "g")
        case "flag":
            flags[flagCursor].toggle()
            flagCursor = (flagCursor + 1) % flags.count
            return key("flag", "f")
        case "swap":
            theme = (theme + 1) % themes.count
            return key("swap", "t")
        case "reveal":
            return key("reveal", "?")
        case "payload":
            // The same id, new text: the row's `==` cannot tell.
            let at = random.below(model.payloads.count)
            model.payloads[at] = ResidualNote(id: model.payloads[at].id, text: Self.short(random.next()))
            return SessionStep(action: "payload")
        case "token":
            model.tokens[random.below(model.tokens.count)] = Self.short(random.next())
            return SessionStep(action: "token")
        case "action":
            model.actions[random.below(model.actions.count)].title = Self.short(random.next())
            return SessionStep(action: "action")
        case "pick":
            model.pick = random.below(4) == 0 ? nil : model.picks[random.below(model.picks.count)].id
            return SessionStep(action: "pick")
        case "count":
            // Mostly the widest row, far below the stack's window, which only
            // a measure sees and which sets the stack's width; otherwise
            // another row, which never grows past it. (A row that did is the
            // case a kept width re-checks only its widest and drawn rows for,
            // and misses; that is Option C's C3r to fix, not this page's.)
            if random.below(4) != 0 {
                model.counters[ResidualColumns.widestCounter].value = random.within(ResidualColumns.wideCounter)
            } else {
                let other = random.below(model.counters.count - 1)
                let at = other < ResidualColumns.widestCounter ? other : other + 1
                model.counters[at].value = random.within(ResidualColumns.narrowCounters)
            }
            return SessionStep(action: "count")
        case "fit":
            // Across the width where the bar stops fitting, both ways.
            model.fits[random.below(model.fits.count)].value = random.within(ResidualColumns.fitCounter)
            return SessionStep(action: "fit")
        case "angle":
            palette.angled.toggle()
            return SessionStep(action: "angle")
        default:
            return SessionStep(action: "quiet")
        }
    }

    private func key(_ action: String, _ character: Character) -> SessionStep {
        SessionStep(action: action, keys: [KeyEvent(key: .character(character))])
    }

    /// The status lines say what the keys and the model set; every line on
    /// the screen is the model's line at that index, numbered; every item on
    /// the screen is marked exactly when it is the selection; and every row of
    /// the band's first two columns says what the model and the page's state
    /// say it must. What `busy`, the badge, the pick, the help text and the
    /// counters do is styling or a picture the stripped screen cannot place,
    /// which the twin compares.
    ///
    /// Read relative to the status line, wherever the window centres the page,
    /// and only as far down as the page is drawn and above the app's status
    /// bar, whose top border ends what a larger scale may have clipped.
    func check(_ screen: [String], after index: Int) -> String? {
        let status = ResidualStatus.main(selection: selection, busy: busy, lines: model.lines.count)
        guard let top = screen.firstIndex(where: { $0.contains(status) }),
            let found = screen[top].range(of: status)
        else { return "the status line does not say \(status)" }
        let extras = ResidualStatus.extras(
            theme: themes[theme].name, hint: hint, badge: badge, flagsOn: flags.count { $0 }, pick: model.pick,
            sum: (model.counters + model.fits).reduce(0) { $0 + $1.value }, angled: palette.angled)
        guard top + 1 < screen.count, screen[top + 1].contains(extras) else {
            return "the second status line does not say \(extras)"
        }
        let left = screen[top].distance(from: screen[top].startIndex, to: found.lowerBound)
        let bar = screen[(top + 2)...].firstIndex { $0.drop { $0 == " " }.hasPrefix("╭") } ?? screen.count
        // A revealed help text is drawn over whatever is beside the focused
        // task, which the twin compares; the rows are read when none is shown.
        guard !screen.contains(where: { line in ResidualColumns.hints.contains { line.contains($0) } }) else {
            return nil
        }
        if let problem = checkBand(screen, top: top + 2, left: left, bar: bar) { return problem }
        return checkColumns(screen, top: top + 2 + ResidualColumns.bandHeight, left: left, bar: bar)
    }

    /// The band's first column — flags, payloads, tokens — and the swatches
    /// and buttons of its second.
    private func checkBand(_ screen: [String], top: Int, left: Int, bar: Int) -> String? {
        for offset in 0..<ResidualColumns.bandHeight where top + offset < bar {
            let row = Array(screen[top + offset].dropFirst(left))
            let expected: String
            switch offset {
            case ..<ResidualColumns.flags:
                expected = ResidualText.flag(offset, flags[offset])
            case ..<(ResidualColumns.flags + ResidualColumns.payloads):
                let payload = model.payloads[offset - ResidualColumns.flags]
                expected = ResidualText.payload(payload.id, payload.text)
            default:
                let at = offset - ResidualColumns.flags - ResidualColumns.payloads
                expected = ResidualText.token(at, model.tokens[at])
            }
            guard String(row.prefix(expected.count)) == expected else {
                return "band row \(offset) does not read \"\(expected)\": \(String(row))"
            }
            let start = ResidualColumns.linesWidth + 1
            let second = row.count > start ? String(row[start...].prefix(ResidualColumns.itemsWidth)) : ""
            if offset < ResidualColumns.swatches {
                let swatch = ResidualText.swatch(themes[theme].name, offset)
                guard second.hasPrefix(swatch) else {
                    return "swatch \(offset) is drawn \"\(second)\" where \"\(swatch)\" belongs"
                }
            } else if offset < ResidualColumns.swatches + ResidualColumns.actions {
                let title = model.actions[offset - ResidualColumns.swatches].title
                guard second.contains(title) else {
                    return "button \(offset - ResidualColumns.swatches) is drawn \"\(second)\" without \"\(title)\""
                }
            } else if offset < ResidualColumns.swatches + ResidualColumns.actions + ResidualColumns.fitRows {
                let at = offset - ResidualColumns.swatches - ResidualColumns.actions
                let value = model.fits[at].value
                let fit = value <= ResidualColumns.fitsUpTo ? ResidualText.fitBar(at, value) : ResidualText.fitWord(at)
                guard second.hasPrefix(fit) else {
                    return "fitting row \(at) is drawn \"\(second)\" where \"\(fit)\" belongs"
                }
            }
        }
        return nil
    }

    /// The first three shapes: every line at its index, every item marked
    /// exactly when it is the selection, and every task's button in the
    /// brackets the palette says.
    private func checkColumns(_ screen: [String], top: Int, left: Int, bar: Int) -> String? {
        let tall = max(model.lines.count, model.items.count, model.tasks.count)
        guard top < bar else { return nil }
        for (offset, line) in screen[top..<min(bar, top + tall)].enumerated() {
            let row = Array(line.dropFirst(left))
            if offset < model.lines.count {
                let expected = ResidualLabels.line(offset + 1) + model.lines[offset]
                guard String(row.prefix(expected.count)) == expected else {
                    return "line \(offset + 1) does not read \"\(expected)\": \(String(row))"
                }
            }
            if offset < model.items.count {
                let item = model.items[offset]
                let expected = (item.id == selection ? "> " : "  ") + item.title
                let start = ResidualColumns.linesWidth + 1
                let drawn = row.count > start ? String(row[start...].prefix(expected.count)) : ""
                guard drawn == expected else {
                    return "item \(item.id) is drawn \"\(drawn)\" where \"\(expected)\" belongs"
                }
            }
            if offset < model.tasks.count {
                let task = model.tasks[offset]
                let button = palette.angled ? "<\(task.title)>" : "[\(task.title)]"
                let start = ResidualColumns.linesWidth + ResidualColumns.itemsWidth + 2
                let drawn = row.count > start ? String(row[start...]) : ""
                guard drawn.contains(button) else {
                    return "task \(task.id) is drawn \"\(drawn)\" without \"\(button)\""
                }
            }
        }
        return nil
    }

    static var descriptor: SessionDescriptor {
        SessionDescriptor(
            id: Kind.sessionID,
            summary: "rows that draw what is not their element: lines by index, a selection mark, a parent's "
                + "busy, and a band of the shapes Option C's reviews named — \(Kind.rowsSummary)",
            exercises:
                "index-keyed rows reading document.lines[i] retyped, inserted above and removed; a row "
                + "computing selection == item.id; a parent @State driving .disabled, .bold and .help into "
                + "rows; rows holding a Binding, an existential or a token memo; an injected object swapped; "
                + "Button rows; a List whose selection is bound to a model and whose rows carry a badge; "
                + "off-window rows reading counters of their own; a custom ButtonStyle reading a model — "
                + "each right today only because the write clears everything below the page",
            make: { config, width, height, cold in
                DrivenSession(ResidualSession(config: config), width: width, height: height, cold: cold)
            })
    }
}

/// How often the script takes each kind of step.
enum ResidualWeights {
    /// The first three shapes, as the session has always weighted them, and
    /// the band's share.
    static let steps: [(String, Int)] = [
        ("select", 22), ("busy", 12), ("edit", 20), ("insert", 8), ("remove", 6), ("rename", 8),
        ("retask", 6), ("focus", 6), ("band", 48),
    ]

    /// How the band's share divides, with the page left alone as often as it
    /// always was.
    static let band: [(String, Int)] = [
        ("hint", 3), ("badge", 3), ("flag", 4), ("swap", 3), ("reveal", 2), ("payload", 4), ("token", 4),
        ("action", 3), ("pick", 3), ("count", 5), ("fit", 4), ("angle", 3), ("quiet", 7),
    ]
}
