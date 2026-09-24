//  🖥️ TUIkit — Terminal UI Kit for Swift
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
    /// Shared by the three `.textFieldStyle` fields, so what differs between
    /// them is visibly the chrome rather than the content.
    @State private var styledText: String = "Ada"
    @State private var searchQuery: String = ""
    @State private var submittedValue: String = ""

    // Cascading .onSubmit demo state
    @State private var formName: String = ""
    @State private var formEmail: String = ""
    @State private var submitLog: [String] = []

    // SecureField state
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var apiKey: String = ""
    /// The count, not a sentence: the sentence is built where it is shown, from
    /// a key that carries the count as `%@`, so a translation may place it.
    @State private var submittedLength: Int?

    // TextEditor state
    @State private var notes: String = L("page.newControls.editorSample")

    // Disabled samples
    @State private var disabledText: String = L("page.textField.cannotEdit")
    @State private var disabledPassword: String = "secret123"

    // Cursor settings (F1/F2/F3), applied to the whole page's cursor.
    @State private var cursorShapeIndex: Int = 0
    @State private var cursorAnimationIndex: Int = 0
    @State private var cursorSpeedIndex: Int = 1  // Start at standard

    private let shapes: [TextCursorStyle.Shape] = [.block, .bar, .underscore]
    private let animations: [TextCursorStyle.Animation] = [.none, .blink, .pulse]
    /// The caret's speed is not part of its style: it is the speed set for
    /// `.textCursor` with `.indicatorAnimationSpeed(_:for:)`. F3 steps through the
    /// three recommended presets, though any positive rate works.
    private let speeds: [IndicatorAnimationSpeed] = [.halfSpeed, .standard, .doubleSpeed]

    private var currentShape: TextCursorStyle.Shape { shapes[cursorShapeIndex] }
    private var currentAnimation: TextCursorStyle.Animation { animations[cursorAnimationIndex] }
    private var currentSpeed: IndicatorAnimationSpeed { speeds[cursorSpeedIndex] }

    private var shapeLabel: String {
        // The glyph prefix is the shape's own rendering, so the label always
        // previews exactly what the caret will draw.
        "\(currentShape.character) \(localizedShapeName)"
    }

    private var localizedShapeName: String {
        switch currentShape {
        case .block: L("page.textField.shape.block")
        case .bar: L("page.textField.shape.bar")
        case .underscore: L("page.textField.shape.underscore")
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
        // By position, because a speed is a value rather than an enum case.
        switch cursorSpeedIndex {
        case 0: L("page.textField.speed.half")
        case 2: L("page.textField.speed.double")
        default: L("page.textField.speed.standard")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            // MARK: TextField
            DemoSection("page.textField.section.cursorDemo") {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 1) {
                        Text("\(L("page.textField.input")):").foregroundStyle(.palette.foregroundSecondary)
                        TextField("Input", text: $demoText, prompt: Text("page.textField.typeHere"))
                    }
                    HStack(spacing: 1) {
                        Text("\(L("page.textField.search")):").foregroundStyle(.palette.foregroundSecondary)
                        TextField("Search", text: $searchQuery, prompt: Text("page.textField.enterSearchTerm"))
                            .onSubmit { submittedValue = searchQuery }
                    }
                    if !submittedValue.isEmpty {
                        HStack(spacing: 1) {
                            Text("\(L("page.textField.submitted")):").foregroundStyle(.palette.foregroundSecondary)
                            Text(submittedValue).foregroundStyle(.palette.success)
                        }
                    }
                    Text("page.textField.cursorInherited").dim()
                }
                // .textFieldTextStyle re-themes the entered text of all fields
                // in this section (cursor, selection and prompt keep their colours).
                .textFieldTextStyle { $0.foreground = .palette.accent }
            }

            // MARK: .textFieldStyle
            DemoSection("page.textInput.styleSection") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.textInput.styleExplain")
                        .foregroundStyle(.palette.foregroundSecondary)
                    HStack(spacing: 1) {
                        Text(".automatic").foregroundStyle(.palette.foregroundSecondary)
                            .frame(width: 12)
                        TextField("Automatic", text: $styledText).frame(width: 24)
                    }
                    HStack(spacing: 1) {
                        Text(".plain").foregroundStyle(.palette.foregroundSecondary)
                            .frame(width: 12)
                        TextField("Plain", text: $styledText)
                            .textFieldStyle(.plain)
                            .frame(width: 24)
                    }
                    // The point of `.plain`: a field that reads as part of a
                    // sentence. Both fields above edit the SAME binding, so the
                    // difference on screen is the chrome and nothing else.
                    HStack(spacing: 0) {
                        Text("page.textInput.styleInlineLead")
                        TextField("Inline", text: $styledText)
                            .textFieldStyle(.plain)
                            .frame(width: 16)
                        Text("page.textInput.styleInlineTail")
                    }
                }
            }

            // MARK: Cascading .onSubmit
            DemoSection("page.textInput.submitSection") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.textInput.submitExplain")
                        .foregroundStyle(.palette.foregroundSecondary)

                    // One `.onSubmit` on the VStack cascades to BOTH fields:
                    // Return in either runs it. The Email field ALSO has its own
                    // per-field `.onSubmit`, so submitting there logs twice
                    // (per-field first, then the cascading form action).
                    // SwiftUI's `.submitLabel(_:)` has no counterpart: it
                    // labels an on-screen keyboard's Return key, which a
                    // terminal does not have, so TUIkit omits it rather than
                    // accepting it and doing nothing.
                    VStack(alignment: .leading, spacing: 0) {
                        TextField(
                            "page.textInput.submitName", text: $formName,
                            prompt: Text("page.textInput.submitName"))
                        TextField(
                            "page.textInput.submitEmail", text: $formEmail,
                            prompt: Text("page.textInput.submitEmail"))
                            .onSubmit { logSubmit(L("page.textInput.submitEmailCommitted")) }
                    }
                    .onSubmit {
                        logSubmit("\(L("page.textInput.submitForm")): \(formName) / \(formEmail)")
                    }

                    if submitLog.isEmpty {
                        Text("page.textInput.submitHint").dim()
                    } else {
                        ForEach(Array(submitLog.suffix(4).enumerated()), id: \.offset) { _, entry in
                            Text("• \(entry)").foregroundStyle(.palette.success)
                        }
                    }
                }
            }

            // MARK: SecureField
            DemoSection("page.secureField.section.passwordFields") {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 1) {
                        Text("\(L("page.secureField.password")):").foregroundStyle(.palette.foregroundSecondary)
                        SecureField("page.secureField.password", text: $password)
                    }
                    HStack(spacing: 1) {
                        Text("\(L("page.secureField.confirm")):").foregroundStyle(.palette.foregroundSecondary)
                        SecureField("Confirm", text: $confirmPassword, prompt: Text("page.secureField.reenterPassword"))
                    }
                    HStack(spacing: 1) {
                        Text("\(L("page.secureField.apiKey")):").foregroundStyle(.palette.foregroundSecondary)
                        SecureField("page.secureField.apiKey", text: $apiKey)
                            .onSubmit { submittedLength = apiKey.count }
                    }
                    if let submittedLength {
                        HStack(spacing: 1) {
                            Text("\(L("page.secureField.status")):").foregroundStyle(.palette.foregroundSecondary)
                            Text("page.secureField.submitted \(submittedLength)").foregroundStyle(.palette.success)
                        }
                    }
                    HStack(spacing: 1) {
                        Text("\(L("page.secureField.match")):").foregroundStyle(.palette.foregroundSecondary)
                        if password.isEmpty && confirmPassword.isEmpty {
                            Text("page.secureField.enterPasswords").dim()
                        } else if password == confirmPassword {
                            Text("page.secureField.passwordsMatch").foregroundStyle(.palette.success)
                        } else {
                            Text("page.secureField.passwordsDiffer").foregroundStyle(.palette.error)
                        }
                    }
                }
            }

            // MARK: TextEditor
            DemoSection("page.textInput.editorSection") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.newControls.editorHint").foregroundStyle(.palette.foregroundSecondary)
                    // Default field appearance (a subtle field tint, like
                    // TextField) — no box; a scroll indicator appears when the
                    // text is taller than the frame.
                    TextEditor(text: $notes)
                        .frame(height: 5)
                    // The boxed look is available by adding `.border()`. Both
                    // share `notes`, so editing one updates the other.
                    Text("page.textInput.editorBordered").foregroundStyle(.palette.foregroundSecondary)
                    TextEditor(text: $notes)
                        .frame(height: 4)
                        .border()

                    // The editor's own legend, right under the editors rather
                    // than at the foot of the page: these are readline's
                    // bindings, they are not written on anything, and a reader
                    // who has just clicked into a field is not going to scroll
                    // to find out what Ctrl-U does.
                    KeyboardHelpSection(
                        "page.textInput.editorKeysSection",
                        shortcuts: [
                            "page.textInput.editorKeys.motion",
                            "page.textInput.editorKeys.lineEnds",
                            "page.textInput.editorKeys.words",
                            "page.textInput.editorKeys.kill",
                            "page.textInput.editorKeys.selectAll",
                            "page.textInput.editorKeys.undoClipboard",
                        ])
                }
            }

            // MARK: Disabled
            DemoSection("page.textField.section.disabled") {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 1) {
                        Text("\(L("page.textField.disabled")):").foregroundStyle(.palette.foregroundSecondary)
                        TextField("Disabled", text: $disabledText, prompt: Text("page.textField.cannotEdit"))
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
                    "page.textField.help.moveCursor",
                    "page.textField.help.jumpStartEnd",
                    "page.textField.help.backspace",
                    "page.textField.help.delete",
                    "page.textField.help.submit",
                    "page.textField.help.nextField",
                ])

                KeyboardHelpSection(
                    "page.textField.section.cursorSettings",
                    shortcuts: [
                        "page.textField.help.f1Shape",
                        "page.textField.help.f2Animation",
                        "page.textField.help.f3Speed",
                    ]
                )
            }

            Spacer()
        }
        .textCursor(currentShape, animation: currentAnimation)
        .indicatorAnimationSpeed(currentSpeed, for: .textCursor)
        .statusBarItems(cursorStatusBarItems)
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader("menu.item.textInput")
        }
    }

    /// Appends a submit-log entry, keeping only the most recent handful.
    private func logSubmit(_ entry: String) {
        submitLog.append(entry)
        if submitLog.count > 8 { submitLog.removeFirst(submitLog.count - 8) }
    }

    private var cursorStatusBarItems: [any StatusBarItemProtocol] {
        [
            StatusBarItem(shortcut: Shortcut.escape, label: "page.textField.back"),
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
