//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ThemesSession.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// MARK: - The script

/// Someone working through a task list — walking and selecting rows, tabbing
/// through a form, typing, toggling, saving, choosing from a menu — while the
/// look changes under them: the app's palette cycled with `t` through every
/// one TUIkit ships, the form put in a palette of the session's own, the table
/// in another, the colour depth dropped to 256 and 16 colours and raised
/// again, a tint flipped over a band of controls, some of it while the menu is
/// open — and quiet steps between, while the focused rows breathe.
@MainActor
final class ThemesSession: StressSession {
    let board: ThemeBoard
    private var random: SessionRandom
    /// The steps still to come of an activity under way, each built when it is
    /// played.
    private var pending: [() -> SessionStep] = []
    /// The screen as it stood before this step.
    private(set) var screen: [String] = []
    /// The app's palette: an index into `PaletteRegistry.all`, which `t`
    /// cycles as the app's palette manager does.
    private(set) var rootIndex = 0
    /// The depth the frames are drawn at.
    private(set) var depth: ColorDepth = .truecolor
    /// The saves the session has made: what the status line must count.
    private(set) var expectedSaves = 0
    /// The palettes drawn in before the last change of look, by region: what
    /// no cell may still show once the change has been drawn.
    private(set) var retired: [any Palette] = []

    /// The depths the session cycles through.
    static let depths: [ColorDepth] = [.truecolor, .palette256, .basic16]
    /// The tints the tinted band cycles through.
    static let tints: [Color?] = [nil, .rgb(220, 60, 160), .rgb(40, 200, 120), .ansi(.blue)]

    init(config: StressConfig) {
        let seed = config.seed
        board = ThemeBoard(
            tasks: (0..<config.sized(24)).map { index in
                let h = mix(seed, index)
                return ThemeBoard.Task(
                    id: index, title: Synth.sentence(h, words: 1 + Int(h % 3)), owner: Synth.name(h >> 8),
                    hours: 1 + Int(h % 40))
            })
        random = SessionRandom(seed: seed ^ 0x7E4E)
    }

    var page: ThemesPage { ThemesPage(board: board) }

    var looksBeforeEachStep: Bool { true }

    func look(at screen: [String]) { self.screen = screen }

    var colorDepth: ColorDepth? { depth }

    /// The app's palette.
    var rootPalette: any Palette { PaletteRegistry.all[rootIndex] }

    /// The palette the form is drawn in.
    var formPalette: any Palette { board.formPalette ?? rootPalette }

    /// Every palette on the screen now: the app's (the header, the status bar,
    /// the list), the form's and the table's.
    var palettesInUse: [any Palette] {
        [rootPalette, formPalette] + (board.tablePalette.map { [$0] } ?? [])
    }

    /// The focus the status line reports, or `nil` when it is not on the screen.
    var focusShown: String? { Self.focus(on: screen) }

    /// The focus `screen`'s status line reports.
    static func focus(on screen: [String]) -> String? {
        guard let line = screen.first(where: { $0.hasPrefix("[") && $0.contains(" saved") }),
            let end = line.firstIndex(of: "]")
        else { return nil }
        return String(line[line.index(after: line.startIndex)..<end])
    }

    // MARK: Steps

    func step(_ index: Int) -> SessionStep {
        // The page's `@FocusState` reads the focus the first frame gave out a
        // frame late, so the first step lets it.
        if index == 0 { return SessionStep(action: "settle") }
        if !pending.isEmpty { return pending.removeFirst()() }
        // Each activity with its weight: how often a person does it.
        let activities: [((ThemesSession) -> SessionStep, Int)] = [
            ({ $0.walk() }, 22), ({ $0.select() }, 8), ({ _ in SessionStep(action: "tab", keys: [KeyEvent(key: .tab)]) }, 12),
            ({ $0.type() }, 6), ({ $0.pressing(" ", on: "pinned", action: "toggle") }, 4), ({ $0.save() }, 4),
            ({ $0.menu() }, 5), ({ $0.cycleTheme() }, 12), ({ $0.custom() }, 5), ({ $0.tablePalette() }, 5),
            ({ $0.changeDepth() }, 7), ({ $0.tint() }, 5), ({ _ in SessionStep(action: "quiet") }, 14),
            ({ $0.resize() }, 2),
        ]
        return random.pick(activities)(self)
    }

    /// The tint over the tinted band, changed.
    private func tint() -> SessionStep {
        board.tint = Self.tints[random.below(Self.tints.count)]
        return SessionStep(action: "tint")
    }

    /// Return on Save, where it holds the focus.
    private func save() -> SessionStep {
        guard focusShown == "save" else { return SessionStep(action: "tab", keys: [KeyEvent(key: .tab)]) }
        expectedSaves += 1
        return SessionStep(action: "save", keys: [KeyEvent(key: .enter)])
    }

    private func resize() -> SessionStep {
        let sizes = [(120, 40), (100, 30), (132, 44)]
        let (width, height) = sizes[random.below(sizes.count)]
        return SessionStep(action: "resize", resize: (width, height))
    }

    /// The form in the session's own palette, or back in the app's.
    private func custom() -> SessionStep {
        changeLook("custom") { $0.board.formPalette = $0.board.formPalette == nil ? HarbourPalette() : nil }
    }

    /// The table in a shipped palette, or back in the app's.
    private func tablePalette() -> SessionStep {
        let choice = random.below(PaletteRegistry.all.count + 1)
        return changeLook("table-palette") {
            $0.board.tablePalette = choice < PaletteRegistry.all.count ? PaletteRegistry.all[choice] : nil
        }
    }

    /// The depth moved to another, named by where it goes, so a trace says
    /// which way.
    private func changeDepth() -> SessionStep {
        let next = Self.depths[((Self.depths.firstIndex(of: depth) ?? 0) + 1 + random.below(2)) % Self.depths.count]
        let name = next == .truecolor ? "truecolour" : next == .palette256 ? "256-colour" : "16-colour"
        return changeLook(name) { $0.depth = next }
    }

    /// The More menu opened with Return where it holds the focus; then, with
    /// it open, the look changed under it or not; then an item chosen, or the
    /// menu dismissed. Not `t`, which an open menu keeps from the app.
    private func menu() -> SessionStep {
        guard focusShown == "more" else { return SessionStep(action: "tab", keys: [KeyEvent(key: .tab)]) }
        let under: [() -> SessionStep] =
            switch random.below(4) {
            case 0: [{ [weak self] in self?.changeDepth() ?? SessionStep(action: "quiet") }]
            case 1: [{ [weak self] in self?.custom() ?? SessionStep(action: "quiet") }]
            case 2: [{ SessionStep(action: "menu-quiet") }]
            default: []
            }
        let choose = random.below(3) != 0
        pending = under + [
            { [weak self] in
                guard choose else { return SessionStep(action: "menu-dismiss", keys: [KeyEvent(key: .escape)]) }
                self?.expectedSaves += 1
                return SessionStep(action: "menu-choose", keys: [KeyEvent(key: .down), KeyEvent(key: .enter)])
            },
            // A frame for the focus to come back to the menu's label, where
            // the status line shows it.
            { SessionStep(action: "settle") },
        ]
        return SessionStep(action: "menu-open", keys: [KeyEvent(key: .enter)])
    }

    /// A change of look: the palettes drawn in until now are retired, then the
    /// change is made.
    private func changeLook(_ action: String, _ change: (ThemesSession) -> Void) -> SessionStep {
        let before = palettesInUse
        change(self)
        retired = before
        return SessionStep(action: action)
    }

    /// `t`, which cycles the app's palette — from anywhere but the title
    /// field, where it would be typed. From there, Tab out first.
    private func cycleTheme() -> SessionStep {
        // Only where the status line says where the focus is: a short terminal
        // cuts it off, and a `t` into the title would be typed.
        guard focusShown.map({ $0 != "title" }) == true else {
            return SessionStep(action: "tab", keys: [KeyEvent(key: .tab)])
        }
        let before = palettesInUse
        rootIndex = (rootIndex + 1) % PaletteRegistry.all.count
        retired = before
        return SessionStep(action: "theme", keys: [KeyEvent(key: .character("t"))])
    }

    /// Up or Down in the list, when it holds the focus; Tab towards it when not.
    private func walk() -> SessionStep {
        guard focusShown == "list" else { return SessionStep(action: "tab", keys: [KeyEvent(key: .tab)]) }
        let down = random.below(3) != 0
        return SessionStep(action: "walk", keys: [KeyEvent(key: down ? .down : .up)])
    }

    /// Return on the cursor row, which selects it.
    private func select() -> SessionStep {
        guard focusShown == "list" else { return SessionStep(action: "tab", keys: [KeyEvent(key: .tab)]) }
        return SessionStep(action: "select", keys: [KeyEvent(key: .enter)])
    }

    /// A word typed into the title, when it holds the focus.
    private func type() -> SessionStep {
        guard focusShown == "title" else { return SessionStep(action: "tab", keys: [KeyEvent(key: .tab)]) }
        let word = Synth.sentence(random.next(), words: 1) + " "
        return SessionStep(
            action: "type", keys: word.map { $0 == " " ? KeyEvent(key: .space) : KeyEvent(key: .character($0)) })
    }

    /// Space or Return on the control named `focus`, when it holds the focus.
    private func pressing(_ key: Character, on focus: String, action: String) -> SessionStep {
        guard focusShown == focus else { return SessionStep(action: "tab", keys: [KeyEvent(key: .tab)]) }
        return SessionStep(action: action, keys: [KeyEvent(key: key == " " ? .space : .enter)])
    }

    static let descriptor = SessionDescriptor(
        id: "themes",
        summary: "a task list and form whose palette, colour depth and tint change while it is used",
        exercises:
            "every shipped palette cycled with `t`, a custom one on the form, any one on the table; truecolour, "
            + "256 and 16 colours; a tint flipped over a band of controls; a translucent line; the look changed "
            + "under an open menu — while rows are walked and selected, a form is filled in and the focused rows "
            + "breathe",
        make: { config, width, height, cold in
            DrivenSession(ThemesSession(config: config), width: width, height: height, cold: cold)
        })
}
