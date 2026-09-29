//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MenusSession.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// MARK: - What is open

/// A menu the session has open, as the session expects it to be.
struct OpenMenu {
    enum Kind: Equatable {
        /// A pop-up `Menu`, by its label.
        case popUp(String)
        /// The status filter's drop-down.
        case picker
        /// A document's context menu.
        case context(Int)
        /// The tag field's suggestions.
        case suggestions
    }

    let kind: Kind
    /// Where the focus was before it opened, as the status line said: where it
    /// must be once it closes.
    let focusBefore: String?
    /// The highlighted row, as an index into the selectable rows, or `nil`.
    var highlight: Int?
    /// Whether the session knows ``highlight`` — not for a menu that went from
    /// the screen and came back.
    var knowsHighlight = true
    /// Whether it was opened this step, by a press whose release is still to
    /// come — the tail of the opening click, which chooses nothing.
    var awaitingRelease = false
}

// MARK: - The script

/// Someone running a document manager from its menus: pop-up menus at the top
/// and bottom corners, a status drop-down, context menus on the documents, an
/// inline menu down the side and a tag field that suggests — each opened by
/// the keyboard and by the mouse (a click, or a press dragged to a row),
/// walked with the arrows, and closed by choosing, by Escape or by a click
/// elsewhere; while documents arrive, leave and are renamed underneath an open
/// menu, the File menu's own recent items change while it is up, and the
/// terminal is made short and narrow around it.
@MainActor
final class MenusSession: StressSession {
    let desk: MenuDesk
    private var random: SessionRandom
    /// The steps still to come of an activity under way, each built when it is
    /// played, against the screen as it then stands.
    private var pending: [() -> SessionStep] = []
    /// The screen as it stood before this step.
    private(set) var screen: [String] = []
    /// The menu the session has open, as it expects it.
    private(set) var open: OpenMenu?
    /// The commands the session has run: what ``MenuDesk/applied`` must say.
    private(set) var expectedApplied = 0
    /// What the status filter must say.
    private(set) var expectedFilter = 0
    /// The command the session last chose, as ``MenuDesk/last`` must say it
    /// ran — or `nil` when the session cannot tell which (Return on the inline
    /// menu runs whichever of its rows holds the focus). A count alone passes
    /// a hit map that runs the row beside the one clicked.
    private(set) var expectedLast: String? = "—"
    /// Where the focus must be once a closed menu has handed it back, and the
    /// step whose frame first shows it. TUIkit hands it back at the end of the
    /// pass that closes the menu, after the page has drawn — it asks for the
    /// next frame to show it (`FocusManager.endRenderPass`) — so the page's
    /// `@FocusState` reads it one frame late.
    private(set) var focusAfterClose: (focus: String, from: Int)?
    /// A menu that went from the screen while open — its anchor scrolled out
    /// of view — and was dismissed with Escape, which it may not have heard.
    private(set) var lost: OpenMenu.Kind?
    /// Whether a menu has gone out of view with its anchor this run — which
    /// the checks, not the script, record: see `tagIfAfterALostMenu`.
    var lostAMenu = false
    /// The step being played.
    private var stepIndex = 0
    /// A menu left open, its rows nowhere on the screen: its anchor moved out of
    /// the scroll view it sits in (a document inserted above it), the scroll
    /// view culled the pop-up with it, and the menu kept the keyboard.
    static let anchorOutOfView = "menu-anchor-out-of-view"

    var knownIssues: [String: String] {
        [
            Self.anchorOutOfView:
                "an open menu whose anchor scrolls out of its scroll view is culled with it but stays open, "
                + "holding the keyboard; fixed later in this series"
        ]
    }

    /// The sizes the session makes the terminal: roomy, short, narrow, both.
    private static let sizes = [(120, 40), (80, 22), (60, 16), (44, 12), (100, 13), (36, 30)]

    init(config: StressConfig) {
        let seed = config.seed
        desk = MenuDesk(
            documents: (0..<config.sized(40)).map { index in
                let h = mix(seed, index)
                return MenuDesk.Document(
                    id: index, name: Synth.sentence(h, words: 1 + Int(h % 3)), status: Int(h % 3))
            })
        random = SessionRandom(seed: seed ^ 0x3E75)
    }

    var page: MenusPage { MenusPage(desk: desk) }

    var looksBeforeEachStep: Bool { true }

    func look(at screen: [String]) { self.screen = screen }

    // MARK: Steps

    func step(_ index: Int) -> SessionStep {
        stepIndex = index
        // The page's `@FocusState` reads the focus the first frame gave out a
        // frame late (see `focusAfterClose`), so the first step lets it.
        if index == 0 { return SessionStep(action: "settle") }
        if !pending.isEmpty { return pending.removeFirst()() }
        if open == nil, let kind = lost, shows(kind) {
            // A menu that went with its anchor, back with it: open, as far as
            // anyone looking can tell, with a highlight nobody chose.
            open = OpenMenu(kind: kind, focusBefore: nil, highlight: nil, knowsHighlight: false)
            lost = nil
        }
        if let open { return stepInMenu(open) }
        switch random.pick([
            ("key-open", 16), ("click-open", 12), ("drag-open", 6), ("context", 12), ("suggest", 8),
            ("tab", 14), ("inline", 4), ("sync", 12), ("resize", 4), ("quiet", 6),
        ]) {
        case "key-open": return keyboardOpen()
        case "click-open": return pointerOpen(drag: false)
        case "drag-open": return pointerOpen(drag: true)
        case "context": return rightClick()
        case "suggest": return suggest()
        case "tab":
            return SessionStep(action: "tab", keys: Array(repeating: KeyEvent(key: .tab), count: random.within(1...3)))
        case "inline": return inline()
        case "sync": return sync()
        case "resize": return resize()
        default: return SessionStep(action: "quiet")
        }
    }

    /// A step with a menu open: walk it, choose from it, dismiss it, or change
    /// the model or the terminal under it.
    private func stepInMenu(_ menu: OpenMenu) -> SessionStep {
        // A menu that has gone from the screen is dismissed, as a person who
        // lost it would: nothing in it can be aimed at.
        if !shows(menu.kind) {
            lost = menu.kind
            close(restoringFocus: false)
            return SessionStep(action: "dismiss", keys: [KeyEvent(key: .escape)])
        }
        switch random.pick([
            ("down", 22), ("up", 10), ("end", 3), ("choose", 16), ("click-row", 10), ("escape", 10),
            ("click-away", 5), ("sync", 12), ("resize", 6), ("quiet", 6),
        ]) {
        case "down": return walk(KeyEvent(key: .down))
        case "up": return walk(KeyEvent(key: .up))
        case "end": return walk(KeyEvent(key: .end))
        case "choose": return chooseByKey()
        case "click-row": return clickRow()
        case "escape":
            close(restoringFocus: true)
            return SessionStep(action: "dismiss", keys: [KeyEvent(key: .escape)])
        case "click-away": return clickAway()
        case "sync": return sync()
        case "resize": return resize()
        default: return SessionStep(action: "quiet")
        }
    }

    /// Records that the open menu closed, and where the focus must then be.
    private func close(restoringFocus: Bool) {
        if restoringFocus, let focus = open?.focusBefore { focusAfterClose = (focus, stepIndex + 1) }
        // A frame with nothing done, for the focus to show where it went —
        // and for the next step to read it there, not where it was.
        pending.append { SessionStep(action: "settle") }
        open = nil
    }

    // MARK: Opening

    /// Opens whatever holds the focus with the keyboard: Return on a pop-up
    /// menu or the drop-down, Shift+F10 on a document — or, when nothing that
    /// opens a menu holds it, Tabs on.
    private func keyboardOpen() -> SessionStep {
        guard let focus = focusShown else { return SessionStep(action: "tab", keys: [KeyEvent(key: .tab)]) }
        let kind: OpenMenu.Kind
        var key = KeyEvent(key: .enter)
        switch focus {
        case "file": kind = .popUp("File")
        case "view": kind = .popUp("View")
        case "export": kind = .popUp("Export")
        case "help": kind = .popUp("Help")
        case "filter": kind = .picker
        case let row where row.hasPrefix("row "):
            guard let id = Int(row.dropFirst(4)) else { return SessionStep(action: "quiet") }
            kind = .context(id)
            key = KeyEvent(key: .f10, shift: true)
        case "tag": return suggestFromTheField(focused: true)
        default:
            return SessionStep(action: "tab", keys: [KeyEvent(key: .tab)])
        }
        // The keyboard highlights the first row; a drop-down, its choice.
        open = OpenMenu(kind: kind, focusBefore: focus, highlight: kind == .picker ? desk.filter : 0)
        return SessionStep(action: "key-open", keys: [key])
    }

    /// Opens a pop-up menu or the drop-down with a click on its label — a press
    /// and release together, which leaves it up — or with a press alone, whose
    /// release is dragged onto a row on the next step.
    private func pointerOpen(drag: Bool) -> SessionStep {
        let targets: [(label: String, kind: OpenMenu.Kind, focus: String)] = [
            ("File ▾", .popUp("File"), "file"), ("View ▾", .popUp("View"), "view"),
            ("Export ▾", .popUp("Export"), "export"), ("Help ▾", .popUp("Help"), "help"),
            (MenuDesk.filters[desk.filter], .picker, "filter"),
        ]
        let target = targets[random.below(targets.count)]
        guard let (x, y) = locate(target.label) else { return SessionStep(action: "quiet") }
        // The click focuses what it opens, so that is where the focus goes back
        // to. A drop-down the pointer opens highlights its choice, where a menu
        // highlights nothing — the owner's call, still open (see
        // `Documentation/Unifying the menu implementations.md`).
        let kind = target.kind
        open = OpenMenu(kind: kind, focusBefore: target.focus, highlight: kind == .picker ? desk.filter : nil)
        let press = MouseEvent(button: .left, phase: .pressed, x: x, y: y)
        guard !drag else {
            open?.awaitingRelease = true
            pending = [{ [weak self] in self?.dragRelease(pressedAt: (x, y)) ?? SessionStep(action: "quiet") }]
            return SessionStep(action: "press-open", mouse: [press])
        }
        return SessionStep(
            action: "click-open", mouse: [press, MouseEvent(button: .left, phase: .released, x: x, y: y)])
    }

    /// The rest of a press-and-drag: the pointer dragged onto a row and
    /// released there, which chooses it — or, when no row is on the screen
    /// but the one under the press, released where it was pressed: the tail
    /// of a click, which chooses nothing and leaves the menu up
    /// (`MouseEventDispatcher.endsPopupOpeningClick`). A menu too tall for the
    /// space around its trigger is drawn over it, so a row can be there.
    private func dragRelease(pressedAt press: (x: Int, y: Int)) -> SessionStep {
        guard let menu = open else { return SessionStep(action: "quiet") }
        open?.awaitingRelease = false
        let rows = selectableRows(menu.kind)
        let visible = rows.indices.filter { row in
            guard let at = Self.drawnRow(rows[row], on: screen) else { return false }
            return at.y != press.y
        }
        guard let row = visible.isEmpty ? nil : visible[random.below(visible.count)],
            let (x, y) = Self.drawnRow(rows[row], on: screen)
        else {
            return SessionStep(
                action: "release", mouse: [MouseEvent(button: .left, phase: .released, x: press.x, y: press.y)])
        }
        choose(row, of: menu)
        return SessionStep(
            action: "drag-choose",
            mouse: [
                MouseEvent(button: .left, phase: .dragged, x: x, y: y),
                MouseEvent(button: .left, phase: .released, x: x, y: y),
            ])
    }

    /// Opens a document's context menu with a right-click on its row — at its
    /// start, its middle or its number at the trailing edge.
    private func rightClick() -> SessionStep {
        let status = Self.statusLine(on: screen)
        let rows = screen.indices.compactMap { y -> (Int, Int, Int)? in
            guard screen[y] != status, let range = screen[y].range(of: #"#\d+\b"#, options: .regularExpression),
                let id = Int(screen[y][range].dropFirst()), desk.index(of: id) != nil
            else { return nil }
            return (y, id, screen[y].distance(from: screen[y].startIndex, to: range.lowerBound))
        }
        guard !rows.isEmpty else { return SessionStep(action: "quiet") }
        let (y, id, numberAt) = rows[random.below(rows.count)]
        // The row starts after the inline menu's box beside it, where there is one.
        let line = Array(screen[y])
        let box = line[..<numberAt].lastIndex { "│╯╰╮╭".contains($0) }
        let rowStart = box.map { $0 + 2 } ?? (line.firstIndex { $0 != " " } ?? 0)
        let x = [numberAt, rowStart, (rowStart + numberAt) / 2, numberAt + 1][random.below(4)]
        open = OpenMenu(kind: .context(id), focusBefore: focusShown, highlight: nil)
        return SessionStep(
            action: "context",
            mouse: [
                MouseEvent(button: .right, phase: .pressed, x: x, y: y),
                MouseEvent(button: .right, phase: .released, x: x, y: y),
            ])
    }

    /// Types into the tag field and opens its suggestions: the field focused
    /// with a click unless it holds the focus, cleared, a letter or two typed,
    /// and then Down at the caret or a click on its `▾`.
    private func suggest() -> SessionStep {
        suggestFromTheField(focused: focusShown == "tag")
    }

    private func suggestFromTheField(focused: Bool) -> SessionStep {
        guard let (x, y) = locate("▾▌") else { return SessionStep(action: "quiet") }
        let prefix = ["u", "l", "b", "un", "le", "bl"][random.below(6)]
        var keys = Array(repeating: KeyEvent(key: .backspace), count: desk.tag.count + 1)
        keys += prefix.map { KeyEvent(key: .character($0)) }
        let byClick = random.below(3) == 0
        pending = [
            { SessionStep(action: "type", keys: keys) },
            { [weak self] in
                guard let self else { return SessionStep(action: "quiet") }
                // Down comes into the menu at its first row; a click on the ▾
                // leaves the keyboard at the caret (`TextFieldHandler`).
                open = OpenMenu(kind: .suggestions, focusBefore: "tag", highlight: byClick ? nil : 0)
                guard byClick, let (x, y) = locate("▾▌") else {
                    open?.highlight = 0
                    return SessionStep(action: "suggest-open", keys: [KeyEvent(key: .down)])
                }
                return SessionStep(
                    action: "suggest-open",
                    mouse: [
                        MouseEvent(button: .left, phase: .pressed, x: x, y: y),
                        MouseEvent(button: .left, phase: .released, x: x, y: y),
                    ])
            },
        ]
        guard !focused else { return pending.removeFirst()() }
        return SessionStep(
            action: "focus-field",
            mouse: [
                MouseEvent(button: .left, phase: .pressed, x: max(0, x - 3), y: y),
                MouseEvent(button: .left, phase: .released, x: max(0, x - 3), y: y),
            ])
    }

    /// Runs a row of the inline menu: Return when it holds the focus, a click
    /// on one otherwise.
    private func inline() -> SessionStep {
        if focusShown == "jump" {
            expectedApplied += 1
            expectedLast = nil
            return SessionStep(action: "inline", keys: [KeyEvent(key: .enter)])
        }
        let label = random.below(2) == 0 ? "Jump First" : "Jump Last"
        guard let (x, y) = locate(label) else { return SessionStep(action: "quiet") }
        expectedApplied += 1
        expectedLast = label
        return SessionStep(
            action: "inline",
            mouse: [
                MouseEvent(button: .left, phase: .pressed, x: x + 1, y: y),
                MouseEvent(button: .left, phase: .released, x: x + 1, y: y),
            ])
    }

    // MARK: In a menu

    /// An arrow or a jump key, and where it moves the highlight
    /// (`MenuHighlight`): a drop-down wraps, everything else stops at the
    /// ends, and from nothing Down enters at the top and Up at the bottom.
    private func walk(_ key: KeyEvent) -> SessionStep {
        guard var menu = open else { return SessionStep(action: "quiet") }
        let count = selectableRows(menu.kind).count
        guard count > 0 else { return SessionStep(action: "quiet", keys: []) }
        let last = count - 1
        switch (key.key, menu.highlight) {
        case (.down, nil): menu.highlight = 0
        case (.up, nil), (.end, _): menu.highlight = last
        case (.down, let row?): menu.highlight = menu.kind == .picker ? (row + 1) % count : min(row + 1, last)
        case (.up, let row?): menu.highlight = menu.kind == .picker ? (row + count - 1) % count : max(row - 1, 0)
        default: break
        }
        open = menu
        return SessionStep(action: "walk", keys: [key])
    }

    /// Return: runs the highlighted row — or, in the suggestions with none
    /// highlighted, submits the field as typed.
    private func chooseByKey() -> SessionStep {
        guard let menu = open else { return SessionStep(action: "quiet") }
        let count = selectableRows(menu.kind).count
        if let row = menu.highlight, row < count {
            choose(row, of: menu)
        } else if menu.kind == .suggestions {
            expectedApplied += 1
            expectedLast = "Tag \(desk.tag)"
            close(restoringFocus: true)
        } else {
            return walk(KeyEvent(key: .down))
        }
        return SessionStep(action: "choose", keys: [KeyEvent(key: .enter)])
    }

    /// A click on a row drawn in the open menu, which runs it.
    private func clickRow() -> SessionStep {
        guard let menu = open else { return SessionStep(action: "quiet") }
        let rows = selectableRows(menu.kind)
        let visible = rows.indices.filter { Self.drawnRow(rows[$0], on: screen) != nil }
        guard !visible.isEmpty else { return walk(KeyEvent(key: .down)) }
        let row = visible[random.below(visible.count)]
        guard let (x, y) = Self.drawnRow(rows[row], on: screen) else { return SessionStep(action: "quiet") }
        choose(row, of: menu)
        return SessionStep(
            action: "click-row",
            mouse: [
                MouseEvent(button: .left, phase: .pressed, x: x, y: y),
                MouseEvent(button: .left, phase: .released, x: x, y: y),
            ])
    }

    /// Records what choosing `row` of `menu` must do.
    private func choose(_ row: Int, of menu: OpenMenu) {
        switch menu.kind {
        case .picker: expectedFilter = row
        default:
            expectedApplied += 1
            expectedLast = command(choosing: selectableRows(menu.kind)[row], in: menu.kind)
        }
        close(restoringFocus: true)
    }

    /// A click on the status line, well away from any menu, which dismisses
    /// the one that is open.
    private func clickAway() -> SessionStep {
        guard let status = Self.statusLine(on: screen), let y = screen.firstIndex(of: status) else {
            close(restoringFocus: true)
            return SessionStep(action: "dismiss", keys: [KeyEvent(key: .escape)])
        }
        close(restoringFocus: true)
        return SessionStep(
            action: "click-away",
            mouse: [
                MouseEvent(button: .left, phase: .pressed, x: 1, y: y),
                MouseEvent(button: .left, phase: .released, x: 1, y: y),
            ])
    }

    // MARK: Underneath

    /// A change from elsewhere: a document arrives, leaves, is renamed or
    /// promoted, or is reopened, which puts it among the File menu's recent
    /// items — while a menu may be up over it.
    private func sync() -> SessionStep {
        switch random.below(5) {
        case 0:
            desk.documents.insert(
                MenuDesk.Document(
                    id: desk.makeID(), name: Synth.sentence(random.next(), words: random.within(1...3)),
                    status: random.below(3)),
                at: random.below(desk.documents.count + 1))
        case 1:
            guard desk.documents.count > 4 else { break }
            let index = random.below(desk.documents.count)
            // Not the document whose menu is open: a menu whose row leaves goes
            // with it, which is not what this step is about.
            if case .context(let id)? = open?.kind, desk.documents[index].id == id { break }
            desk.recent.removeAll { $0 == desk.documents[index].id }
            desk.documents.remove(at: index)
        case 2:
            guard !desk.documents.isEmpty else { break }
            desk.documents[random.below(desk.documents.count)].name = Synth.sentence(
                random.next(), words: random.within(1...4))
        case 3:
            guard !desk.documents.isEmpty else { break }
            let index = random.below(desk.documents.count)
            desk.documents[index].status = (desk.documents[index].status + 1) % MenuDesk.statuses.count
        default:
            guard !desk.documents.isEmpty else { break }
            let id = desk.documents[random.below(desk.documents.count)].id
            desk.recent.removeAll { $0 == id }
            desk.recent.insert(id, at: 0)
            if desk.recent.count > 3 { desk.recent.removeLast() }
        }
        // A highlight whose row went moves to the row now in its place, or to
        // the last (`MenuHighlight.adopt(selectable:)`).
        if var menu = open, let row = menu.highlight {
            menu.highlight = min(row, selectableRows(menu.kind).count - 1)
            if menu.highlight == -1 { menu.highlight = nil }
            open = menu
        }
        return SessionStep(action: "sync")
    }

    private func resize() -> SessionStep {
        let (width, height) = Self.sizes[random.below(Self.sizes.count)]
        return SessionStep(action: "resize", resize: (width, height))
    }

    static let descriptor = SessionDescriptor(
        id: "menus",
        summary: "a document manager run from its menus, while documents change under them",
        exercises:
            "pop-up menus in the four corners, a picker drop-down, context menus, an inline menu and a combo "
            + "box's suggestions — opened by the keyboard, by a click and by a press dragged to a row; walked, "
            + "chosen from, dismissed; rows and a menu's own items changing while it is up; short and narrow "
            + "terminals; the focus handed back on close",
        make: { config, width, height, cold in
            DrivenSession(MenusSession(config: config), width: width, height: height, cold: cold)
        })
}
