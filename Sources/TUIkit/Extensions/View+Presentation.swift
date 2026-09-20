//  🖥️ TUIkit — Terminal UI Kit for Swift
//  View+Presentation.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Alert Presentation

extension View {
    /// Presents an alert when a binding to a Boolean value is true.
    ///
    /// This modifier mirrors SwiftUI's `.alert(isPresented:)` pattern. When
    /// `isPresented` is `true`, the base content is dimmed and the alert is
    /// displayed centered on top.
    ///
    /// Choosing any action closes the alert, so an action does not flip
    /// `isPresented` itself. Escape chooses the `.cancel`-role button.
    ///
    /// ## Example
    ///
    /// ```swift
    /// @State var showAlert = false
    ///
    /// VStack {
    ///     Button("Show Alert") { showAlert = true }
    /// }
    /// .alert("Warning", isPresented: $showAlert) {
    ///     Button("Yes") { save() }
    ///     Button("Cancel", role: .cancel) {}
    /// } message: {
    ///     Text("Are you sure?")
    /// }
    /// ```
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``. A `String` you computed binds to the overload
    /// below and is shown as written.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the alert title.
    ///   - isPresented: A binding to a Boolean value that determines whether
    ///     to present the alert.
    ///   - actions: A ViewBuilder returning the alert action buttons.
    ///   - message: A ViewBuilder returning the alert message content.
    ///   - borderStyle: Custom border style for the alert (TUIkit extension, default: nil).
    ///   - borderColor: Custom border color (TUIkit extension, default: nil).
    ///   - titleColor: Custom title text color (TUIkit extension, default: nil).
    /// - Returns: A view that presents an alert conditionally.
    public func alert<Actions: View, Message: View>(
        _ titleKey: LocalizedStringKey,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: @escaping () -> Actions,
        @ViewBuilder message: @escaping () -> Message,
        borderStyle: BorderStyle? = nil,
        borderColor: Color? = nil,
        titleColor: Color? = nil
    ) -> some View {
        alert(
            titleKey.localized, isPresented: isPresented, actions: actions,
            message: message, borderStyle: borderStyle, borderColor: borderColor,
            titleColor: titleColor)
    }

    /// Presents an alert whose title is displayed as written.
    ///
    /// Generic over `StringProtocol`, which is both SwiftUI's own spelling and
    /// what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey`` for why the concrete-`String` spelling does not.
    ///
    /// - Parameters:
    ///   - title: The alert title.
    ///   - isPresented: A binding to a Boolean value that determines whether
    ///     to present the alert.
    ///   - actions: A ViewBuilder returning the alert action buttons.
    ///   - message: A ViewBuilder returning the alert message content.
    ///   - borderStyle: Custom border style for the alert (TUIkit extension, default: nil).
    ///   - borderColor: Custom border color (TUIkit extension, default: nil).
    ///   - titleColor: Custom title text color (TUIkit extension, default: nil).
    /// - Returns: A view that presents an alert conditionally.
    @_disfavoredOverload
    public func alert<S: StringProtocol, Actions: View, Message: View>(
        _ title: S,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: @escaping () -> Actions,
        @ViewBuilder message: @escaping () -> Message,
        borderStyle: BorderStyle? = nil,
        borderColor: Color? = nil,
        titleColor: Color? = nil
    ) -> some View {
        AlertPresentationModifier<Self, Actions, Message>(
            content: self,
            isPresented: isPresented,
            title: String(title),
            message: message(),
            actions: actions(),
            borderStyle: borderStyle,
            borderColor: borderColor,
            titleColor: titleColor
        )
    }

    /// Presents an alert with title and actions only (no message).
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the alert title.
    ///   - isPresented: A binding to a Boolean value that determines whether
    ///     to present the alert.
    ///   - actions: A ViewBuilder returning the alert action buttons.
    ///   - borderStyle: Optional border style.
    ///   - borderColor: Optional border color.
    ///   - titleColor: Optional title color.
    /// - Returns: A view that presents an alert conditionally.
    public func alert<Actions: View>(
        _ titleKey: LocalizedStringKey,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: @escaping () -> Actions,
        borderStyle: BorderStyle? = nil,
        borderColor: Color? = nil,
        titleColor: Color? = nil
    ) -> some View {
        alert(
            titleKey.localized, isPresented: isPresented, actions: actions,
            borderStyle: borderStyle, borderColor: borderColor, titleColor: titleColor)
    }

    /// Presents an alert with actions only, whose title is shown as written.
    ///
    /// Generic over `StringProtocol` for the same reason as the form above:
    /// that is what keeps a *literal* binding to the key overload rather than
    /// to this one — see ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - title: The alert title.
    ///   - isPresented: A binding to a Boolean value that determines whether
    ///     to present the alert.
    ///   - actions: A ViewBuilder returning the alert action buttons.
    ///   - borderStyle: Optional border style.
    ///   - borderColor: Optional border color.
    ///   - titleColor: Optional title color.
    /// - Returns: A view that presents an alert conditionally.
    @_disfavoredOverload
    public func alert<S: StringProtocol, Actions: View>(
        _ title: S,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: @escaping () -> Actions,
        borderStyle: BorderStyle? = nil,
        borderColor: Color? = nil,
        titleColor: Color? = nil
    ) -> some View {
        AlertPresentationModifier<Self, Actions, EmptyView>(
            content: self,
            isPresented: isPresented,
            title: String(title),
            message: nil,
            actions: actions(),
            borderStyle: borderStyle,
            borderColor: borderColor,
            titleColor: titleColor
        )
    }
}

// MARK: - Confirmation Dialog

extension View {
    /// Presents a confirmation dialog (action sheet) with a message when a
    /// binding is true. Mirrors SwiftUI's `confirmationDialog(_:isPresented:...)`.
    ///
    /// Presented like `.alert` — a centred, dimming overlay dismissible with
    /// Escape — but with the action buttons stacked **vertically** (an action
    /// sheet). A `.cancel`-role button sorts to the bottom.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``. A `String` you computed binds to the overload
    /// below and is shown as written.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the dialog title (suppressed when
    ///     `titleVisibility` is `.hidden`).
    ///   - isPresented: A binding controlling presentation.
    ///   - titleVisibility: Whether the title is shown (default `.automatic`).
    ///   - actions: A ViewBuilder returning the dialog's action buttons.
    ///   - message: A ViewBuilder returning the dialog's message.
    public func confirmationDialog<Actions: View, Message: View>(
        _ titleKey: LocalizedStringKey,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        @ViewBuilder actions: @escaping () -> Actions,
        @ViewBuilder message: @escaping () -> Message
    ) -> some View {
        confirmationDialog(
            titleKey.localized, isPresented: isPresented,
            titleVisibility: titleVisibility, actions: actions, message: message)
    }

    /// Presents a confirmation dialog whose title is displayed as written.
    ///
    /// Generic over `StringProtocol`, which is both SwiftUI's own spelling and
    /// what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey`` for why the concrete-`String` spelling does not.
    @_disfavoredOverload
    public func confirmationDialog<S: StringProtocol, Actions: View, Message: View>(
        _ title: S,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        @ViewBuilder actions: @escaping () -> Actions,
        @ViewBuilder message: @escaping () -> Message
    ) -> some View {
        AlertPresentationModifier<Self, Actions, Message>(
            content: self,
            isPresented: isPresented,
            title: titleVisibility == .hidden ? "" : String(title),
            message: message(),
            actions: actions(),
            borderStyle: nil,
            borderColor: nil,
            titleColor: nil,
            verticalButtons: true
        )
    }

    /// Presents a confirmation dialog (action sheet) with actions only.
    public func confirmationDialog<Actions: View>(
        _ titleKey: LocalizedStringKey,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        @ViewBuilder actions: @escaping () -> Actions
    ) -> some View {
        confirmationDialog(
            titleKey.localized, isPresented: isPresented,
            titleVisibility: titleVisibility, actions: actions)
    }

    /// Presents an actions-only dialog whose title is displayed as written.
    ///
    /// Generic over `StringProtocol` for the same reason as the form above:
    /// that is what keeps a *literal* binding to the key overload rather than
    /// to this one — see ``LocalizedStringKey``.
    @_disfavoredOverload
    public func confirmationDialog<S: StringProtocol, Actions: View>(
        _ title: S,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        @ViewBuilder actions: @escaping () -> Actions
    ) -> some View {
        AlertPresentationModifier<Self, Actions, EmptyView>(
            content: self,
            isPresented: isPresented,
            title: titleVisibility == .hidden ? "" : String(title),
            message: nil,
            actions: actions(),
            borderStyle: nil,
            borderColor: nil,
            titleColor: nil,
            verticalButtons: true
        )
    }
}

// MARK: - App Header

extension View {
    /// Declares the app header content for this view.
    ///
    /// The header is rendered at the top of the terminal, outside the view tree,
    /// similar to the status bar at the bottom. When no `.appHeader` modifier is
    /// present, the header is hidden and no vertical space is reserved.
    ///
    /// ## Example
    ///
    /// ```swift
    /// VStack {
    ///     Text("Page content")
    /// }
    /// .appHeader {
    ///     HStack {
    ///         Text("My App").bold().foregroundStyle(.palette.accent)
    ///         Spacer()
    ///         Text("v1.0").foregroundStyle(.palette.foregroundTertiary)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter content: A ViewBuilder returning the header content.
    /// - Returns: A view that declares the app header content.
    public func appHeader<Header: View>(
        @ViewBuilder content: () -> Header
    ) -> some View {
        AppHeaderModifier(content: self, header: content())
    }
}

// MARK: - Modal Presentation

extension View {
    /// Presents a modal overlay when a binding to a Boolean value is true.
    ///
    /// This modifier dims the base content and displays the provided content
    /// centered on top when `isPresented` is `true`. Use this for custom modal
    /// content that doesn't fit the alert pattern.
    ///
    /// ## Example
    ///
    /// ```swift
    /// @State var showSettings = false
    ///
    /// VStack {
    ///     Button("Settings") { showSettings = true }
    /// }
    /// .modal(isPresented: $showSettings) {
    ///     Dialog(title: "Settings") {
    ///         Text("Option 1")
    ///         Text("Option 2")
    ///         Button("Close") { showSettings = false }
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - isPresented: A binding to a Boolean value that determines whether
    ///     to present the modal.
    ///   - onDismiss: A closure run after the modal is dismissed, or `nil` for
    ///     no callback.
    ///   - content: A ViewBuilder returning the modal content.
    /// - Returns: A view that presents a modal overlay conditionally.
    public func modal<Modal: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Modal
    ) -> some View {
        modalPresentation(
            isPresented: isPresented, style: .sheet, itemKey: nil, onDismiss: onDismiss,
            modal: content())
    }

    /// The one place a modal presentation is assembled — panel or cover, about
    /// an item or about nothing.
    ///
    /// Four call sites: ``modal(isPresented:onDismiss:content:)`` (which
    /// ``sheet(isPresented:onDismiss:content:)`` forwards to),
    /// ``sheet(item:onDismiss:content:)``, and the two `fullScreenCover`
    /// spellings. What they share is not just the modifier but the `onDismiss`
    /// wiring: it fires on the presented → dismissed transition, which covers
    /// every route that clears the binding — a Close button, Escape,
    /// `@Environment(\.dismiss)`, or a programmatic change. Written
    /// per-spelling it was already duplicated once.
    ///
    /// Not the always-on `modal { … }` in `View+Convenience.swift`, which
    /// builds the modifier itself: it has no binding to watch and so nothing
    /// for this wiring to do.
    ///
    /// - Parameters:
    ///   - isPresented: The binding that presents and dismisses.
    ///   - style: Panel over a dimmed page, or the whole content area.
    ///   - itemKey: The presented item's identity key, or `nil` when the
    ///     presentation is about nothing in particular. See
    ///     ``ModalPresentationModifier/itemKey``.
    ///   - onDismiss: Run on the presented → dismissed transition.
    ///   - modal: The content to present.
    private func modalPresentation<Modal: View>(
        isPresented: Binding<Bool>,
        style: ModalPresentationModifier<Self, Modal>.Style,
        itemKey: String?,
        onDismiss: (() -> Void)?,
        modal: Modal
    ) -> some View {
        ModalPresentationModifier(
            content: self,
            isPresented: isPresented,
            modal: modal,
            style: style,
            itemKey: itemKey
        )
        .onChange(of: isPresented.wrappedValue) { wasPresented, isPresentedNow in
            if wasPresented, !isPresentedNow { onDismiss?() }
        }
    }

    /// Presents content modally when a binding to a Boolean value is true.
    ///
    /// A SwiftUI-compatible spelling of ``modal(isPresented:onDismiss:content:)``:
    /// the terminal presents the content as a centred overlay that dims the
    /// background rather than as a sliding sheet, but a call site written against
    /// SwiftUI's `.sheet(isPresented:onDismiss:content:)` works unchanged.
    ///
    /// - Parameters:
    ///   - isPresented: A binding to a Boolean value that determines whether
    ///     to present the sheet.
    ///   - onDismiss: An optional closure run when the sheet is dismissed.
    ///   - content: A ViewBuilder returning the sheet content.
    /// - Returns: A view that presents the content modally.
    public func sheet<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modal(isPresented: isPresented, onDismiss: onDismiss, content: content)
    }

    /// Presents a sheet for a currently-selected item.
    ///
    /// SwiftUI-compatible: a non-`nil` `Identifiable` value presents the sheet;
    /// clearing the binding (or the content setting it to `nil`) dismisses it and
    /// runs `onDismiss`. As with the `isPresented:` form, the terminal presents a
    /// centred, background-dimming overlay rather than a sliding sheet.
    ///
    /// The item's **id is the content's identity**, which is what this form has
    /// over closing over a value and presenting on a flag: change the item and
    /// the sheet is a different view — `@State` back at its initial values,
    /// `onAppear`/`task` firing again — rather than the same view handed a new
    /// row to describe. Moving a selection from one row to another while the
    /// sheet is up used to leave the first row's half-typed draft, scroll
    /// position and selection sitting in the second row's editor. Keep the ids
    /// distinct: two items whose ids are equal are one view, as in SwiftUI.
    ///
    /// ```swift
    /// @State var editing: Row?
    /// List(rows, selection: $sel) { … }
    ///     .sheet(item: $editing) { row in EditView(row) }
    /// ```
    ///
    /// - Parameters:
    ///   - item: A binding to an optional, identifiable item; non-`nil` presents.
    ///   - onDismiss: An optional closure run when the sheet is dismissed.
    ///   - content: A ViewBuilder building the sheet from the unwrapped item.
    /// - Returns: A view that presents a sheet for the selected item.
    public func sheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        let isPresented = Binding<Bool>(
            get: { item.wrappedValue != nil },
            set: { presented in if !presented { item.wrappedValue = nil } }
        )
        // Assembled here rather than through the `isPresented:` spelling, which
        // has no way to name the item: the identity key has to be read from the
        // same binding, at the same moment, as the content built from it.
        return modalPresentation(
            isPresented: isPresented,
            style: .sheet,
            itemKey: item.wrappedValue.map { identityKey($0.id) },
            onDismiss: onDismiss,
            modal: item.wrappedValue.map(content))
    }
}

// MARK: - Full-Screen Cover

extension View {
    /// Presents content covering the whole screen. Matches SwiftUI's
    /// `fullScreenCover(isPresented:onDismiss:content:)`.
    ///
    /// The difference from ``sheet(isPresented:onDismiss:content:)`` is the same
    /// one SwiftUI draws: a sheet is a panel over the (dimmed) page, a cover
    /// replaces it. The cover fills the content area between the app header and
    /// the status bar, nothing of the page shows through, and it cannot be
    /// dragged — there is nowhere for it to go.
    ///
    /// Content smaller than that area is CENTRED in it, as SwiftUI centres it —
    /// unlike a bare ``View/frame(width:height:alignment:)``, which is
    /// top-leading by default here. Add your own `Spacer`s or `frame` alignment
    /// if you want the content pinned to an edge instead.
    ///
    /// Escape dismisses it, as with every presentation.
    ///
    /// - Parameters:
    ///   - isPresented: A binding controlling presentation.
    ///   - onDismiss: An optional closure run when the cover is dismissed.
    ///   - content: A ViewBuilder returning the cover's content.
    public func fullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modalPresentation(
            isPresented: isPresented, style: .fullScreen, itemKey: nil, onDismiss: onDismiss,
            modal: content())
    }

    /// Presents a full-screen cover for a currently-selected item. Matches
    /// SwiftUI's `fullScreenCover(item:onDismiss:content:)`.
    ///
    /// The item's id is the content's identity, exactly as in
    /// ``sheet(item:onDismiss:content:)`` — a cover shown for a different item
    /// starts with fresh state.
    ///
    /// - Parameters:
    ///   - item: A binding to an optional, identifiable item; non-`nil` presents.
    ///   - onDismiss: An optional closure run when the cover is dismissed.
    ///   - content: A ViewBuilder building the cover from the unwrapped item.
    public func fullScreenCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        let isPresented = Binding<Bool>(
            get: { item.wrappedValue != nil },
            set: { presented in if !presented { item.wrappedValue = nil } }
        )
        // Keyed by the item, for the reason ``sheet(item:onDismiss:content:)``
        // states: a cover reopened for a different item is a different view.
        return modalPresentation(
            isPresented: isPresented,
            style: .fullScreen,
            itemKey: item.wrappedValue.map { identityKey($0.id) },
            onDismiss: onDismiss,
            modal: item.wrappedValue.map(content))
    }
}

// MARK: - Notification Host

extension View {
    /// Makes this view the notification rendering host.
    ///
    /// Attach this modifier **once, at the root of your view tree** (e.g. on the
    /// content of your `WindowGroup`). Notifications are posted to a process-wide
    /// ``NotificationService`` and live there until they expire, independently of
    /// the view tree — so the host's placement decides only *where they are
    /// drawn*. Hosting at the root means a toast posted on one screen stays
    /// visible until it expires even after the user navigates elsewhere, which is
    /// almost always what transient status messages want. Hosting it on a single
    /// screen instead scopes the toast to that screen: it disappears the moment
    /// you navigate away (the notification is still active, but nothing is drawing
    /// it). Apply it on exactly one view — two hosts would draw every toast twice.
    ///
    /// It reads active notifications from the environment's ``NotificationService``
    /// and renders them as a stacked overlay at the configured position.
    ///
    /// Notifications are posted via the service, not declared in the view tree:
    ///
    /// ```swift
    /// // At the root:
    /// ContentView()
    ///     .notificationHost()
    ///
    /// // Anywhere in the hierarchy:
    /// NotificationService.current.post("Saved!")
    /// ```
    ///
    /// The base content remains fully interactive — notifications do not dim
    /// or block the background.
    ///
    /// - Parameter width: Fixed width of each notification box in characters (default: 40).
    /// - Returns: A view that renders notifications from the environment service.
    public func notificationHost(
        width: Int = 40
    ) -> some View {
        NotificationHostModifier(
            content: self,
            width: width
        )
    }
}
