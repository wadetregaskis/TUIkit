//  🖥️ TUIKit — Terminal UI Kit for Swift
//  OverlaysPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

// MARK: - Overlay Demo Variants

/// Available overlay demo variants.
private enum OverlayDemo: Int, CaseIterable {
    case alertStandard
    case alertWarning
    case alertError
    case alertInfo
    case alertSuccess
    case dialog
    case dialogWithFooter
    case dialogAuth
    case dialogProse
    case modalCustom
    case notification

    /// Display label for the menu.
    var label: String {
        switch self {
        case .alertStandard: L("page.overlays.label.alertStandard")
        case .alertWarning: L("page.overlays.label.alertWarning")
        case .alertError: L("page.overlays.label.alertError")
        case .alertInfo: L("page.overlays.label.alertInfo")
        case .alertSuccess: L("page.overlays.label.alertSuccess")
        case .dialog: L("page.overlays.label.dialog")
        case .dialogWithFooter: L("page.overlays.label.dialogWithFooter")
        case .dialogAuth: L("page.overlays.label.dialogAuth")
        case .dialogProse: L("page.overlays.label.dialogProse")
        case .modalCustom: L("page.overlays.label.modalCustom")
        case .notification: L("page.overlays.label.notification")
        }
    }

    /// Description text for the detail panel.
    var description: String {
        switch self {
        case .alertStandard:
            L("page.overlays.desc.alertStandard")
        case .alertWarning:
            L("page.overlays.desc.alertWarning")
        case .alertError:
            L("page.overlays.desc.alertError")
        case .alertInfo:
            L("page.overlays.desc.alertInfo")
        case .alertSuccess:
            L("page.overlays.desc.alertSuccess")
        case .dialog:
            L("page.overlays.desc.dialog")
        case .dialogWithFooter:
            L("page.overlays.desc.dialogWithFooter")
        case .dialogAuth:
            L("page.overlays.desc.dialogAuth")
        case .dialogProse:
            L("page.overlays.desc.dialogProse")
        case .modalCustom:
            L("page.overlays.desc.modalCustom")
        case .notification:
            L("page.overlays.desc.notification")
        }
    }

    /// API usage example for the detail panel, already broken into the lines it
    /// should be shown on.
    ///
    /// Written out the way the call would actually be written rather than
    /// squeezed onto one line: a trailing-closure API folded into a single
    /// string is exactly the shape a terminal wraps worst, and what came out the
    /// other side — a `message:` label orphaned at the start of a line, at the
    /// panel's own indent — read as a different statement rather than as the
    /// continuation of one.
    var apiUsage: [String] {
        switch self {
        case .alertStandard:
            [
                ".alert(\"Title\", isPresented: $show) {",
                "    actions",
                "} message: {",
                "    Text(\"...\")",
                "}",
            ]
        case .alertWarning:
            Self.modalCall("Alert.warning(message: \"...\") { actions }")
        case .alertError:
            Self.modalCall("Alert.error(message: \"...\") { actions }")
        case .alertInfo:
            Self.modalCall("Alert.info(message: \"...\") { actions }")
        case .alertSuccess:
            Self.modalCall("Alert.success(message: \"...\") { actions }")
        case .dialog:
            Self.modalCall("Dialog(title: \"...\") { content }")
        case .dialogWithFooter:
            [
                ".modal(isPresented: $show) {",
                "    Dialog(title: \"...\") {",
                "        content",
                "    } footer: {",
                "        buttons",
                "    }",
                "}",
            ]
        case .dialogAuth:
            [
                ".modal(isPresented: $show) {",
                "    Dialog(\"Sign in\") {",
                "        TextField / SecureField",
                "    } footer: {",
                "        Cancel; Sign in",
                "    }",
                "}",
            ]
        case .dialogProse:
            Self.modalCall("Dialog(\"...\") { Text(paragraphs) }")
                + [".dialogPreferredWidth(100)"]
        case .modalCustom:
            Self.modalCall("VStack { ... }")
        case .notification:
            ["NotificationService.current.post(\"Saved!\")"]
        }
    }

    /// The `.modal(isPresented:)` wrapper every dialog demo shares, around one
    /// line of content.
    private static func modalCall(_ content: String) -> [String] {
        [".modal(isPresented: $show) {", "    " + content, "}"]
    }

    /// Whether this demo variant is a notification (not a modal).
    var isNotification: Bool {
        self == .notification
    }
}

// MARK: - Overlays Page

/// Interactive overlays and modals demo page.
///
/// Displays a menu of overlay variants on the left and a description
/// panel on the right. Pressing Enter shows the selected overlay
/// with dimmed background content.
struct OverlaysPage: View {
    @FocusState private var focusedDemo: OverlayDemo?
    @State var showOverlay: Bool = false
    @State var authUsername: String = ""
    @State var authPassword: String = ""
    @State private var showConfirm = false
    @State private var confirmChoice = "—"
    @State private var showPopover = false
    @State private var showCover = false
    @State private var showDetented = false
    @State private var detent: PresentationDetent = .medium

    /// Callback to navigate back to the main menu.
    let onBack: () -> Void

    /// The demo the description panel describes: whichever entry holds
    /// focus, falling back to the first before anything does.
    private var selectedDemo: OverlayDemo {
        focusedDemo ?? .alertStandard
    }

    /// The demo the OPEN overlay is showing.
    ///
    /// Deliberately not `selectedDemo`. Presenting a modal isolates the page
    /// beneath it, so the menu rows stop registering and `focusedDemo` goes
    /// nil — one frame after the overlay appears, a focus-derived choice falls
    /// back to `.alertStandard` and the overlay swaps to the wrong demo in
    /// front of you. What is being SHOWN has to be decided when it is opened,
    /// not re-derived from a focus the act of opening took away.
    @State private var presentedDemo: OverlayDemo = .alertStandard

    var body: some View {
        backgroundContent
            .modal(isPresented: $showOverlay) {
                overlayContent(for: presentedDemo)
            }
            .confirmationDialog(
                "page.overlays.confirm.title",
                isPresented: $showConfirm,
                titleVisibility: .visible,
                actions: {
                    Button("page.overlays.confirm.delete", role: .destructive) {
                        confirmChoice = L("page.overlays.confirm.deleted")
                    }
                    Button("page.overlays.confirm.cancel", role: .cancel) {
                        confirmChoice = L("page.overlays.confirm.cancelled")
                    }
                },
                message: { Text("page.overlays.confirm.message") })
            // Note: notifications are hosted once at the app root (see
            // `ExampleApp` in main.swift) so a toast posted here survives
            // navigating back to the menu, rather than vanishing with the page.
            .statusBarItems(statusBarItems)
    }

    /// Whether any of this page's presentations is on screen.
    ///
    /// `.statusBarItems` sits outside every one of them, so the framework's
    /// backdrop isolation — which drops the items a presented page declares
    /// *inside* the presentation — does not reach these. The page has to
    /// withdraw them itself.
    private var isPresenting: Bool {
        showOverlay || showConfirm || showPopover || showCover || showDetented
    }

    /// The page's own footer, withdrawn while anything is presented.
    ///
    /// Each presentation publishes its own dismiss item and takes the keys, so
    /// what the page would add is a promise it can no longer keep: "⎋ back"
    /// goes nowhere, and "↵ show" describes an Enter that now activates
    /// whatever the presentation focused. Saying nothing leaves the bar reading
    /// "⎋ dismiss   q quit" — which is what a dialog already showed, and now
    /// what the confirmation dialog, the cover, the sheet and the popover show
    /// too.
    private var statusBarItems: [any StatusBarItemProtocol] {
        guard !isPresenting else { return [] }
        // Escape only. The Return entry is the bar's own, labelled by whatever
        // holds the focus — which is what "show" was trying and failing to be.
        return [
            StatusBarItem(shortcut: Shortcut.escape, label: "page.overlays.status.back") {
                onBack()
            }
        ]
    }

    // MARK: - Background Content

    /// The main background content with menu and description.
    private var backgroundContent: some View {
        VStack(alignment: .leading, spacing: 1) {
            // Top-aligned: the menu windows itself to the page's visible
            // viewport, which only keeps its selection on screen if the menu
            // actually starts at the top of the page — centre alignment
            // against the (taller) description panel would push its lower
            // rows, selection included, below the fold on short terminals.
            HStack(alignment: .top, spacing: 3) {
                // Left: Demo menu
                // An inline Menu: each demo is a Button, and the panel beside
                // it describes whichever one holds focus. Reading `@FocusState`
                // in the body is what makes the description follow the arrows
                // — a menu item's action only runs when you actually pick it.
                Menu("page.overlays.selectDemo") {
                    ForEach(OverlayDemo.allCases, id: \.self) { demo in
                        Button(demo.label) {
                            if demo.isNotification {
                                NotificationService.current.post(
                                    "page.overlays.alert.successMessage"
                                )
                            } else {
                                presentedDemo = demo
                                showOverlay = true
                            }
                        }
                        .focused($focusedDemo, equals: demo)
                    }
                }
                .menuStyle(.inline)

                // Right: Description of selected demo
                descriptionPanel
            }

            DemoSection("page.overlays.confirm.section") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.overlays.confirm.explain")
                        .foregroundStyle(.palette.foregroundSecondary)
                    HStack(spacing: 2) {
                        // Clear the read-out as the dialog opens, so choosing
                        // the same answer twice running still reads as two
                        // answers rather than as nothing having happened.
                        Button("page.overlays.confirm.trigger") {
                            confirmChoice = "—"
                            showConfirm = true
                        }
                        ValueDisplayRow("page.overlays.confirm.result", confirmChoice)
                    }
                }
            }

            DemoSection("page.overlays.variants.section") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.overlays.variants.explain")
                        .foregroundStyle(.palette.foregroundSecondary)
                    HStack(spacing: 2) {
                        // A popover anchors to the button that opened it, so
                        // this one is deliberately not centred on the screen.
                        Button("page.overlays.variants.popover") { showPopover = true }
                            .popover(isPresented: $showPopover) {
                                VStack(alignment: .leading) {
                                    Text("page.overlays.variants.popoverTitle").bold()
                                    Text("page.overlays.variants.popoverBody")
                                        .foregroundStyle(.palette.foregroundSecondary)
                                }
                            }

                        Button("page.overlays.variants.cover") { showCover = true }

                        Button("page.overlays.variants.sheet") { showDetented = true }
                    }
                    // The terminal's stand-in for dragging a sheet's grabber:
                    // the bound selection, moved by a control the app owns.
                    Picker("page.overlays.variants.detent", selection: $detent) {
                        Text("page.overlays.variants.detentMedium").tag(PresentationDetent.medium)
                        Text("page.overlays.variants.detentLarge").tag(PresentationDetent.large)
                        Text("8").tag(PresentationDetent.height(8))
                    }
                }
            }

            DemoSection("page.overlays.section.howItWorks") {
                Text("page.overlays.howItWorks.intro")
                    .foregroundStyle(.palette.foregroundSecondary)
                Text("  .alert(isPresented:)        — \(L("page.overlays.howItWorks.alertLine"))")
                    .foregroundStyle(.palette.foregroundSecondary)
                Text("  .modal(isPresented:)        — \(L("page.overlays.howItWorks.modalLine"))")
                    .foregroundStyle(.palette.foregroundSecondary)
                Text("  NotificationService.current.post() — \(L("page.overlays.howItWorks.notifLine"))")
                    .foregroundStyle(.palette.foregroundSecondary)
                Text("page.overlays.howItWorks.summary")
                    .bold()
                    .foregroundStyle(.palette.accent)
            }

            Spacer()
        }
        .scrollableDemoPage()
        // The cover and the detented sheet are attached at the PAGE, not at
        // their buttons: both present over the whole screen, so hanging them
        // off a button inside a scroll view would only make the attachment
        // point harder to reason about. (A popover is the opposite — it
        // belongs to its button, and is attached there.)
        .fullScreenCover(isPresented: $showCover) {
            VStack(spacing: 1) {
                Text("page.overlays.variants.coverTitle").bold()
                Text("page.overlays.variants.coverBody")
                    .foregroundStyle(.palette.foregroundSecondary)
                Button("button.close") { showCover = false }
            }
        }
        .sheet(isPresented: $showDetented) {
            Dialog(title: "page.overlays.variants.sheetTitle") {
                // A blank row between the prose and the action, and the action
                // at the trailing edge — where a dialog's confirming button
                // sits on every desktop platform. Packed against the text it
                // read as another line of the message.
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.overlays.variants.sheetBody")
                    Button("button.close") { showDetented = false }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .presentationDetents([.medium, .large, .height(8)], selection: $detent)
        }
        .appHeader {
            DemoAppHeader("menu.item.overlays")
        }
    }

    // MARK: - Description Panel

    /// Detail panel showing the selected demo's description and API usage.
    ///
    /// No `.frame(width:)`. It used to be pinned to 55 columns, which wrapped
    /// every API line even with half the page still empty beside it; left to
    /// size itself the panel takes the width its longest line asks for, bounded
    /// by what the row has left, so the code only wraps when it genuinely
    /// cannot fit.
    private var descriptionPanel: some View {
        Panel(selectedDemo.label, titleColor: .palette.accent) {
            // One blank line between the description and the API block — the
            // stack's own spacing. There used to be three: the spacing on either
            // side of an explicit empty `Text`.
            VStack(alignment: .leading, spacing: 1) {
                Text(selectedDemo.description)
                    .foregroundStyle(.palette.foreground)

                VStack(alignment: .leading, spacing: 0) {
                    Text("page.overlays.apiLabel")
                        .bold()
                        .foregroundStyle(.palette.accent)
                    ForEach(selectedDemo.apiUsage, id: \.self) { line in
                        // Built as a String rather than interpolated into a
                        // literal, so it stays a string and not a lookup key.
                        Text("  " + line)
                            .foregroundStyle(.palette.foregroundSecondary)
                    }
                }
            }
        }
    }

    // MARK: - The two dialog demos

    /// "Dialog": deliberately FOOTERLESS — `Dialog(title:) { content }`, the
    /// convenience init nothing else on this page reaches.
    ///
    /// That absence is the whole point of the demo: no separator rule, no
    /// button row, nothing below the body. With a lone Dismiss in each, this
    /// and ``confirmDialog`` rendered as the same dialog with different words
    /// in it, and the second demo's entire subject went unseen.
    ///
    /// A read-only panel needs no button, and Esc closes it (the status bar
    /// says so while it is open, and the body says so too, so the absence reads
    /// as deliberate). Note where the button ISN'T: a dialog's body scrolls on
    /// a short terminal, so a control put in the body can be scrolled out of
    /// reach. That is what footers are for — and what the demo below shows.
    private var settingsDialog: some View {
        Dialog(
            title: "page.overlays.dialog.settingsTitle",
            borderColor: .palette.border, titleColor: .palette.accent
        ) {
            VStack(alignment: .leading) {
                Text("page.overlays.dialog.themeDark").foregroundStyle(.palette.foreground)
                Text("page.overlays.dialog.languageEnglish").foregroundStyle(.palette.foreground)
                Text("page.overlays.dialog.notificationsOn").foregroundStyle(.palette.foreground)
                Text("")
                Text("page.overlays.dialog.noFooterHint")
                    .foregroundStyle(.palette.foregroundSecondary)
            }
        }
    }

    /// "Dialog with Footer": the counterpart to ``settingsDialog`` — a divider,
    /// then a ROW of actions pinned beneath the body.
    ///
    /// Two buttons, not one. A single button reads as one more line of content;
    /// Cancel / Proceed reads unmistakably as a footer bar. A confirmation is
    /// also the case that genuinely needs one, which is why this is the demo
    /// that has it.
    private var confirmDialog: some View {
        Dialog(
            title: "page.overlays.dialog.confirmTitle",
            borderColor: .palette.border, titleColor: .palette.accent,
            footerAlignment: .trailing
        ) {
            Text("page.overlays.dialog.confirmBody").foregroundStyle(.palette.foreground)
            Text("page.overlays.dialog.confirmUndone").foregroundStyle(.palette.foregroundSecondary)
        } footer: {
            HStack {
                Button("page.overlays.button.cancel") {
                    showOverlay = false
                }
                .keyboardShortcut(.cancelAction)
                Button("page.overlays.button.proceed") {
                    showOverlay = false
                }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Overlay Content

    /// Builds the overlay content for the selected demo variant.
    @ViewBuilder
    private func overlayContent(for demo: OverlayDemo) -> some View {
        switch demo {
        case .alertStandard, .alertWarning, .alertError,
            .alertInfo, .alertSuccess:
            alertContent(for: demo)

        case .dialog:
            settingsDialog

        case .dialogWithFooter:
            confirmDialog

        case .dialogProse:
            // Deliberately NO `.frame(width:)`: the point of this demo is the
            // dialog choosing its own width. Prose can technically be laid out
            // as one enormous line per paragraph, so on a wide terminal a
            // dialog that simply took what it was offered would be painful to
            // read. It wraps at `dialogPreferredWidth` (100 by default) while
            // that fits, and only spends more of the screen when the extra
            // width actually buys back vertical room — resize the terminal
            // narrow and tall, then short and wide, to watch it decide.
            Dialog(
                title: "page.overlays.dialog.proseTitle",
                borderColor: .palette.border, titleColor: .palette.accent,
                footerAlignment: .trailing
            ) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.overlays.dialog.proseIntro")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text("page.overlays.dialog.proseParagraph1")
                        .foregroundStyle(.palette.foreground)
                    Text("page.overlays.dialog.proseParagraph2")
                        .foregroundStyle(.palette.foreground)
                    Text("page.overlays.dialog.proseParagraph3")
                        .foregroundStyle(.palette.foreground)
                }
            } footer: {
                dismissButton
            }

        case .dialogAuth:
            Dialog(
                title: "page.overlays.dialog.signInTitle",
                borderColor: .palette.border, titleColor: .palette.accent,
                footerAlignment: .trailing
            ) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.overlays.dialog.enterCredentials")
                        .foregroundStyle(.palette.foregroundSecondary)
                    // A Form, because that is where SwiftUI puts a field's label
                    // on screen at all. Measured against real macOS SwiftUI: a
                    // TextField in a plain VStack shows its title only as
                    // PLACEHOLDER text inside the field (and nothing at all once
                    // a prompt is supplied, or once the field has content) —
                    // which is exactly what TUIkit already did. Only inside a
                    // Form does the title become a real label, right-aligned in
                    // a shared column with the fields' left edges in line.
                    //
                    // No colons: SwiftUI's Form labels have none. Hand-rolling
                    // "Username:" as a sibling Text (the first attempt here)
                    // matched neither.
                    Form {
                        LabeledContent("page.overlays.dialog.username") {
                            TextField(
                                "", text: $authUsername,
                                prompt: Text("page.overlays.dialog.usernamePrompt"))
                        }
                        LabeledContent("page.overlays.dialog.password") {
                            SecureField(
                                "", text: $authPassword,
                                prompt: Text("page.overlays.dialog.passwordPrompt"))
                        }
                    }
                }
            } footer: {
                HStack {
                    // Escape cancels, Return/Enter signs in — from anywhere in
                    // the dialog: the credential fields have no onSubmit, so
                    // Return falls through to the default button even while
                    // typing (macOS dialog semantics).
                    Button("page.overlays.button.cancel") {
                        authUsername = ""
                        authPassword = ""
                        showOverlay = false
                    }
                    .keyboardShortcut(.cancelAction)
                    Button("page.overlays.button.signIn") {
                        // Demo only — clear the password for safety.
                        authPassword = ""
                        showOverlay = false
                    }
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
                }
            }
            // A PREFERENCE, not a fixed frame — and the difference matters.
            // `TextField` is width-flexible, so it takes whatever it is
            // offered: left at the 100-cell default this sign-in box renders
            // 103 wide with 90-cell credential fields, which is silly. Stating
            // a narrower comfortable width still lets the dialog shrink on a
            // narrow terminal, still lets it grow if the content ever genuinely
            // needs the room, and still adapts when a translation runs long —
            // none of which a `.frame(width: 55)` would do.
            .dialogPreferredWidth(55)

        case .modalCustom:
            modalCustomBody

        case .notification:
            // Notifications are posted via NotificationService, not shown as modal content.
            EmptyView()
        }
    }

    /// Builds an alert for the given demo variant.
    @ViewBuilder
    private func alertContent(for demo: OverlayDemo) -> some View {
        switch demo {
        case .alertStandard:
            Alert(
                title: "page.overlays.alert.standardTitle",
                message: "page.overlays.alert.standardMessage",
                borderColor: .palette.border,
                titleColor: .palette.accent
            ) { EmptyView() }
        case .alertWarning:
            Alert(
                title: "page.overlays.alert.warningTitle",
                message: "page.overlays.alert.warningMessage",
                titleColor: .palette.warning
            ) { EmptyView() }
        case .alertError:
            Alert(
                title: "page.overlays.alert.errorTitle",
                message: "page.overlays.alert.errorMessage",
                titleColor: .palette.error
            ) { EmptyView() }
        case .alertInfo:
            Alert(
                title: "page.overlays.alert.infoTitle",
                message: "page.overlays.alert.infoMessage",
                titleColor: .palette.info
            ) { EmptyView() }
        case .alertSuccess:
            Alert(
                title: "page.overlays.alert.successTitle",
                message: "page.overlays.alert.successMessage",
                titleColor: .palette.success
            ) { EmptyView() }
        default:
            EmptyView()
        }
    }

    /// Reusable dismiss button for the Dialog variants. (The Alert variants take
    /// no actions — they are dismissed with Escape, shown in the status bar — so
    /// they pass `EmptyView()` rather than this.)
    ///
    /// No `HStack { Spacer(); … }` around it: a Spacer is width-flexible, so it
    /// reports whatever width it is offered, and a container is as wide as its
    /// widest part — one Spacer in a footer stretches the whole dialog to fill
    /// the terminal. `footerAlignment: .trailing` places the button instead, and
    /// leaves the dialog free to size itself to its content.
    private var dismissButton: some View {
        Button("page.overlays.button.dismiss") {
            showOverlay = false
        }
        .buttonStyle(.primary)
    }

    /// The "Modal (Custom)" body: an ordinary view presented as a modal, with
    /// no Dialog chrome and no fixed size — it is as big as what is in it.
    ///
    /// The Dismiss button simply sits in the stack. An earlier version pushed it
    /// to the trailing edge with a computed `.padding(.leading,)` — the max text
    /// width minus the button's rendered width — which meant hard-coding what
    /// `.primary` adds around a label AND counting Characters rather than cells,
    /// so any CJK label (this app ships zh and ja) would have mis-aligned it.
    /// Alignment that has to be computed from string lengths is a sign the
    /// layout wants expressing differently, not measuring harder.
    private var modalCustomBody: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("page.overlays.modal.title").bold().foregroundStyle(.palette.accent)
            Text("page.overlays.modal.line1").foregroundStyle(.palette.foreground)
            Text("page.overlays.modal.line2").foregroundStyle(.palette.foregroundSecondary)
            Text("page.overlays.modal.line3").foregroundStyle(.palette.foregroundSecondary)
            dismissButton
        }
        .padding(EdgeInsets(horizontal: 2, vertical: 1))
        .border(.palette.border)
    }
}
