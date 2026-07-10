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
    @State var menuSelection: Int = 0
    @State var showOverlay: Bool = false
    @State var authUsername: String = ""
    @State var authPassword: String = ""

    /// Callback to navigate back to the main menu.
    let onBack: () -> Void

    /// The currently selected demo variant.
    private var selectedDemo: OverlayDemo {
        OverlayDemo.allCases[menuSelection]
    }

    var body: some View {
        backgroundContent
            .modal(isPresented: $showOverlay) {
                overlayContent(for: selectedDemo)
            }
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
            HStack(spacing: 3) {
                // Left: Demo menu
                Menu(
                    title: L("page.overlays.selectDemo"),
                    items: OverlayDemo.allCases.map { demo in
                        MenuItem(label: demo.label, shortcut: nil)
                    },
                    selection: $menuSelection,
                    onSelect: { _ in
                        if selectedDemo.isNotification {
                            NotificationService.current.post(
                                L("page.overlays.alert.successMessage")
                            )
                        } else {
                            showOverlay = true
                        }
                    },
                    selectedColor: .palette.accent,
                    borderColor: .palette.border
                )

                // Right: Description of selected demo
                descriptionPanel
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
            DemoAppHeader(L("page.overlays.header"))
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
            Dialog(title: L("page.overlays.dialog.settingsTitle"), borderColor: .palette.border, titleColor: .palette.accent) {
                VStack(alignment: .leading) {
                    Text(L("page.overlays.dialog.themeDark")).foregroundStyle(.palette.foreground)
                    Text(L("page.overlays.dialog.languageEnglish")).foregroundStyle(.palette.foreground)
                    Text(L("page.overlays.dialog.notificationsOn")).foregroundStyle(.palette.foreground)
                    Text("")
                    dismissButton
                }
            }
            .frame(width: 50)

        case .dialogWithFooter:
            Dialog(title: L("page.overlays.dialog.confirmTitle"), borderColor: .palette.border, titleColor: .palette.accent) {
                Text(L("page.overlays.dialog.confirmBody")).foregroundStyle(.palette.foreground)
                Text(L("page.overlays.dialog.confirmUndone")).foregroundStyle(.palette.foregroundSecondary)
            } footer: {
                dismissButton
            }
            .frame(width: 50)

        case .dialogAuth:
            Dialog(title: L("page.overlays.dialog.signInTitle"), borderColor: .palette.border, titleColor: .palette.accent) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.overlays.dialog.enterCredentials"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    TextField(L("page.overlays.dialog.username"), text: $authUsername, prompt: Text(L("page.overlays.dialog.usernamePrompt")))
                    SecureField(L("page.overlays.dialog.password"), text: $authPassword, prompt: Text(L("page.overlays.dialog.passwordPrompt")))
                }
            } footer: {
                HStack {
                    Spacer()
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
            .frame(width: 55)

        case .modalCustom:
            // No explicit frame — the modal sizes to its content. To
            // right-align the Dismiss button without the usual
            // `HStack { Spacer; Button }` (whose flexible Spacer stretches
            // the modal to fill the screen), we push the button right with
            // an explicit leading-padding equal to the natural max text
            // width minus the rendered button width.
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
            ) { EmptyView() }.frame(width: 60)
        case .alertWarning:
            Alert(
                title: L("page.overlays.alert.warningTitle"),
                message: L("page.overlays.alert.warningMessage"),
                titleColor: .palette.warning
            ) { EmptyView() }.frame(width: 60)
        case .alertError:
            Alert(
                title: L("page.overlays.alert.errorTitle"),
                message: L("page.overlays.alert.errorMessage"),
                titleColor: .palette.error
            ) { EmptyView() }.frame(width: 60)
        case .alertInfo:
            Alert(
                title: L("page.overlays.alert.infoTitle"),
                message: L("page.overlays.alert.infoMessage"),
                titleColor: .palette.info
            ) { EmptyView() }.frame(width: 60)
        case .alertSuccess:
            Alert(
                title: L("page.overlays.alert.successTitle"),
                message: L("page.overlays.alert.successMessage"),
                titleColor: .palette.success
            ) { EmptyView() }.frame(width: 60)
        default:
            EmptyView()
        }
    }

    /// Reusable right-aligned dismiss button for the Dialog variants. (The Alert
    /// variants take no actions — they are dismissed with Escape, shown in the
    /// status bar — so they pass `EmptyView()` rather than this.)
    private var dismissButton: some View {
        HStack {
            Spacer()
            Button(L("page.overlays.button.dismiss")) {
                showOverlay = false
            }
            .buttonStyle(.primary)
        }
    }

    /// The "Modal (Custom)" body. Computes the natural max-text width of
    /// the body lines and pushes the Dismiss button right by exactly the
    /// gap that's left after subtracting the rendered button width — so
    /// the modal sizes to its content but the button still sits at the
    /// trailing edge of that content. (A regular `HStack { Spacer; Button }`
    /// would do the same trick, but in TUIkit's current layout model the
    /// HStack's flexible Spacer stretches the parent VStack to the full
    /// screen width, defeating the whole point of "size-to-fit".)
    private var modalCustomBody: some View {
        let title = L("page.overlays.modal.title")
        let line1 = L("page.overlays.modal.line1")
        let line2 = L("page.overlays.modal.line2")
        let line3 = L("page.overlays.modal.line3")
        let dismissLabel = L("page.overlays.button.dismiss")
        let lines = [title, line1, line2, line3]
        let maxLineWidth = lines.map(\.count).max() ?? 0
        // The .primary button style wraps the label in two side caps
        // (▐ … ▌) and a space of inner padding on each side.
        let buttonRenderedWidth = dismissLabel.count + 4
        let leadingPad = max(0, maxLineWidth - buttonRenderedWidth)

        return VStack(alignment: .leading, spacing: 1) {
            Text(title).bold().foregroundStyle(.palette.accent)
            Text("")
            Text(line1).foregroundStyle(.palette.foreground)
            Text(line2).foregroundStyle(.palette.foregroundSecondary)
            Text(line3).foregroundStyle(.palette.foregroundSecondary)
            Text("")
            Button(dismissLabel) {
                showOverlay = false
            }
            .buttonStyle(.primary)
            .padding(.leading, leadingPad)
        }
        .padding(EdgeInsets(horizontal: 2, vertical: 1))
        .border(color: .palette.border)
    }
}
