//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ReorderFeedbackChoice.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// The drag-to-reorder feedback choices the Lists demo offers, mapped to the
/// framework's `RowReorderFeedback` values. Apply the chosen one with
/// `.rowReorderFeedback(choice.feedback)` and drag a row to see the difference.
enum ReorderFeedbackChoice: Int, CaseIterable {
    case live
    case dimmed
    case cursor

    /// The framework value this choice selects.
    var feedback: RowReorderFeedback {
        switch self {
        case .live: .live
        case .dimmed: .dimmed
        case .cursor: .cursor
        }
    }

    /// The localized option label.
    var label: String {
        switch self {
        case .live: L("page.list.reorderFeedback.live")
        case .dimmed: L("page.list.reorderFeedback.dimmed")
        case .cursor: L("page.list.reorderFeedback.cursor")
        }
    }
}
