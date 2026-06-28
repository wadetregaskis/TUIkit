//  TUIKit - Terminal UI Kit for Swift
//  TextFieldPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// TextField demo page.
///
/// Shows interactive text field features including:
/// - Basic text input with cursor
/// - Cursor styles (block, bar, underscore)
/// - Cursor animations (none, blink, pulse)
/// - Cursor speeds (slow, regular, fast)
/// - Cursor navigation (left/right/home/end)
/// - Text editing (insert, backspace, delete)
/// - onSubmit action
/// - Disabled state
struct TextFieldPage: View {
    @State var demoText: String = ""
    @State var searchQuery: String = ""
    @State var disabledText: String = L("page.textField.cannotEdit")
    @State var submittedValue: String = ""

    @State var cursorShapeIndex: Int = 0
    @State var cursorAnimationIndex: Int = 0
    @State var cursorSpeedIndex: Int = 1  // Start at regular

    private let shapes: [TextCursorStyle.Shape] = [.block, .bar, .underscore]
    private let animations: [TextCursorStyle.Animation] = [.none, .blink, .pulse]
    private let speeds: [TextCursorStyle.Speed] = [.slow, .regular, .fast]

    private var currentShape: TextCursorStyle.Shape {
        shapes[cursorShapeIndex]
    }

    private var currentAnimation: TextCursorStyle.Animation {
        animations[cursorAnimationIndex]
    }

    private var currentSpeed: TextCursorStyle.Speed {
        speeds[cursorSpeedIndex]
    }

    private var shapeLabel: String {
        switch currentShape {
        case .block: "█ \(L("page.textField.shape.block"))"
        case .bar: "│ \(L("page.textField.shape.bar"))"
        case .underscore: "▁ \(L("page.textField.shape.underscore"))"
        }
    }

    private var animationLabel: String {
        switch currentAnimation {
        case .none: L("page.textField.animation.static")
        case .blink: L("page.textField.animation.blink")
        case .pulse: L("page.textField.animation.pulse")
        }
    }

    private var speedLabel: String {
        switch currentSpeed {
        case .slow: L("page.textField.speed.slow")
        case .regular: L("page.textField.speed.regular")
        case .fast: L("page.textField.speed.fast")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection(L("page.textField.section.cursorDemo")) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 1) {
                        Text("\(L("page.textField.input")):").foregroundStyle(.palette.foregroundSecondary)
                        TextField("Input", text: $demoText, prompt: Text(L("page.textField.typeHere")))
                    }
                    HStack(spacing: 1) {
                        Text("\(L("page.textField.search")):").foregroundStyle(.palette.foregroundSecondary)
                        TextField("Search", text: $searchQuery, prompt: Text(L("page.textField.enterSearchTerm")))
                            .onSubmit { submittedValue = searchQuery }
                    }
                    if !submittedValue.isEmpty {
                        HStack(spacing: 1) {
                            Text("\(L("page.textField.submitted")):").foregroundStyle(.palette.foregroundSecondary)
                            Text(submittedValue).foregroundStyle(.palette.success)
                        }
                    }
                    Text(L("page.textField.cursorInherited")).dim()
                }
                // .textFieldTextStyle re-themes the entered text of all fields
                // in this section (cursor, selection and prompt keep their colours).
                .textFieldTextStyle { $0.foreground = .palette.accent }
            }

            DemoSection(L("page.textField.section.disabled")) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 1) {
                        Text("\(L("page.textField.disabled")):").foregroundStyle(.palette.foregroundSecondary)
                        TextField("Disabled", text: $disabledText, prompt: Text(L("page.textField.cannotEdit")))
                            .disabled()
                    }
                }
            }

            HStack(alignment: .top, spacing: 3) {
                KeyboardHelpSection(shortcuts: [
                    L("page.textField.help.moveCursor"),
                    L("page.textField.help.jumpStartEnd"),
                    L("page.textField.help.backspace"),
                    L("page.textField.help.delete"),
                    L("page.textField.help.submit"),
                    L("page.textField.help.nextField"),
                ])

                KeyboardHelpSection(
                    L("page.textField.section.cursorSettings"),
                    shortcuts: [
                        L("page.textField.help.f1Shape"),
                        L("page.textField.help.f2Animation"),
                        L("page.textField.help.f3Speed"),
                    ]
                )
            }

            Spacer()
        }
        .padding(.horizontal, 1)
        .textCursor(currentShape, animation: currentAnimation, speed: currentSpeed)
        .statusBarItems(cursorStatusBarItems)
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader(L("page.textField.header"))
        }
    }

    private var cursorStatusBarItems: [any StatusBarItemProtocol] {
        [
            StatusBarItem(shortcut: Shortcut.escape, label: L("page.textField.back")),
            StatusBarItem(shortcut: Shortcut.f1, label: shapeLabel) {
                cursorShapeIndex = (cursorShapeIndex + 1) % shapes.count
            },
            StatusBarItem(shortcut: Shortcut.f2, label: animationLabel) {
                cursorAnimationIndex = (cursorAnimationIndex + 1) % animations.count
            },
            StatusBarItem(shortcut: Shortcut.f3, label: speedLabel) {
                cursorSpeedIndex = (cursorSpeedIndex + 1) % speeds.count
            },
        ]
    }
}
