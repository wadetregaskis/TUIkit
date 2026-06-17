//  🖥️ TUIKit — Terminal UI Kit for Swift
//  View+Convenience.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Modal

extension View {
    /// Presents this view as an always-on modal dialog over dimmed content.
    ///
    /// The unconditional counterpart to ``modal(isPresented:content:)`` — for
    /// content that is *always* modal while it's in the tree. It goes through the
    /// same presentation path: the background is dimmed **and made inert** (its
    /// focusables and key/mouse handlers are isolated), a dedicated focus section
    /// captures the keyboard, and the modal is centred on the screen. So the
    /// background can't be interacted with while the modal is up — the same
    /// guarantee the binding-based form gives.
    ///
    /// > Important: Do **not** present a `Dialog` with bare `.dimmed().overlay()`.
    /// > That only dims the *look* of the background; it leaves the background
    /// > focusable and clickable, and the dialog never captures focus. Use this
    /// > modifier (or ``modal(isPresented:content:)`` / ``alert(title:isPresented:…)``).
    ///
    /// ## Example
    ///
    /// ```swift
    /// mainContent.modal {
    ///     Dialog(title: "Settings") {
    ///         Text("Setting 1")
    ///         Text("Setting 2")
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter content: The modal content to display.
    /// - Returns: A view with the modal overlay.
    public func modal<Modal: View>(
        @ViewBuilder content: () -> Modal
    ) -> some View {
        ModalPresentationModifier(
            content: self,
            isPresented: .constant(true),
            modal: content()
        )
    }
}

// MARK: - Type Erasure

extension View {
    /// Wraps this view in an AnyView for type erasure.
    ///
    /// Use this when you need to return different view types from
    /// conditional branches.
    public func asAnyView() -> AnyView {
        AnyView(self)
    }
}
