//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FocusPage.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// Focus & raw-input demo page.
///
/// Demonstrates explicit focus identity and grouping (`.focusID` / `.focusSection`)
/// alongside the raw key handler (`.onKeyPress`):
/// - Two labelled focus sections you can Tab through, with a live readout of the
///   currently focused element's `focusID`.
/// - A live "last key pressed" logger fed by `.onKeyPress`.
struct FocusPage: View {
    @State private var lastKey: String = "—"

    // The focus manager publishes the currently focused element's id; reading it
    // in `body` re-evaluates each render, and a focus change requests a re-render,
    // so the readout below tracks the focus live as you Tab around.
    @Environment(\.focusManager) private var focusManager

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection(L("page.focus.sectionsSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.focus.sectionsDescription"))
                        .foregroundStyle(.palette.foregroundSecondary)

                    HStack(spacing: 3) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(L("page.focus.sectionA")).dim()
                            Button("A · One") {}.focusID("focus-a-one")
                            Button("A · Two") {}.focusID("focus-a-two")
                        }
                        .focusSection("focus-section-a")

                        VStack(alignment: .leading, spacing: 0) {
                            Text(L("page.focus.sectionB")).dim()
                            Button("B · One") {}.focusID("focus-b-one")
                            Button("B · Two") {}.focusID("focus-b-two")
                        }
                        .focusSection("focus-section-b")
                    }

                    ValueDisplayRow(
                        L("page.focus.focusedID"),
                        focusManager?.currentFocusedID ?? "—")
                }
            }

            DemoSection(L("page.focus.keyLoggerSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.focus.keyLoggerDescription"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    ValueDisplayRow(L("page.focus.lastKey"), lastKey)
                }
            }

            Spacer()
        }
        .onKeyPress { event in
            lastKey = describeKey(event)
            // Don't consume — let Tab (focus), Esc (back) and everything else
            // continue through the dispatch chain.
            return false
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader(L("page.focus.title"))
        }
    }

    // MARK: - Helpers

    /// A readable description of a key event for the logger.
    private func describeKey(_ event: KeyEvent) -> String {
        var parts: [String] = []
        if event.ctrl { parts.append("Ctrl") }
        if event.alt { parts.append("Alt") }
        if event.shift { parts.append("Shift") }
        parts.append(keyName(event.key))
        return parts.joined(separator: "+")
    }

    // The complexity is the one-line-per-key switch itself; splitting it
    // into helpers would fragment the table without simplifying it. Block
    // form keeps the suppression adjacent to the function.
    // swiftlint:disable cyclomatic_complexity
    private func keyName(_ key: Key) -> String {
        switch key {
        case .escape: return "Esc"
        case .enter: return "Enter"
        case .tab: return "Tab"
        case .backspace: return "Backspace"
        case .delete: return "Delete"
        case .space: return "Space"
        case .up: return "Up"
        case .down: return "Down"
        case .left: return "Left"
        case .right: return "Right"
        case .home: return "Home"
        case .end: return "End"
        case .pageUp: return "PageUp"
        case .pageDown: return "PageDown"
        case .f1: return "F1"
        case .f2: return "F2"
        case .f3: return "F3"
        case .f4: return "F4"
        case .f5: return "F5"
        case .f6: return "F6"
        case .f7: return "F7"
        case .f8: return "F8"
        case .f9: return "F9"
        case .f10: return "F10"
        case .f11: return "F11"
        case .f12: return "F12"
        case .character(let ch): return "'\(ch)'"
        case .paste: return "(paste)"
        default: return "(other)"
        }
    }
    // swiftlint:enable cyclomatic_complexity
}
