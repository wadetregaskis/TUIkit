//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AppShapes.swift
//
//  Whole applications, as scenarios — the shapes people actually build.
//
//  The catalogue measures PARTS: a list, a table, a stack, a gradient, a menu.
//  That is the right unit for isolating a cost, and it is the wrong unit for
//  finding one, because nothing in it puts a sorted table beside a filtered
//  list beside a wrapped detail pane inside a split view and asks what the
//  frame costs. Every interaction discovered this month lived in a combination:
//  a `.fit` column with churning data, a wrapped table under the estimator's
//  row limit, three passes over the same rows.
//
//  So these are applications. A file browser, a log viewer, a process monitor,
//  a mail client, a settings form, a code editor, a chat window — each built
//  the way an app is built, out of the whole API rather than the corner a
//  fixture needs, and each updating the way its real counterpart updates.
//
//      Stress --variants
//      Stress --bench --scenario app-shapes --variant process-monitor
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkit

// MARK: - The data an app has

/// A file, as a file browser has one.
struct FileEntry: Identifiable, Sendable, Equatable {
    let id: Int
    let name: String
    let kind: String
    let bytes: Int
    let modified: Date
    let isDirectory: Bool

    var size: String {
        isDirectory ? "—" : bytes.formatted(.byteCount(style: .file))
    }
    var stamp: String { modified.formatted(date: .abbreviated, time: .shortened) }

    static func sample(_ index: Int, seed: UInt64) -> Self {
        let h = mix(seed, index)
        let directory = h.isMultiple(of: 7)
        let stem = Synth.slug(h)
        let extensions = ["swift", "md", "json", "png", "log", "txt", "yaml"]
        let ext = extensions[Int((h >> 12) % UInt64(extensions.count))]
        return Self(
            id: index,
            name: directory ? stem : "\(stem).\(ext)",
            kind: directory ? "Folder" : ext.uppercased() + " document",
            bytes: Int(h % 40_000_000),
            modified: Date(timeIntervalSince1970: 1_600_000_000 + Double(h % 63_000_000)),
            isDirectory: directory)
    }
}

/// One log line. Levels are weighted the way a real log's are — mostly info,
/// occasionally an error — because a level-coloured row and a plain one do not
/// cost the same and a fixture at 1:1 would price neither.
struct LogLine: Identifiable, Sendable, Equatable {
    let id: Int
    let level: Level
    let source: String
    let message: String

    enum Level: Sendable, Equatable {
        case debug, info, warning, error

        var label: String {
            switch self {
            case .debug: "DEBUG"
            case .info: "INFO "
            case .warning: "WARN "
            case .error: "ERROR"
            }
        }
        var colour: Color {
            switch self {
            case .debug: .gray
            case .info: .cyan
            case .warning: .yellow
            case .error: .red
            }
        }
    }

    static func sample(_ sequence: Int, seed: UInt64) -> Self {
        let h = mix(seed, sequence)
        let level: Level =
            switch h % 20 {
            case 0: .error
            case 1, 2: .warning
            case 3...6: .debug
            default: .info
            }
        return Self(
            id: sequence,
            level: level,
            source: Synth.slug(h >> 8),
            message: Synth.sentence(h >> 16, words: 6 + Int(h % 14)))
    }
}

/// A process, as `top` has one: everything about it moves every tick.
struct ProcSample: Identifiable, Sendable, Equatable {
    let id: Int
    let command: String
    let user: String
    let cpu: Double
    let resident: Int
    let threads: Int
    let state: String

    var cpuText: String { String(format: "%.1f", cpu) }
    var memory: String { resident.formatted(.byteCount(style: .memory)) }
    var bar: String { Synth.bar(cpu / 100, width: 12) }

    static func sample(_ index: Int, tick: Int, seed: UInt64) -> Self {
        let fixed = mix(seed, index)
        // The command and the user are the process's identity and do not move;
        // the numbers do, every tick, which is what makes a sorted monitor
        // re-order under the cursor.
        let moving = mix(fixed, tick / 4 + index)
        return Self(
            id: index,
            command: "\(Synth.slug(fixed))\(fixed.isMultiple(of: 3) ? "d" : "")",
            user: Synth.firstNames[Int((fixed >> 20) % UInt64(Synth.firstNames.count))].lowercased(),
            cpu: Double(moving % 1_000) / 10,
            resident: Int(moving % 2_000_000_000),
            threads: Int(moving % 64) + 1,
            state: ["running", "sleeping", "stuck", "idle"][Int((moving >> 8) % 4)])
    }
}

/// A message in a mailbox.
struct MailMessage: Identifiable, Sendable, Equatable {
    let id: Int
    let sender: String
    let subject: String
    let preview: String
    let unread: Bool
    let received: String

    static func sample(_ index: Int, seed: UInt64) -> Self {
        let h = mix(seed, index)
        return Self(
            id: index,
            sender: Synth.name(h),
            subject: Synth.sentence(h >> 8, words: 4).capitalizedFirst,
            preview: Synth.sentence(h >> 24, words: 18),
            unread: h.isMultiple(of: 5),
            received: ["09:14", "Yesterday", "Mon", "12 Aug", "3 Jul"][Int((h >> 16) % 5)])
    }
}

/// A chat message, which is a bubble of variable height on one side or the
/// other.
struct ChatMessage: Identifiable, Sendable, Equatable {
    let id: Int
    let author: String
    let body: String
    let mine: Bool

    static func sample(_ index: Int, seed: UInt64) -> Self {
        let h = mix(seed, index)
        return Self(
            id: index,
            author: Synth.name(h),
            body: Synth.sentence(h >> 8, words: 3 + Int(h % 30)),
            mine: h.isMultiple(of: 3))
    }
}

extension String {
    /// First letter upper-cased, for a subject line. Not `capitalized`, which
    /// would upper-case every word.
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

// MARK: - The matrix

@MainActor
enum AppShapeMatrix {
    static let scenarioID = "app-shapes"

    static let descriptor = Scenario(
        id: scenarioID,
        title: "Application Shapes",
        blurb: "Whole applications — file browser, log viewer, process monitor, mail, form, editor, chat.",
        stresses: "the full API in combination · split views · live sorted tables · wrapped detail panes · forms of controls",
        make: { config in
            ScenarioVariants.resolve(config, in: scenarioID)?.make(config)
                ?? AnyView(Text(Lf("stress.scenario.app-shapes.heading", "?", 0)))
        }
    )

    private static func variant(
        _ id: String, _ summary: String, _ make: @escaping @MainActor (StressConfig) -> AnyView
    ) -> ScenarioVariant {
        ScenarioVariant(id: id, summary: summary, axis: "app", make: make)
    }

    static let variants: [ScenarioVariant] = [
        variant("file-browser", "split view: folder list + sortable file table with formatted sizes and dates") {
            AnyView(FileBrowserApp(count: $0.sized(4_000), seed: $0.seed))
        },
        variant("log-viewer", "a tailing, level-coloured, filtered log with wrapped messages") {
            AnyView(LogViewerApp(window: $0.sized(2_000), seed: $0.seed))
        },
        variant("process-monitor", "top: every number moves, re-sorted every frame, multi-selected") {
            AnyView(ProcessMonitorApp(count: $0.sized(400), seed: $0.seed))
        },
        variant("mail-client", "three columns: mailboxes, multi-line message rows with badges, a wrapped reading pane") {
            AnyView(MailClientApp(count: $0.sized(2_000), seed: $0.seed))
        },
        variant("settings-form", "a form of 60 live controls — toggles, sliders, steppers, pickers, fields") {
            AnyView(SettingsFormApp(groups: $0.sized(12)))
        },
        variant("code-editor", "2,000 syntax-coloured lines, a gutter, and both scroll axes") {
            AnyView(CodeEditorApp(lines: $0.sized(2_000), seed: $0.seed))
        },
        variant("code-editor-tailing", "the same editor with a GROWING document — the shape that makes every data-keyed memo miss") {
            AnyView(CodeEditorApp(lines: $0.sized(2_000), seed: $0.seed, tailing: true))
        },
        variant("chat", "bottom-anchored variable-height bubbles, alternating alignment, a live composer") {
            AnyView(ChatApp(count: $0.sized(1_500), seed: $0.seed))
        },
        variant("chat-eager", "the same chat in a plain VStack — every message rendered, every frame") {
            AnyView(ChatApp(count: $0.sized(1_500), seed: $0.seed, eager: true))
        },
        variant("sidebar", "a source list: a hand-written row above 300 looped rows, each tagged with the app's enum") {
            AnyView(ProjectSidebarApp(count: $0.sized(300), seed: $0.seed, tagged: true))
        },
        variant("sidebar-untagged", "the same source list answering by the projects' ids — no row built to read a tag") {
            AnyView(ProjectSidebarApp(count: $0.sized(300), seed: $0.seed, tagged: false))
        },
        variant("grouped-feed", "40 sections, each a heading over its own lazy stack of ~300 one- and two-line entries; the page moves every tick") {
            AnyView(GroupedFeedApp(sections: $0.sized(40), entries: 300, seed: $0.seed, mixedHeights: true))
        },
        variant("grouped-feed-uniform", "the same feed with one-line entries — nested stacks a sixteen-row sample already prices exactly") {
            AnyView(GroupedFeedApp(sections: $0.sized(40), entries: 300, seed: $0.seed, mixedHeights: false))
        },
        variant("headed-log", "a header over a lazy stack of 2,000 one- and two-line entries in one scroll view; the page moves every tick") {
            AnyView(HeadedLogApp(entries: $0.sized(2_000), seed: $0.seed))
        },
    ]
}
