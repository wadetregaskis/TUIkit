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

    /// API usage example for the detail panel.
    var apiUsage: String {
        switch self {
        case .alertStandard:
            ".alert(\"Title\", isPresented: $show) { actions } message: { Text(\"...\") }"
        case .alertWarning:
            ".modal(isPresented: $show) { Alert.warning(message: \"...\") { actions } }"
        case .alertError:
            ".modal(isPresented: $show) { Alert.error(message: \"...\") { actions } }"
        case .alertInfo:
            ".modal(isPresented: $show) { Alert.info(message: \"...\") { actions } }"
        case .alertSuccess:
            ".modal(isPresented: $show) { Alert.success(message: \"...\") { actions } }"
        case .dialog:
            ".modal(isPresented: $show) { Dialog(title: \"...\") { content } }"
        case .dialogWithFooter:
            ".modal(isPresented: $show) { Dialog(title: \"...\") { content } footer: { buttons } }"
        case .dialogAuth:
            ".modal(isPresented: $show) { Dialog(\"Sign in\") { TextField/SecureField } footer: { Cancel; Sign in } }"
        case .dialogProse:
            ".modal(isPresented: $show) { Dialog(\"...\") { Text(paragraphs) } }  .dialogPreferredWidth(100)"
        case .modalCustom:
            ".modal(isPresented: $show) { VStack { ... } }"
        case .notification:
            "NotificationService.current.post(\"Saved!\")"
        }
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
                L("page.overlays.confirm.title"),
                isPresented: $showConfirm,
                titleVisibility: .visible,
                actions: {
                    Button(L("page.overlays.confirm.delete"), role: .destructive) {
                        confirmChoice = L("page.overlays.confirm.deleted")
                    }
                    Button(L("page.overlays.confirm.cancel"), role: .cancel) {
                        confirmChoice = L("page.overlays.confirm.cancelled")
                    }
                },
                message: { Text(L("page.overlays.confirm.message")) })
            // Note: notifications are hosted once at the app root (see
            // `ExampleApp` in main.swift) so a toast posted here survives
            // navigating back to the menu, rather than vanishing with the page.
            .statusBarItems(statusBarItems)
    }

    /// Status bar items change depending on whether a modal is open.
    /// When a modal is presented, ESC closes the modal instead of navigating back.
    private var statusBarItems: [any StatusBarItemProtocol] {
        if showOverlay {
            return [
                StatusBarItem(shortcut: Shortcut.escape, label: L("page.overlays.status.close")) {
                    showOverlay = false
                },
            ]
        } else {
            return [
                StatusBarItem(shortcut: Shortcut.escape, label: L("page.overlays.status.back")) {
                    onBack()
                },
                StatusBarItem(shortcut: Shortcut.arrowsUpDown, label: L("page.overlays.status.nav")),
                StatusBarItem(shortcut: Shortcut.enter, label: L("page.overlays.status.show")),
            ]
        }
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
                Menu(L("page.overlays.selectDemo")) {
                    ForEach(OverlayDemo.allCases, id: \.self) { demo in
                        Button(demo.label) {
                            if demo.isNotification {
                                NotificationService.current.post(
                                    L("page.overlays.alert.successMessage")
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

            DemoSection(L("page.overlays.confirm.section")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.overlays.confirm.explain"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    HStack(spacing: 2) {
                        Button(L("page.overlays.confirm.trigger")) { showConfirm = true }
                        ValueDisplayRow(L("page.overlays.confirm.result"), confirmChoice)
                    }
                }
            }

            DemoSection(L("page.overlays.section.howItWorks")) {
                Text(L("page.overlays.howItWorks.intro"))
                    .foregroundStyle(.palette.foregroundSecondary)
                Text("  .alert(isPresented:)        — \(L("page.overlays.howItWorks.alertLine"))")
                    .foregroundStyle(.palette.foregroundSecondary)
                Text("  .modal(isPresented:)        — \(L("page.overlays.howItWorks.modalLine"))")
                    .foregroundStyle(.palette.foregroundSecondary)
                Text("  NotificationService.current.post() — \(L("page.overlays.howItWorks.notifLine"))")
                    .foregroundStyle(.palette.foregroundSecondary)
                Text(L("page.overlays.howItWorks.summary"))
                    .bold()
                    .foregroundStyle(.palette.accent)
            }

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader(L("menu.item.overlays"))
        }
    }

    // MARK: - Description Panel

    /// Detail panel showing the selected demo's description and API usage.
    private var descriptionPanel: some View {
        Panel(selectedDemo.label, titleColor: .palette.accent) {
            VStack(alignment: .leading, spacing: 1) {
                Text(selectedDemo.description)
                    .foregroundStyle(.palette.foreground)

                Text("")

                Text(L("page.overlays.apiLabel"))
                    .bold()
                    .foregroundStyle(.palette.accent)
                Text("  \(selectedDemo.apiUsage)")
                    .foregroundStyle(.palette.foregroundSecondary)
            }
        }
        .frame(width: 55)
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
            // The button belongs in the FOOTER, not at the bottom of the body.
            // A dialog's body scrolls when the terminal is too short; its footer
            // is pinned. With the button in the body it could be scrolled out of
            // view — the one control the user always needs.
            Dialog(
                title: L("page.overlays.dialog.settingsTitle"),
                borderColor: .palette.border, titleColor: .palette.accent,
                footerAlignment: .trailing
            ) {
                VStack(alignment: .leading) {
                    Text(L("page.overlays.dialog.themeDark")).foregroundStyle(.palette.foreground)
                    Text(L("page.overlays.dialog.languageEnglish")).foregroundStyle(.palette.foreground)
                    Text(L("page.overlays.dialog.notificationsOn")).foregroundStyle(.palette.foreground)
                }
            } footer: {
                dismissButton
            }

        case .dialogWithFooter:
            Dialog(
                title: L("page.overlays.dialog.confirmTitle"),
                borderColor: .palette.border, titleColor: .palette.accent,
                footerAlignment: .trailing
            ) {
                Text(L("page.overlays.dialog.confirmBody")).foregroundStyle(.palette.foreground)
                Text(L("page.overlays.dialog.confirmUndone")).foregroundStyle(.palette.foregroundSecondary)
            } footer: {
                dismissButton
            }

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
                title: L("page.overlays.dialog.proseTitle"),
                borderColor: .palette.border, titleColor: .palette.accent,
                footerAlignment: .trailing
            ) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.overlays.dialog.proseIntro"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text(L("page.overlays.dialog.proseParagraph1"))
                        .foregroundStyle(.palette.foreground)
                    Text(L("page.overlays.dialog.proseParagraph2"))
                        .foregroundStyle(.palette.foreground)
                    Text(L("page.overlays.dialog.proseParagraph3"))
                        .foregroundStyle(.palette.foreground)
                }
            } footer: {
                dismissButton
            }

        case .dialogAuth:
            Dialog(
                title: L("page.overlays.dialog.signInTitle"),
                borderColor: .palette.border, titleColor: .palette.accent,
                footerAlignment: .trailing
            ) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.overlays.dialog.enterCredentials"))
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
                        LabeledContent(L("page.overlays.dialog.username")) {
                            TextField(
                                "", text: $authUsername,
                                prompt: Text(L("page.overlays.dialog.usernamePrompt")))
                        }
                        LabeledContent(L("page.overlays.dialog.password")) {
                            SecureField(
                                "", text: $authPassword,
                                prompt: Text(L("page.overlays.dialog.passwordPrompt")))
                        }
                    }
                }
            } footer: {
                HStack {
                    // Escape cancels, Return/Enter signs in — from anywhere in
                    // the dialog: the credential fields have no onSubmit, so
                    // Return falls through to the default button even while
                    // typing (macOS dialog semantics).
                    Button(L("page.overlays.button.cancel")) {
                        authUsername = ""
                        authPassword = ""
                        showOverlay = false
                    }
                    .keyboardShortcut(.cancelAction)
                    Button(L("page.overlays.button.signIn")) {
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
                title: L("page.overlays.alert.standardTitle"),
                message: L("page.overlays.alert.standardMessage"),
                borderColor: .palette.border,
                titleColor: .palette.accent
            ) { EmptyView() }
        case .alertWarning:
            Alert(
                title: L("page.overlays.alert.warningTitle"),
                message: L("page.overlays.alert.warningMessage"),
                titleColor: .palette.warning
            ) { EmptyView() }
        case .alertError:
            Alert(
                title: L("page.overlays.alert.errorTitle"),
                message: L("page.overlays.alert.errorMessage"),
                titleColor: .palette.error
            ) { EmptyView() }
        case .alertInfo:
            Alert(
                title: L("page.overlays.alert.infoTitle"),
                message: L("page.overlays.alert.infoMessage"),
                titleColor: .palette.info
            ) { EmptyView() }
        case .alertSuccess:
            Alert(
                title: L("page.overlays.alert.successTitle"),
                message: L("page.overlays.alert.successMessage"),
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
        Button(L("page.overlays.button.dismiss")) {
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
            Text(L("page.overlays.modal.title")).bold().foregroundStyle(.palette.accent)
            Text(L("page.overlays.modal.line1")).foregroundStyle(.palette.foreground)
            Text(L("page.overlays.modal.line2")).foregroundStyle(.palette.foregroundSecondary)
            Text(L("page.overlays.modal.line3")).foregroundStyle(.palette.foregroundSecondary)
            dismissButton
        }
        .padding(EdgeInsets(horizontal: 2, vertical: 1))
        .border(color: .palette.border)
    }
}
