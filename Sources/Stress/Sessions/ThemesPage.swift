//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ThemesPage.swift
//
//  The `themes` session's page and model: a small task manager whose every
//  kind of control shows its focus, its selection and its face, so that a
//  palette, a colour depth or a tint switched under it has something to be
//  wrong about.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import TUIkit

// MARK: - The board

/// Tasks, the form editing one, and the look the session puts on the page.
@Observable
@MainActor
final class ThemeBoard {
    struct Task: Identifiable, Equatable {
        let id: Int
        var title: String
        var owner: String
        var hours: Int
    }

    static let priorities = ["low", "normal", "high", "urgent"]

    var tasks: [Task]
    var selection: Int?
    var tableSelection: Set<Int> = []
    var title = ""
    var pinned = false
    var priority = 1
    var saves = 0
    /// The palette the form is drawn in instead of the app's, or `nil` for the
    /// app's: an environment write the render loop's own palette check never
    /// sees.
    var formPalette: (any Palette)?
    /// The palette the table is drawn in, or `nil` for the app's.
    var tablePalette: (any Palette)?
    /// The tint over the band of tinted controls.
    var tint: Color?

    init(tasks: [Task]) {
        self.tasks = tasks
    }
}

/// Where the focus is, as the page's `@FocusState` reads it.
enum ThemeFocus: Hashable {
    case list, title, pinned, priority, save, more, table, tinted

    var name: String {
        switch self {
        case .list: "list"
        case .title: "title"
        case .pinned: "pinned"
        case .priority: "priority"
        case .save: "save"
        case .more: "more"
        case .table: "table"
        case .tinted: "tinted"
        }
    }
}

// MARK: - The custom palette

/// A palette of the session's own, stated in full: a light page in a blue
/// ink with a teal accent, nothing like any palette TUIkit ships, so a colour
/// of it left on the screen after a switch is unmistakable.
struct HarbourPalette: Palette {
    let id = "stress-harbour"
    let name = "Harbour"
    let background = Color.rgb(236, 242, 246)
    let appHeaderBackground = Color.rgb(206, 222, 232)
    let foreground = Color.rgb(18, 44, 78)
    let foregroundSecondary = Color.rgb(52, 82, 112)
    let foregroundTertiary = Color.rgb(92, 112, 132)
    let accent = Color.rgb(0, 128, 128)
    let success = Color.rgb(24, 128, 60)
    let warning = Color.rgb(160, 104, 0)
    let error = Color.rgb(180, 36, 48)
    let info = Color.rgb(28, 92, 170)
    let border = Color.rgb(120, 146, 168)
}

// MARK: - The page

/// A header naming the app's palette; a list of tasks beside a form editing
/// the selected one — the form in a palette of its own, on its own page, with
/// a field, a toggle, a drop-down, a button and a disabled one and a menu; a
/// table of the same tasks in another palette; a band of controls under a
/// tint; a line drawn translucent; and a status line saying where the focus is.
///
/// The form and the table are ALWAYS given a palette, the app's own where the
/// session chose none, rather than one in a branch of an `if`: the branches are
/// two identities, and switching between them made every control in the form
/// a new one, the focused field included, and sent the focus to the first
/// focus stop. The list is given none, so it is drawn in the app's palette —
/// where the `t` key's cycling reaches it, and where the row promises are
/// judged.
struct ThemesPage: View {
    let board: ThemeBoard
    @FocusState private var focus: ThemeFocus?
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 2) {
                List(selection: Binding(get: { board.selection }, set: { board.selection = $0 })) {
                    ForEach(board.tasks) { task in ThemeTaskRow(task: task) }
                }
                .focused($focus, equals: .list)
                .frame(width: 40, height: 10)
                form
            }
            tableBand
            tintedBand
            Text(verbatim: "a translucent line under the rest").opacity(0.6)
            Spacer(minLength: 0)
            Text(verbatim: "[\(focus?.name ?? "none")] \(board.saves) saved").lineLimit(1)
        }
        .appHeader { Text(verbatim: "Themes · \(palette.name)") }
        .statusBarSystemItems(theme: true)
    }

    /// The form, on a page of its own palette: a palette in the environment
    /// changes what the views below it draw with, not what is behind them —
    /// as a colour scheme does in SwiftUI — so the form paints its own.
    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            ThemeLookLine()
            TextField("Title", text: Binding(get: { board.title }, set: { board.title = $0 }))
                .focused($focus, equals: .title)
                .frame(width: 30)
            Toggle("Pinned", isOn: Binding(get: { board.pinned }, set: { board.pinned = $0 }))
                .focused($focus, equals: .pinned)
            Picker("Priority", selection: Binding(get: { board.priority }, set: { board.priority = $0 })) {
                ForEach(ThemeBoard.priorities.indices, id: \.self) { Text(verbatim: ThemeBoard.priorities[$0]).tag($0) }
            }
            .pickerStyle(.menu)
            .focused($focus, equals: .priority)
            HStack(spacing: 1) {
                Button("Save") { board.saves += 1 }
                    .focused($focus, equals: .save)
                Button("Revert") {}
                    .disabled(true)
                Menu("More") {
                    Button("Duplicate") { board.saves += 1 }
                    Button("Archive") { board.saves += 1 }
                }
                .focused($focus, equals: .more)
            }
        }
        .background(Color.palette.background)
        .palette(board.formPalette ?? palette)
    }

    private var tableBand: some View {
        let table = Table(
            board.tasks,
            selection: Binding(get: { board.tableSelection }, set: { board.tableSelection = $0 })
        ) {
            TableColumn("Task", value: \ThemeBoard.Task.title)
            TableColumn("Owner", value: \ThemeBoard.Task.owner).width(.fit)
            TableColumn("Hours") { "\($0.hours)h" }.width(.fixed(6)).alignment(.trailing)
        }
        .focused($focus, equals: .table)
        .frame(height: 8)
        return table.palette(board.tablePalette ?? palette)
    }

    private var tintedBand: some View {
        HStack(spacing: 1) {
            Button("Tinted") { board.saves += 1 }
                .focused($focus, equals: .tinted)
            Toggle("Tinted toggle", isOn: Binding(get: { board.pinned }, set: { board.pinned = $0 }))
        }
        .tint(board.tint)
    }
}

/// What the page is drawn in, as it reads it: the palette's name and whether
/// it is light or dark — what `\.colorScheme` answers from the palette.
private struct ThemeLookLine: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(verbatim: "look: \(palette.name) · \(colorScheme == .dark ? "dark" : "light")")
    }
}

/// A task: its title, owner and number — in the row's own ink, as the
/// contrast floors TUIkit promises assume.
private struct ThemeTaskRow: View {
    let task: ThemeBoard.Task

    var body: some View {
        HStack(spacing: 1) {
            Text(verbatim: task.title)
            Spacer()
            Text(verbatim: "#\(task.id)")
        }
    }
}

extension ThemeTaskRow: @MainActor Equatable {}
