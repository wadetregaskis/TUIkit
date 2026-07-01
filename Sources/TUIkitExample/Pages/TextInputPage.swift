//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TextInputPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// The text-entry family on one focused page: single-line ``TextField``,
/// masked ``SecureField``, and the multi-line ``TextEditor`` — plus the shared
/// cursor settings (shape / animation / speed) that apply to every field.
struct TextInputPage: View {
    // TextField state
    @State private var demoText: String = ""
    @State private var searchQuery: String = ""
    @State private var submittedValue: String = ""

    // SecureField state
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var apiKey: String = ""
    @State private var submittedPassword: String = ""

    // TextEditor state
    @State private var notes: String = L("page.newControls.editorSample")

    // Disabled samples
    @State private var disabledText: String = L("page.textField.cannotEdit")
    @State private var disabledPassword: String = "secret123"

    // Cursor settings (F1/F2/F3), applied to the whole page's cursor.
    @State private var cursorShapeIndex: Int = 0
    @State private var cursorAnimationIndex: Int = 0
    @State private var cursorSpeedIndex: Int = 1  // Start at regular

    private let shapes: [TextCursorStyle.Shape] = [.block, .bar, .underscore]
    private let animations: [TextCursorStyle.Animation] = [.none, .blink, .pulse]
    private let speeds: [TextCursorStyle.Speed] = [.slow, .regular, .fast]

    private var currentShape: TextCursorStyle.Shape { shapes[cursorShapeIndex] }
    private var currentAnimation: TextCursorStyle.Animation { animations[cursorAnimationIndex] }
    private var currentSpeed: TextCursorStyle.Speed { speeds[cursorSpeedIndex] }

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

            // MARK: TextField
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

            // MARK: SecureField
            DemoSection(L("page.secureField.section.passwordFields")) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 1) {
                        Text("\(L("page.secureField.password")):").foregroundStyle(.palette.foregroundSecondary)
                        SecureField(L("page.secureField.password"), text: $password)
                    }
                    HStack(spacing: 1) {
                        Text("\(L("page.secureField.confirm")):").foregroundStyle(.palette.foregroundSecondary)
                        SecureField("Confirm", text: $confirmPassword, prompt: Text(L("page.secureField.reenterPassword")))
                    }
                    HStack(spacing: 1) {
                        Text("\(L("page.secureField.apiKey")):").foregroundStyle(.palette.foregroundSecondary)
                        SecureField(L("page.secureField.apiKey"), text: $apiKey)
                            .onSubmit {
                                submittedPassword =
                                    "\(L("page.secureField.submittedPrefix")) \(apiKey.count) \(L("page.secureField.characters"))"
                            }
                    }
                    if !submittedPassword.isEmpty {
                        HStack(spacing: 1) {
                            Text("\(L("page.secureField.status")):").foregroundStyle(.palette.foregroundSecondary)
                            Text(submittedPassword).foregroundStyle(.palette.success)
                        }
                    }
                    HStack(spacing: 1) {
                        Text("\(L("page.secureField.match")):").foregroundStyle(.palette.foregroundSecondary)
                        if password.isEmpty && confirmPassword.isEmpty {
                            Text(L("page.secureField.enterPasswords")).dim()
                        } else if password == confirmPassword {
                            Text(L("page.secureField.passwordsMatch")).foregroundStyle(.palette.success)
                        } else {
                            Text(L("page.secureField.passwordsDiffer")).foregroundStyle(.palette.error)
                        }
                    }
                }
            }

            // MARK: TextEditor
            DemoSection(L("page.textInput.editorSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.newControls.editorHint")).foregroundStyle(.palette.foregroundSecondary)
                    // Default field appearance (a subtle field tint, like
                    // TextField) — no box; a scroll indicator appears when the
                    // text is taller than the frame.
                    TextEditor(text: $notes)
                        .frame(height: 5)
                    // The boxed look is available by adding `.border()`. Both
                    // share `notes`, so editing one updates the other.
                    Text(L("page.textInput.editorBordered")).foregroundStyle(.palette.foregroundSecondary)
                    TextEditor(text: $notes)
                        .frame(height: 4)
                        .border()
                }
            }

            // MARK: Disabled
            DemoSection(L("page.textField.section.disabled")) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 1) {
                        Text("\(L("page.textField.disabled")):").foregroundStyle(.palette.foregroundSecondary)
                        TextField("Disabled", text: $disabledText, prompt: Text(L("page.textField.cannotEdit")))
                            .disabled()
                    }
                    HStack(spacing: 1) {
                        Text("\(L("page.secureField.disabled")):").foregroundStyle(.palette.foregroundSecondary)
                        SecureField("Disabled", text: $disabledPassword).disabled()
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
            DemoAppHeader(L("page.textInput.title"))
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
