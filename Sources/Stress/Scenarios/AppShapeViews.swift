//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AppShapeViews.swift
//
//  The applications themselves. See `AppShapes.swift` for why they exist.
//
//  Each is written the way an app is written — the whole API, in combination,
//  with the state an app keeps and the update pattern its real counterpart has
//  — rather than the narrowest tree that exercises one code path. That is the
//  point: the costs worth finding live in the combinations.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkit

// MARK: - File browser

/// A split view: folders on the left, a sortable table of files on the right,
/// a status line under it.
///
/// What it puts together: a `List` with a selection binding beside a `Table`
/// with a second one, a `sortOrder` binding the app applies (by decorating, as
/// `Table`'s own documentation now recommends), `.fit` and `.fixed` and
/// `.flexible` columns in one table, cells built by `Int.formatted(.byteCount)`
/// and `Date.formatted`, and a footer that aggregates the whole collection
/// every frame the way a status line does.
struct FileBrowserApp: View {
    /// Every folder's listing, synthesised ONCE when the scenario is built.
    ///
    /// A real browser reads a directory when you open it, not sixty times a
    /// second — and a fixture that re-synthesises 4,000 entries per frame
    /// measures `Date` and `String` construction rather than the table. (It did:
    /// 7.6 ms a frame, of which the table was a fraction.)
    let listings: [[FileEntry]]
    let seed: UInt64

    init(count: Int, seed: UInt64) {
        self.seed = seed
        self.listings = (0..<12).map { folder in
            (0..<count).map { FileEntry.sample($0 &+ folder &* count, seed: seed) }
        }
    }

    @State private var folder: Int? = 0
    @State private var selection: Int?
    @State private var order = [KeyPathComparator(\FileEntry.name)]

    private var folders: [String] { (0..<listings.count).map { Synth.slug(mix(seed, $0 &* 977)) } }

    var body: some View {
        // The folder decides the data, so switching folders replaces every row
        // — which is the shape a memo cannot serve and an app does constantly.
        let files = listings[min(folder ?? 0, listings.count - 1)]
        let sorted = Self.sorted(files, by: order)
        let total = files.reduce(0) { $0 + $1.bytes }
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.app-shapes.heading", "file-browser", files.count)).bold()
            NavigationSplitView {
                List(selection: $folder) {
                    ForEach(Array(folders.enumerated()), id: \.offset) { pair in
                        HStack(spacing: 1) {
                            Text("▸")
                            Text(pair.element)
                        }
                    }
                }
            } detail: {
                VStack(alignment: .leading, spacing: 0) {
                    Table(sorted, selection: $selection, sortOrder: $order) {
                        TableColumn("Name", value: \FileEntry.name).width(.fit)
                        TableColumn("Kind", value: \FileEntry.kind).width(.fixed(18))
                        TableColumn("Size", value: \FileEntry.bytes) { $0.size }
                            .width(.fixed(12)).alignment(.trailing)
                        TableColumn("Modified", value: \FileEntry.stamp).width(.fixed(22))
                    }
                    Divider()
                    HStack(spacing: 2) {
                        Text("\(files.count) items")
                        Text(total.formatted(.byteCount(style: .file)))
                        Spacer()
                        // In a LEAF, deliberately: an `@Observable` read
                        // invalidates the view whose body took it and
                        // everything below, so a clock read up here would
                        // throw away the table's caches every tick and the
                        // scenario would measure the invalidation. The shell's
                        // own footer carries the same note.
                        TickStamp()
                    }
                }
            }
        }
    }

    /// Decorate, sort, undecorate — one key read per row instead of O(n log n)
    /// comparator calls. See `Table`'s `sortOrder` documentation.
    private static func sorted(
        _ files: [FileEntry], by order: [KeyPathComparator<FileEntry>]
    ) -> [FileEntry] {
        let ascending = order.first?.order != .reverse
        switch order.first?.keyPath {
        case \FileEntry.bytes:
            return files.map { ($0.bytes, $0) }
                .sorted { ascending ? $0.0 < $1.0 : $0.0 > $1.0 }.map(\.1)
        case \FileEntry.stamp:
            return files.map { ($0.modified, $0) }
                .sorted { ascending ? $0.0 < $1.0 : $0.0 > $1.0 }.map(\.1)
        default:
            return files.map { ($0.name, $0) }
                .sorted { ascending ? $0.0 < $1.0 : $0.0 > $1.0 }.map(\.1)
        }
    }
}

// MARK: - Log viewer

/// A log tailing into a list: new lines arrive at the bottom, the view follows
/// them, a filter is applied on every snapshot, and each line is coloured by
/// its level and wrapped to the width.
///
/// The combination that matters: a bottom-anchored `ScrollView` (so the window
/// walks from the END), variable-height rows (the messages wrap), a per-frame
/// `filter` over the whole buffer the way a search field drives one, and
/// per-row `.foregroundStyle` from data rather than from a constant.
struct LogViewerApp: View {
    let window: Int
    let seed: UInt64

    @State private var filter = ""
    @State private var showsDebug = true
    @Environment(StressClock.self) private var clock

    var body: some View {
        let tick = clock.tick
        // A rolling buffer: the newest line is `tick + window`, the oldest
        // scrolls out of memory entirely, which is what a log viewer with a
        // cap does.
        let lines = (0..<window).map { LogLine.sample(tick &+ $0, seed: seed) }
        let shown = lines.filter { line in
            (showsDebug || line.level != .debug)
                && (filter.isEmpty || line.message.contains(filter))
        }
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.app-shapes.heading", "log-viewer", shown.count)).bold()
            HStack(spacing: 2) {
                TextField("filter", text: $filter)
                Toggle("debug", isOn: $showsDebug)
            }
            Divider()
            ScrollView {
                // LAZY, which is what makes the window O(visible). The eager
                // spelling is a variant of its own (`chat-eager`) because the
                // difference is two orders of magnitude and an app reaches for
                // the wrong one first.
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(shown) { line in
                        HStack(alignment: .top, spacing: 1) {
                            Text(String(format: "%7d", line.id)).dim()
                            Text(line.level.label).foregroundStyle(line.level.colour)
                            Text(line.source).foregroundStyle(.blue)
                            Text(line.message)
                        }
                    }
                }
            }
            .defaultScrollAnchor(.bottom)
        }
    }
}

// MARK: - Process monitor

/// `top`: four hundred processes whose every number moves, re-sorted by CPU on
/// every frame, with a multi-selection and an aggregate header.
///
/// The hardest shape in the corpus for anything that keeps rows across frames —
/// nothing is equal to what it was, and the ORDER changes too, so a row is not
/// even where it was. That is exactly what makes it worth measuring beside the
/// scenarios where a memo works.
struct ProcessMonitorApp: View {
    let count: Int
    let seed: UInt64

    @State private var selection: Set<Int> = []
    @State private var order = [KeyPathComparator(\ProcSample.cpu, order: .reverse)]
    @Environment(StressClock.self) private var clock

    var body: some View {
        let tick = clock.tick
        let samples = (0..<count).map { ProcSample.sample($0, tick: tick, seed: seed) }
        let sorted = samples.map { ($0.cpu, $0) }
            .sorted { $0.0 > $1.0 }.map(\.1)
        let load = samples.reduce(0.0) { $0 + $1.cpu } / Double(max(1, count))
        let resident = samples.reduce(0) { $0 + $1.resident }
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.app-shapes.heading", "process-monitor", count)).bold()
            HStack(spacing: 2) {
                Text("load \(String(format: "%.1f", load))%")
                ProgressView(value: load, total: 100)
                Text(resident.formatted(.byteCount(style: .memory)))
            }
            Divider()
            Table(sorted, selection: $selection, sortOrder: $order) {
                TableColumn("PID", value: \ProcSample.id) { "\($0.id)" }
                    .width(.fixed(6)).alignment(.trailing)
                TableColumn("Command", value: \ProcSample.command)
                TableColumn("User", value: \ProcSample.user).width(.fixed(10))
                TableColumn("CPU%", value: \ProcSample.cpu) { $0.cpuText }
                    .width(.fixed(7)).alignment(.trailing)
                TableColumn("", value: \ProcSample.bar).width(.fixed(12))
                TableColumn("Memory", value: \ProcSample.resident) { $0.memory }
                    .width(.fixed(11)).alignment(.trailing)
                TableColumn("Thr", value: \ProcSample.threads) { "\($0.threads)" }
                    .width(.fixed(4)).alignment(.trailing)
                TableColumn("State", value: \ProcSample.state).width(.fixed(9))
            }
        }
    }
}

// MARK: - Mail client

/// Three columns: mailboxes with unread badges, a message list whose rows are
/// three lines each, and a reading pane of wrapped text.
///
/// A multi-line row built from a `VStack` of `Text` — which is how an app
/// writes one, and a different cost entirely from a `Table` with a
/// `lineLimit` — beside a detail pane that re-wraps a paragraph on every frame.
struct MailClientApp: View {
    /// Fetched once, like a mailbox. See ``FileBrowserApp/listings``.
    let messages: [MailMessage]
    let seed: UInt64

    init(count: Int, seed: UInt64) {
        self.seed = seed
        self.messages = (0..<count).map { MailMessage.sample($0, seed: seed) }
    }

    @State private var mailbox: Int? = 0
    @State private var message: Int? = 3
    @Environment(StressClock.self) private var clock

    var body: some View {
        let unread = messages.count { $0.unread }
        let open = messages.first { $0.id == (message ?? 0) }
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.app-shapes.heading", "mail-client", messages.count)).bold()
            NavigationSplitView {
                List(selection: $mailbox) {
                    ForEach(Array(["Inbox", "Sent", "Drafts", "Archive", "Junk"].enumerated()),
                        id: \.offset)
                    { pair in
                        Text(pair.element).badge(pair.offset == 0 ? unread : 0)
                    }
                }
            } content: {
                List(selection: $message) {
                    ForEach(messages) { item in
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 1) {
                                Text(item.unread ? "●" : " ").foregroundStyle(.blue)
                                Text(item.sender).bold()
                                Spacer()
                                Text(item.received).dim()
                            }
                            Text(item.subject)
                            Text(item.preview).dim().lineLimit(1)
                        }
                    }
                }
            } detail: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(open?.subject ?? "").bold()
                        Text(open?.sender ?? "").dim()
                        Divider()
                        // Re-wrapped every frame, which is what a reading pane
                        // does while the window is being resized.
                        ForEach(0..<24, id: \.self) { paragraph in
                            Text(Synth.sentence(mix(seed, paragraph &+ clock.tick / 32), words: 60))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Settings form

/// A form of live controls — the shape that registers the most focus handlers
/// per frame of anything in the catalogue.
///
/// Every control is bound to `@State` and every one registers with the focus
/// system on every frame. Sixty of them is an ordinary preferences window, and
/// nothing else in the corpus measures the per-frame cost of the focus ring at
/// that size.
struct SettingsFormApp: View {
    let groups: Int

    @State private var toggles: [Bool] = Array(repeating: true, count: 64)
    @State private var sliders: [Double] = (0..<64).map { Double($0 % 10) / 10 }
    @State private var steppers: [Int] = Array(repeating: 3, count: 64)
    @State private var names: [String] = (0..<64).map { "value-\($0)" }
    @State private var choices: [Int] = Array(repeating: 1, count: 64)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.app-shapes.heading", "settings-form", groups &* 5)).bold()
            ScrollView {
                Form {
                    ForEach(0..<groups, id: \.self) { group in
                        Section(Synth.slug(mix(0x5EED, group)).capitalizedFirst) {
                            // A `Binding` into an array element, built fresh
                            // for every control on every frame — how a form
                            // over a collection of settings is written, and
                            // five closures per group that nothing can memoise.
                            Toggle("enabled", isOn: $toggles[group])
                            Slider("threshold", value: $sliders[group], in: 0...1)
                            Stepper("retries", value: $steppers[group], in: 0...9)
                            TextField("label", text: $names[group])
                            Picker("mode", selection: $choices[group]) {
                                Text("off").tag(0)
                                Text("auto").tag(1)
                                Text("always").tag(2)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Code editor

/// Two thousand syntax-coloured lines with a line-number gutter, scrollable on
/// both axes.
///
/// The SGR-heaviest scenario there is: every line carries four or five colour
/// runs, so every drawn line is a clip the byte-wise fast path must decline,
/// and the horizontal scroll means the clip is taken from the MIDDLE of the
/// line rather than its start.
struct CodeEditorApp: View {
    let lines: Int
    let seed: UInt64
    /// Whether the document GROWS — a build log, a test run, a `tail -f` in an
    /// editor pane. A variant of its own because it is the only shape that
    /// makes the two-axis width walk miss: the collection's identity changes
    /// every tick, so everything keyed on the rows' DATA — the width over all
    /// rows above all (`StackContentWidth.swift`) — is re-derived rather than
    /// served. A settled document is the easy case and was the only one
    /// measured until 2026-09-22.
    var tailing = false

    @Environment(StressClock.self) private var clock

    var body: some View {
        // Read in the BODY on purpose here, unlike the settled editor below:
        // an arriving line genuinely rebuilds the document, and a per-row leaf
        // would be measuring the observer count instead (see the comment in the
        // row). `lines` is the floor so the two variants start the same size.
        let count = tailing ? lines + Int(clock.tick % 512) : lines
        return VStack(alignment: .leading, spacing: 0) {
            Text(
                Lf(
                    "stress.scenario.app-shapes.heading",
                    tailing ? "code-editor-tailing" : "code-editor", count)
            ).bold()
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<count, id: \.self) { index in
                        // The caret does NOT read the clock, and neither does
                        // anything else here. Both spellings were measured and
                        // both are wrong for this scenario: reading the tick in
                        // the editor's body invalidates every row's memo on
                        // every frame, and reading it in a per-row leaf — the
                        // discipline the file browser's footer follows — gives
                        // the clock two thousand observers instead of one and
                        // costs 3.5× more again (32.8 → 114.9 ms). A leaf is
                        // the right place for a reader only when there is ONE
                        // of it. This scenario is here to measure the two-axis
                        // render, so its caret sits still.
                        HStack(spacing: 1) {
                            Text(String(format: "%5d", index + 1))
                                .foregroundStyle(index == count / 2 ? .orange : .gray)
                            Text(Self.source(index, seed: seed))
                        }
                    }
                }
            }
        }
    }

    /// A line of pseudo-source with real SGR in it: keyword, type, string and
    /// comment runs, as a highlighter emits them.
    private static func source(_ index: Int, seed: UInt64) -> String {
        let h = mix(seed, index)
        let indent = String(repeating: " ", count: Int(h % 4) * 4)
        let keyword = ["let", "var", "func", "guard", "return", "if"][Int(h % 6)]
        return indent
            + "\u{1B}[35m\(keyword)\u{1B}[0m \(Synth.slug(h >> 4)): "
            + "\u{1B}[36m\(Synth.nouns[Int((h >> 12) % UInt64(Synth.nouns.count))].capitalizedFirst)\u{1B}[0m = "
            + "\u{1B}[32m\"\(Synth.sentence(h >> 20, words: 4))\"\u{1B}[0m"
            + (h.isMultiple(of: 5) ? "  \u{1B}[90m// \(Synth.sentence(h >> 32, words: 8))\u{1B}[0m" : "")
    }
}

// MARK: - Chat

/// Bottom-anchored bubbles of wildly different heights, alternating sides.
///
/// Every row is a different height and the view is pinned to the end, so the
/// window walks backwards from the last row — the anchored-window path, over
/// content whose heights are not uniform and are not known without wrapping.
struct ChatApp: View {
    /// The whole conversation, written once. The tick moves a WINDOW through
    /// it, which is what a chat scrolling under new messages does — and what
    /// re-synthesising 1,500 sentences a frame was measuring instead.
    let history: [ChatMessage]
    let count: Int
    let seed: UInt64
    /// Whether the bubbles sit in a `VStack` rather than a `LazyVStack` — the
    /// spelling an app reaches for first, which renders EVERY message on every
    /// frame however few are on screen. A variant of its own because the
    /// difference is two orders of magnitude and it is invisible in the source.
    var eager = false

    init(count: Int, seed: UInt64, eager: Bool = false) {
        self.count = count
        self.seed = seed
        self.eager = eager
        self.history = (0..<(count * 2)).map { ChatMessage.sample($0, seed: seed) }
    }

    @State private var draft = ""
    @Environment(StressClock.self) private var clock

    var body: some View {
        let start = clock.tick % max(1, history.count - count)
        let messages = Array(history[start..<(start + count)])
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.app-shapes.heading", eager ? "chat-eager" : "chat", count))
                .bold()
            ScrollView {
                AnyLayoutStack(eager: eager, alignment: .leading, spacing: 0) {
                    ForEach(messages) { message in
                        HStack(spacing: 0) {
                            if message.mine { Spacer() }
                            VStack(alignment: message.mine ? .trailing : .leading, spacing: 0) {
                                Text(message.author).dim()
                                Text(message.body)
                            }
                            .padding(.horizontal, 1)
                            .border()
                            if !message.mine { Spacer() }
                        }
                    }
                }
            }
            .defaultScrollAnchor(.bottom)
            TextField("message", text: $draft)
        }
    }
}

// MARK: - Shared pieces

/// A leaf that reads the clock, so a tick invalidates a line rather than a page.
private struct TickStamp: View {
    @Environment(StressClock.self) private var clock
    var body: some View { Text(clock.tick.formatted()).dim() }
}

/// A `VStack` or a `LazyVStack`, chosen at runtime.
///
/// One type so a variant can be the SAME application in both spellings: the
/// difference between them is the whole point of the pair, and a second copy of
/// the view would let something else drift between them.
private struct AnyLayoutStack<Content: View>: View {
    let eager: Bool
    let alignment: HorizontalAlignment
    let spacing: Int
    @ViewBuilder let content: Content

    init(
        eager: Bool, alignment: HorizontalAlignment, spacing: Int,
        @ViewBuilder content: () -> Content
    ) {
        self.eager = eager
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if eager {
            VStack(alignment: alignment, spacing: spacing) { content }
        } else {
            LazyVStack(alignment: alignment, spacing: spacing) { content }
        }
    }
}
