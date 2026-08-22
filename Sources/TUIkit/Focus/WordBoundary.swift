//  🖥️ TUIkit — Terminal UI Kit for Swift
//  WordBoundary.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// Where a word starts and ends, for word-wise cursor motion and word deletion.
///
/// One definition, because there were two and they disagreed. `TextField`
/// counted `_` as part of a word — "the readline convention", said its comment
/// — and `TextEditor` did not, so Option-Left over `foo_bar` reached the start
/// of the token in a single-line field and stopped in the middle of it in the
/// multi-line one. Nothing about a control's line count should change what a
/// word is, and the underscore reading is the one that wins: `_` inside an
/// identifier is not a word break to anyone who typed it, and the editor is the
/// control more likely to hold code.
///
/// The scans are pure functions of a character array and an index, which is
/// what lets both controls share them: a `TextField` walks its whole text, a
/// `TextEditor` walks one line, and neither cares which it is.
enum WordBoundary {

    /// Whether `character` is part of a word — letters, digits and underscore.
    /// Everything else separates words.
    static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    /// The index of the start of the word at or before `index`: skip any
    /// separator run, then the word run.
    ///
    /// From the start of a word this lands on the start of the PREVIOUS word,
    /// which is what makes repeated Option-Left walk backwards a word at a time.
    static func previous(in characters: [Character], from index: Int) -> Int {
        var position = min(index, characters.count)
        while position > 0, !isWordCharacter(characters[position - 1]) { position -= 1 }
        while position > 0, isWordCharacter(characters[position - 1]) { position -= 1 }
        return position
    }

    /// The index of the end of the word at or after `index`: skip any separator
    /// run, then the word run.
    static func next(in characters: [Character], from index: Int) -> Int {
        var position = max(0, index)
        while position < characters.count, !isWordCharacter(characters[position]) {
            position += 1
        }
        while position < characters.count, isWordCharacter(characters[position]) {
            position += 1
        }
        return position
    }
}
