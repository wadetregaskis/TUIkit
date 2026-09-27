//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LogVariants.swift
//
//  The log, two more ways: its top line bound through `@Bindable`, and its
//  rows carrying a tap handler that captures the whole log. The same script
//  plays against the same data as `log`, so each reads against `log`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// MARK: - The variants

/// How the log's page differs from `log`'s.
enum LogVariant: String, CaseIterable {
    /// `.scrollPosition(id:)` bound through `@Bindable` to the model, as an
    /// app binds an `@Observable`'s property.
    case observable = "log-observable"
    /// Every row carries a tap handler that captures the list it was drawn
    /// in — the parent's growing `let lines`, through `self` — as an app's
    /// row action reaching for its siblings does.
    ///
    /// Today a write above the rows draws every row again, and the handlers
    /// each frame records replace the last frame's, so one copy of the list
    /// is alive at a time. A memo that serves a row instead keeps the handler
    /// the row recorded when it was drawn, and the list as it was then: one
    /// copy per drawn row, each as long as the log was. That is the memory
    /// this session is here to price.
    case captures = "log-captures"

    /// What the variant does to the log, for `--sessions`.
    var summary: String {
        switch self {
        case .observable: "its top line bound through @Bindable"
        case .captures: "its rows' tap handlers capturing the parent's growing list"
        }
    }
}

/// The log's page with rows whose handlers capture the whole list.
struct CapturingLogPage: View {
    let log: LogModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "\(log.lines.count) lines · top \(log.topLine.map(String.init) ?? "-")")
            ScrollView {
                CapturingLogRows(log: log, lines: log.lines)
            }
            .defaultScrollAnchor(.bottom)
            .scrollPosition(id: Binding(get: { log.topLine }, set: { log.topLine = $0 }))
        }
    }
}

/// The rows, built by a view that holds the list as a `let`, so a handler
/// that reads it captures `self` and with it the list as it was this frame.
private struct CapturingLogRows: View {
    let log: LogModel
    let lines: [LogModel.Line]

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(lines) { line in
                CapturingLogRow(line: line) { log.topLine = lines.firstIndex { $0.id == line.id } }
            }
        }
    }
}

/// A log line with a tap handler. Its `==` compares the line and leaves the
/// handler out, as an app's row does when its action cannot be compared.
private struct CapturingLogRow: View {
    let line: LogModel.Line
    let onTap: () -> Void

    var body: some View {
        LogRow(line: line).onTapGesture(count: 1, perform: onTap)
    }
}

extension CapturingLogRow: @MainActor Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.line == rhs.line }
}

/// Either variant's page.
struct LogVariantPage: View {
    let log: LogModel
    let variant: LogVariant

    var body: some View {
        switch variant {
        case .observable: LogPage(log: log, bindsThroughBindable: true)
        case .captures: CapturingLogPage(log: log)
        }
    }
}

// MARK: - The script

/// `log`'s script and checks, against the variant's page.
@MainActor
final class LogVariantSession: StressSession {
    private let log: LogSession
    private let variant: LogVariant

    init(config: StressConfig, variant: LogVariant) {
        self.variant = variant
        log = LogSession(config: config)
    }

    var page: LogVariantPage { LogVariantPage(log: log.log, variant: variant) }

    func step(_ index: Int) -> SessionStep { log.step(index) }

    func check(_ screen: [String], after index: Int) -> String? { log.check(screen, after: index) }

    static func descriptor(_ variant: LogVariant) -> SessionDescriptor {
        SessionDescriptor(
            id: variant.rawValue,
            summary: "the log, \(variant.summary)",
            exercises: "log's script against log's data: a bottom-anchored lazy stack growing under the "
                + "viewport, " + (variant == .observable
                    ? "scrollPosition(id:) through @Bindable"
                    : "each drawn row's recorded handler holding the list as it was when the row was drawn"),
            make: { config, width, height, cold in
                DrivenSession(LogVariantSession(config: config, variant: variant), width: width, height: height, cold: cold)
            })
    }
}
