//  🖥️ TUIkit — Terminal UI Kit for Swift
//  View+AlertPresenting.swift
//
//  The DATA-DRIVEN alert spellings: `presenting:` hands the value to the
//  builders, `error:` takes the title and message off a `LocalizedError`.
//
//  Separate from `View+Presentation.swift` (which is already at the 500-line
//  guideline) rather than because they are a different feature: every one of
//  these is the Boolean form with its arguments pre-chewed.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - alert(_:isPresented:presenting:…)

extension View {
    /// Presents an alert built from `data` when `isPresented` is true.
    ///
    /// The point of `presenting:` over closing over the value yourself is the
    /// **dismissal race**. An alert's buttons act on something — a file to
    /// delete, a row to discard — and that something is usually the same
    /// `@State` the alert's presence is derived from. Closing over it means the
    /// builders run on whatever the value is NOW, including the frame after it
    /// became `nil`; taking it as a parameter means the alert is not presented
    /// at all unless there is something to present.
    ///
    /// So `isPresented && data != nil` is the real condition, and a `nil` while
    /// the flag is still true draws nothing rather than an alert about nothing.
    ///
    /// ```swift
    /// .alert("Delete \(name)?", isPresented: $confirming, presenting: doomed) { file in
    ///     Button("Delete", role: .destructive) { delete(file) }
    ///     Button("Cancel", role: .cancel) {}
    /// } message: { file in
    ///     Text("\(file.name) cannot be recovered.")
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - titleKey: The alert title, looked up as a localization key.
    ///   - isPresented: Whether to present the alert.
    ///   - data: The value to present. `nil` withholds the alert.
    ///   - actions: The alert's buttons, built from `data`.
    ///   - message: The alert's message, built from `data`.
    /// - Returns: A view that presents an alert conditionally.
    public func alert<Actions: View, Message: View, T>(
        _ titleKey: LocalizedStringKey,
        isPresented: Binding<Bool>,
        presenting data: T?,
        @ViewBuilder actions: @escaping (T) -> Actions,
        @ViewBuilder message: @escaping (T) -> Message
    ) -> some View {
        alert(
            titleKey.localized, isPresented: isPresented, presenting: data,
            actions: actions, message: message)
    }

    /// Presents an alert built from `data`, with a title shown as written.
    ///
    /// Generic over `StringProtocol`, which is both SwiftUI's own spelling and
    /// what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey`` for why the concrete-`String` spelling does not.
    ///
    /// - Parameters:
    ///   - title: The alert title.
    ///   - isPresented: Whether to present the alert.
    ///   - data: The value to present. `nil` withholds the alert.
    ///   - actions: The alert's buttons, built from `data`.
    ///   - message: The alert's message, built from `data`.
    /// - Returns: A view that presents an alert conditionally.
    @_disfavoredOverload
    public func alert<S: StringProtocol, Actions: View, Message: View, T>(
        _ title: S,
        isPresented: Binding<Bool>,
        presenting data: T?,
        @ViewBuilder actions: @escaping (T) -> Actions,
        @ViewBuilder message: @escaping (T) -> Message
    ) -> some View {
        alert(
            title, isPresented: isPresented.andPresent(data),
            actions: { if let data { actions(data) } },
            message: { if let data { message(data) } })
    }

    /// Presents an alert built from `data`, with buttons and no message.
    ///
    /// - Parameters:
    ///   - titleKey: The alert title, looked up as a localization key.
    ///   - isPresented: Whether to present the alert.
    ///   - data: The value to present. `nil` withholds the alert.
    ///   - actions: The alert's buttons, built from `data`.
    /// - Returns: A view that presents an alert conditionally.
    public func alert<Actions: View, T>(
        _ titleKey: LocalizedStringKey,
        isPresented: Binding<Bool>,
        presenting data: T?,
        @ViewBuilder actions: @escaping (T) -> Actions
    ) -> some View {
        alert(titleKey.localized, isPresented: isPresented, presenting: data, actions: actions)
    }

    /// Presents an alert built from `data` with buttons and no message, with a
    /// title shown as written.
    ///
    /// Generic over `StringProtocol` for the same reason as the form above:
    /// that is what keeps a *literal* binding to the key overload rather than
    /// to this one — see ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - title: The alert title.
    ///   - isPresented: Whether to present the alert.
    ///   - data: The value to present. `nil` withholds the alert.
    ///   - actions: The alert's buttons, built from `data`.
    /// - Returns: A view that presents an alert conditionally.
    @_disfavoredOverload
    public func alert<S: StringProtocol, Actions: View, T>(
        _ title: S,
        isPresented: Binding<Bool>,
        presenting data: T?,
        @ViewBuilder actions: @escaping (T) -> Actions
    ) -> some View {
        alert(
            title, isPresented: isPresented.andPresent(data),
            actions: { if let data { actions(data) } })
    }
}

// MARK: - alert(isPresented:error:…)

extension View {
    /// Presents an alert describing `error`.
    ///
    /// The title is the error's `errorDescription` and the message its
    /// `recoverySuggestion` — which is what those two properties are FOR, and
    /// why this spelling exists rather than "pass the strings yourself": an
    /// error that has been given a decent `LocalizedError` conformance already
    /// knows how it should read, in whatever language the app is running in.
    /// An error with no recovery suggestion gets a title and buttons alone.
    ///
    /// - Parameters:
    ///   - isPresented: Whether to present the alert.
    ///   - error: The error to describe. `nil` withholds the alert.
    ///   - actions: The alert's buttons.
    /// - Returns: A view that presents an alert conditionally.
    public func alert<E: LocalizedError, Actions: View>(
        isPresented: Binding<Bool>,
        error: E?,
        @ViewBuilder actions: @escaping () -> Actions
    ) -> some View {
        alert(
            error?.alertTitle ?? "", isPresented: isPresented.andPresent(error),
            actions: actions,
            // Not `Text(…)?`: an empty message and no message are different
            // pictures — the alert would keep a blank line for one.
            message: { if let suggestion = error?.recoverySuggestion { Text(suggestion) } })
    }

    /// Presents an alert describing `error`, with a message of your own.
    ///
    /// The asymmetry with ``alert(isPresented:error:actions:)`` — this form's
    /// `actions` takes the error, that one's does not — is SwiftUI's, kept so
    /// its source compiles verbatim.
    ///
    /// - Parameters:
    ///   - isPresented: Whether to present the alert.
    ///   - error: The error to describe. `nil` withholds the alert.
    ///   - actions: The alert's buttons, built from the error.
    ///   - message: The alert's message, built from the error.
    /// - Returns: A view that presents an alert conditionally.
    public func alert<E: LocalizedError, Actions: View, Message: View>(
        isPresented: Binding<Bool>,
        error: E?,
        @ViewBuilder actions: @escaping (E) -> Actions,
        @ViewBuilder message: @escaping (E) -> Message
    ) -> some View {
        alert(
            error?.alertTitle ?? "", isPresented: isPresented.andPresent(error),
            actions: { if let error { actions(error) } },
            message: { if let error { message(error) } })
    }
}

// MARK: - confirmationDialog(_:isPresented:titleVisibility:presenting:…)

extension View {
    /// Presents a confirmation dialog built from `data`.
    ///
    /// The `alert` reasoning applies unchanged — see
    /// ``alert(_:isPresented:presenting:actions:message:)-(LocalizedStringKey,_,_,_,_)`` for why the value
    /// is a parameter rather than something the builders close over.
    ///
    /// - Parameters:
    ///   - titleKey: The dialog title, looked up as a localization key.
    ///   - isPresented: Whether to present the dialog.
    ///   - titleVisibility: Whether the title is shown.
    ///   - data: The value to present. `nil` withholds the dialog.
    ///   - actions: The dialog's buttons, built from `data`.
    ///   - message: The dialog's message, built from `data`.
    /// - Returns: A view that presents a confirmation dialog conditionally.
    public func confirmationDialog<Actions: View, Message: View, T>(
        _ titleKey: LocalizedStringKey,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        presenting data: T?,
        @ViewBuilder actions: @escaping (T) -> Actions,
        @ViewBuilder message: @escaping (T) -> Message
    ) -> some View {
        confirmationDialog(
            titleKey.localized, isPresented: isPresented, titleVisibility: titleVisibility,
            presenting: data, actions: actions, message: message)
    }

    /// Presents a confirmation dialog built from `data`, titled as written.
    ///
    /// Generic over `StringProtocol`, which is both SwiftUI's own spelling and
    /// what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey`` for why the concrete-`String` spelling does not.
    ///
    /// - Parameters:
    ///   - title: The dialog title.
    ///   - isPresented: Whether to present the dialog.
    ///   - titleVisibility: Whether the title is shown.
    ///   - data: The value to present. `nil` withholds the dialog.
    ///   - actions: The dialog's buttons, built from `data`.
    ///   - message: The dialog's message, built from `data`.
    /// - Returns: A view that presents a confirmation dialog conditionally.
    @_disfavoredOverload
    public func confirmationDialog<S: StringProtocol, Actions: View, Message: View, T>(
        _ title: S,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        presenting data: T?,
        @ViewBuilder actions: @escaping (T) -> Actions,
        @ViewBuilder message: @escaping (T) -> Message
    ) -> some View {
        confirmationDialog(
            title, isPresented: isPresented.andPresent(data), titleVisibility: titleVisibility,
            actions: { if let data { actions(data) } },
            message: { if let data { message(data) } })
    }

    /// Presents a confirmation dialog built from `data`, with no message.
    ///
    /// - Parameters:
    ///   - titleKey: The dialog title, looked up as a localization key.
    ///   - isPresented: Whether to present the dialog.
    ///   - titleVisibility: Whether the title is shown.
    ///   - data: The value to present. `nil` withholds the dialog.
    ///   - actions: The dialog's buttons, built from `data`.
    /// - Returns: A view that presents a confirmation dialog conditionally.
    public func confirmationDialog<Actions: View, T>(
        _ titleKey: LocalizedStringKey,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        presenting data: T?,
        @ViewBuilder actions: @escaping (T) -> Actions
    ) -> some View {
        confirmationDialog(
            titleKey.localized, isPresented: isPresented, titleVisibility: titleVisibility,
            presenting: data, actions: actions)
    }

    /// Presents a confirmation dialog built from `data` with no message, titled
    /// as written.
    ///
    /// Generic over `StringProtocol` for the same reason as the form above:
    /// that is what keeps a *literal* binding to the key overload rather than
    /// to this one — see ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - title: The dialog title.
    ///   - isPresented: Whether to present the dialog.
    ///   - titleVisibility: Whether the title is shown.
    ///   - data: The value to present. `nil` withholds the dialog.
    ///   - actions: The dialog's buttons, built from `data`.
    /// - Returns: A view that presents a confirmation dialog conditionally.
    @_disfavoredOverload
    public func confirmationDialog<S: StringProtocol, Actions: View, T>(
        _ title: S,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        presenting data: T?,
        @ViewBuilder actions: @escaping (T) -> Actions
    ) -> some View {
        confirmationDialog(
            title, isPresented: isPresented.andPresent(data), titleVisibility: titleVisibility,
            actions: { if let data { actions(data) } })
    }
}

// MARK: - Support

extension LocalizedError {
    /// The title an alert describing this error carries.
    ///
    /// `errorDescription` is the property a `LocalizedError` exists to provide,
    /// but it is Optional and a conformance may leave it out. `localizedDescription`
    /// is never nil — it falls back through Foundation's own machinery — so an
    /// alert always has a title rather than an empty bar.
    var alertTitle: String { errorDescription ?? localizedDescription }
}

extension Binding<Bool> {
    /// This flag, but false whenever there is nothing to present.
    ///
    /// Reads conjoin; writes pass straight through, so choosing a button still
    /// clears the caller's own flag.
    func andPresent<T>(_ value: T?) -> Binding<Bool> {
        Binding(
            get: { self.wrappedValue && value != nil },
            set: { self.wrappedValue = $0 })
    }
}
