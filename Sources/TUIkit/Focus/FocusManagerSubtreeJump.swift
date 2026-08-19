//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FocusManagerSubtreeJump.swift
//
//  Where a jump within one subtree's own focus stops can land. The jump itself
//  lives in `Focus.swift`, beside the focus state it moves.
//
//  Created by Wade Tregaskis
//  License: MIT

extension FocusManager {

    /// Where a jump within one subtree's own focus stops lands.
    enum SubtreeFocusJump: Equatable {
        /// The subtree's first stop (`Home`).
        case first
        /// Its last (`End`).
        case last
        /// A screenful further on, clamped at the end (`Page Down`).
        case forward(Int)
        /// A screenful back, clamped at the start (`Page Up`).
        case backward(Int)
    }
}
