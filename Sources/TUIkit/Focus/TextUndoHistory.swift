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
///
/// The history describes the text the control itself produced, and only that.
/// The bound text can also be replaced from outside: the app loads another
/// document into the same editor, or clears a field on submit. The records
/// then describe text that is no longer there, and undoing onto the new text
/// would bring back text the control never produced from it. So the control
/// tells the history what it writes (``noteWritten(_:)``), and before the
/// history is used again (``forgetIfReplaced(current:)``) a text that is not
/// the one last written means a replacement, and the history is forgotten.
///
/// One step per edit, and a key is one edit: typing a word takes as many
/// undos as it has letters. The macOS text system groups a run of typing into
/// one step; this does not.
struct TextUndoHistory<Caret> {
    /// The recorded states, oldest first.
    private var states: [(text: String, caret: Caret)] = []

    /// The text the control last wrote, as its binding read it back, or `nil`
    /// before it has written anything.
    private var written: String?

    /// How many states are kept. Recording one more drops the oldest.
    let limit: Int

    init(limit: Int = 50) {
        self.limit = limit
    }

    /// Forgets the history if `current`, the bound text before the control
    /// records or undoes an edit, is not the text the control last wrote.
    ///
    /// Call it before the control writes anything for the key (or click) it
    /// is handling. Comparing strings is cheap when nothing replaced the text:
    /// the binding hands back the storage the control wrote.
    mutating func forgetIfReplaced(current: String) {
        guard let written, written != current else { return }
        states.removeAll()
        self.written = nil
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

    /// Notes the text the control has just written, as its binding reads it
    /// back, so a binding that rewrites what it is given is not taken for a
    /// replacement.
    mutating func noteWritten(_ text: String) {
        written = text
    }

    /// Takes the newest state, or `nil` when there is nothing to undo.
    mutating func popLast() -> (text: String, caret: Caret)? {
        states.popLast()
    }
}
