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
    case ghost
    case cursor

    /// The framework value this choice selects.
    var feedback: RowReorderFeedback {
        switch self {
        case .live: .live
        case .ghost: .ghost
        case .cursor: .cursor
        }
    }

    /// The localized option label.
    var label: String {
        switch self {
        case .live: L("page.list.reorderFeedback.live")
        case .ghost: L("page.list.reorderFeedback.ghost")
        case .cursor: L("page.list.reorderFeedback.cursor")
        }
    }
}
