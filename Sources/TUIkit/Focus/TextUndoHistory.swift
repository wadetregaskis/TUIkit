//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextUndoHistory.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// What a text control's undo puts back: the text as it was before each edit,
/// and where the caret was then, newest last.
///
/// Generic over the caret because the text controls place theirs differently:
/// a field's is an index into its one line, an editor's a line and a column.
/// Everything else about undo is the same in both, so it is kept once, here.
struct TextUndoHistory<Caret> {
    /// The recorded states, oldest first.
    private var states: [(text: String, caret: Caret)] = []

    /// How many states are kept. Recording one more drops the oldest.
    let limit: Int

    init(limit: Int = 50) {
        self.limit = limit
    }

    /// Records the state before an edit.
    ///
    /// A state whose text is the newest one's is not recorded again, so an
    /// edit that pushes before a change it then does not make costs no undo
    /// step.
    mutating func record(text: String, caret: Caret) {
        if let last = states.last, last.text == text {
            return
        }
        states.append((text, caret))
        if states.count > limit {
            states.removeFirst()
        }
    }

    /// Takes the newest state, or `nil` when there is nothing to undo.
    mutating func popLast() -> (text: String, caret: Caret)? {
        states.popLast()
    }
}
